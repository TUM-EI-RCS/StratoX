--  Based on AdaCore's Ada Drivers Library,
--  see https://github.com/AdaCore/Ada_Drivers_Library,
--  checkout 93b5f269341f970698af18f9182fac82a0be66c3.
--  Copyright (C) Adacore
--
--  Tailored to StratoX project.
--  Author: Martin Becker (becker@rcs.ei.tum.de)
with Ada.Unchecked_Conversion;
with Ada.Real_Time;   use Ada.Real_Time;
with STM32_SVD.SDIO;  use STM32_SVD.SDIO;
with System;          use System;

package body STM32.SDMMC is

   BLOCKLEN : constant := 512; -- SD Version 2.0 (High capacity) does only allow blocks of this size

   --  Mask for errors Card Status R1 (OCR Register)
   SD_OCR_ADDR_OUT_OF_RANGE     : constant := 16#8000_0000#;
   SD_OCR_ADDR_MISALIGNED       : constant := 16#4000_0000#;
   SD_OCR_BLOCK_LEN_ERR         : constant := 16#2000_0000#;
   SD_OCR_ERASE_SEQ_ERR         : constant := 16#1000_0000#;
   SD_OCR_BAD_ERASE_PARAM       : constant := 16#0800_0000#;
   SD_OCR_WRITE_PROT_VIOLATION  : constant := 16#0400_0000#;
   SD_OCR_LOCK_UNLOCK_FAILED    : constant := 16#0100_0000#;
   SD_OCR_COM_CRC_FAILED        : constant := 16#0080_0000#;
   SD_OCR_ILLEGAL_CMD           : constant := 16#0040_0000#;
   SD_OCR_CARD_ECC_FAILED       : constant := 16#0020_0000#;
   SD_OCR_CC_ERROR              : constant := 16#0010_0000#;
   SD_OCR_GENERAL_UNKNOWN_ERROR : constant := 16#0008_0000#;
   SD_OCR_STREAM_READ_UNDERRUN  : constant := 16#0004_0000#;
   SD_OCR_STREAM_WRITE_UNDERRUN : constant := 16#0002_0000#;
   SD_OCR_CID_CSD_OVERWRITE     : constant := 16#0001_0000#;
   SD_OCR_WP_ERASE_SKIP         : constant := 16#0000_8000#;
   SD_OCR_CARD_ECC_DISABLED     : constant := 16#0000_4000#;
   SD_OCR_ERASE_RESET           : constant := 16#0000_2000#;
   SD_OCR_AKE_SEQ_ERROR         : constant := 16#0000_0008#;
   SD_OCR_ERRORMASK             : constant := 16#FDFF_E008#;

   --  Masks for R6 responses.
   SD_R6_General_Unknown_Error : constant := 16#0000_2000#;
   SD_R6_Illegal_Cmd           : constant := 16#0000_4000#;
   SD_R6_Com_CRC_Failed        : constant := 16#0000_8000#;

   SD_Voltage_Window_SD        : constant := 16#8010_0000#;
   SD_High_Capacity            : constant := 16#4000_0000#;
   SD_Std_Capacity             : constant := 16#0000_0000#;
   SD_Check_Pattern            : constant := 16#0000_01AA#;

   SD_MAX_VOLT_TRIAL           : constant := 16#0000_FFFF#;

   SD_WIDE_BUS_SUPPORT         : constant := 16#0004_0000#;
   SD_SINGLE_BUS_SUPPORT       : constant := 16#0001_0000#;
   SD_CARD_LOCKED              : constant := 16#0200_0000#;

   SD_DATATIMEOUT              : constant := 16#FFFF_FFFF#;
   SD_0TO7BITS                 : constant := 16#0000_00FF#;
   SD_8TO715ITS                : constant := 16#0000_FF00#;
   SD_16TO23BITS               : constant := 16#00FF_0000#;
   SD_24TO31BITS               : constant := 16#FF00_0000#;

   type SD_SCR is array (1 .. 2) of Word;

   procedure Send_Command
     (Controller         : in out SDMMC_Controller;
      Command_Index      : SDMMC_Command;
      Argument           : Word;
      Response           : WAITRESP_Field;
      CPSM               : Boolean;
      Wait_For_Interrupt : Boolean);

   procedure Configure_Data
     (Controller         : in out SDMMC_Controller;
      Data_Length        : UInt25; -- TODO: Pre => multiple of data_block_size
      Data_Block_Size    : DBLOCKSIZE_Field;
      Transfer_Direction : Data_Direction;
      Transfer_Mode      : DTMODE_Field;
      DPSM               : Boolean;
      DMA_Enabled        : Boolean);

   --function Read_FIFO
   --  (Controller : in out SDMMC_Controller) return Word;

   procedure Write_FIFO
     (Controller : in out SDMMC_Controller; data : Word);

   function Command_Error
     (Controller : in out SDMMC_Controller) return SD_Error;

   function Response_R1_Error
     (Controller    : in out SDMMC_Controller;
      Command_Index : SDMMC_Command) return SD_Error;
   --  Checks for error conditions for R1 response

   function Response_R2_Error
     (Controller : in out SDMMC_Controller) return SD_Error;
   --  Checks for error conditions for R2 (CID or CSD) response.

   function Response_R3_Error
     (Controller : in out SDMMC_Controller) return SD_Error;
   --  Checks for error conditions for R3 (OCR) response.

   function Response_R6_Error
     (Controller    : in out SDMMC_Controller;
      Command_Index : SDMMC_Command;
      RCA           :    out Word) return SD_Error;

   function Response_R7_Error
     (Controller : in out SDMMC_Controller) return SD_Error;
   --  Checks for error conditions for R7 response.

   function SD_Select_Deselect
     (Controller : in out SDMMC_Controller) return SD_Error;

   function Power_On
     (Controller : in out SDMMC_Controller) return SD_Error;

   function Power_Off
     (Controller : in out SDMMC_Controller) return SD_Error;

   function Initialize_Cards
     (Controller : in out SDMMC_Controller) return SD_Error;

   function Read_Card_Info
     (Controller : in out SDMMC_Controller;
      Info       :    out Card_Information) return SD_Error;

   function Find_SCR
     (Controller : in out SDMMC_Controller;
      SCR        :    out SD_SCR) return SD_Error;

   function Disable_Wide_Bus
     (Controller : in out SDMMC_Controller) return SD_Error;

   function Enable_Wide_Bus
     (Controller : in out SDMMC_Controller) return SD_Error;

   ------------------------
   -- Clear_Static_Flags --
   ------------------------

   procedure Clear_Static_Flags (Controller : in out SDMMC_Controller)
   is
   begin
      Controller.Periph.ICR :=
        (CCRCFAILC => True,
         DCRCFAILC => True,
         CTIMEOUTC => True,
         DTIMEOUTC => True,
         TXUNDERRC => True,
         RXOVERRC  => True,
         CMDRENDC  => True,
         CMDSENTC  => True,
         DATAENDC  => True,
         STBITERRC => True,
         DBCKENDC  => True,
         SDIOITC   => True,
         CEATAENDC => True,
         others    => <>);
   end Clear_Static_Flags;

   ----------------
   -- Clear_Flag (interrupts) --
   ----------------

   procedure Clear_Flag
     (Controller : in out SDMMC_Controller;
      Flag       : SDMMC_Clearable_Flags)
   is
   begin
      case Flag is
         when Data_End =>
            Controller.Periph.ICR.DATAENDC  := True;
         when Data_CRC_Fail =>
            Controller.Periph.ICR.DCRCFAILC := True;
         when Data_Timeout =>
            Controller.Periph.ICR.DTIMEOUTC := True;
         when RX_Overrun =>
            Controller.Periph.ICR.RXOVERRC  := True;
         when TX_Underrun =>
            Controller.Periph.ICR.TXUNDERRC := True;
      end case;
   end Clear_Flag;

   ----------------------
   -- Enable_Interrupt --
   ----------------------

   procedure Enable_Interrupt
     (Controller : in out SDMMC_Controller;
      Interrupt  : SDMMC_Interrupts)
   is
   begin
      case Interrupt is
         when Data_End_Interrupt =>
            Controller.Periph.MASK.DATAENDIE   := True;
         when Data_CRC_Fail_Interrupt =>
            Controller.Periph.MASK.DCRCFAILIE  := True;
         when Data_Timeout_Interrupt =>
            Controller.Periph.MASK.DTIMEOUTIE  := True;
         when TX_FIFO_Empty_Interrupt =>
            Controller.Periph.MASK.TXFIFOEIE   := True;
         when RX_FIFO_Full_Interrupt =>
            Controller.Periph.MASK.RXFIFOFIE   := True;
         when TX_Underrun_Interrupt =>
            Controller.Periph.MASK.TXUNDERRIE  := True;
         when RX_Overrun_Interrupt =>
            Controller.Periph.MASK.RXOVERRIE   := True;
      end case;
   end Enable_Interrupt;

   -----------------------
   -- Disable_Interrupt --
   -----------------------

   procedure Disable_Interrupt
     (Controller : in out SDMMC_Controller;
      Interrupt  : SDMMC_Interrupts)
   is
   begin
      case Interrupt is
         when Data_End_Interrupt =>
            Controller.Periph.MASK.DATAENDIE   := False;
         when Data_CRC_Fail_Interrupt =>
            Controller.Periph.MASK.DCRCFAILIE  := False;
         when Data_Timeout_Interrupt =>
            Controller.Periph.MASK.DTIMEOUTIE  := False;
         when TX_FIFO_Empty_Interrupt =>
            Controller.Periph.MASK.TXFIFOEIE   := False;
         when RX_FIFO_Full_Interrupt =>
            Controller.Periph.MASK.RXFIFOFIE   := False;
         when TX_Underrun_Interrupt =>
            Controller.Periph.MASK.TXUNDERRIE  := False;
         when RX_Overrun_Interrupt =>
            Controller.Periph.MASK.RXOVERRIE   := False;
      end case;
   end Disable_Interrupt;

   ------------------
   -- Send_Command --
   ------------------

   procedure Send_Command
     (Controller         : in out SDMMC_Controller;
      Command_Index      : SDMMC_Command;
      Argument           : Word;
      Response           : WAITRESP_Field;
      CPSM               : Boolean; -- command path state machine enable
      Wait_For_Interrupt : Boolean)
   is
      CMD : CMD_Register  := Controller.Periph.CMD;
   begin
      Controller.Periph.ARG := Argument;
      CMD.CMDINDEX := CMD_CMDINDEX_Field (Command_Index);
      CMD.WAITRESP := Response;
      CMD.WAITINT  := Wait_For_Interrupt;
      CMD.CPSMEN   := CPSM;
      Controller.Periph.CMD := CMD;
   end Send_Command;

   --------------------
   -- Configure_Data --
   --------------------

   procedure Configure_Data
     (Controller         : in out SDMMC_Controller;
      Data_Length        : UInt25;
      Data_Block_Size    : DBLOCKSIZE_Field;
      Transfer_Direction : Data_Direction;
      Transfer_Mode      : DTMODE_Field;
      DPSM               : Boolean;
      DMA_Enabled        : Boolean)
   is
      Tmp : DCTRL_Register := Controller.Periph.DCTRL;
   begin
      Controller.Periph.DLEN.DATALENGTH  := Data_Length;
      --  DCTRL cannot be written during 3 SDMMCCLK (48MHz) clock periods
      --  Minimum wait time is 1 Milliseconds, so let's do that
      delay until Clock + Milliseconds (1);
      Tmp.DTDIR      :=
        (if Transfer_Direction = Read then Card_To_Controller
         else Controller_To_Card);
      Tmp.DTMODE     := Transfer_Mode;
      Tmp.DBLOCKSIZE := Data_Block_Size;
      Tmp.DTEN       := DPSM;
      Tmp.DMAEN      := DMA_Enabled;
      Controller.Periph.DCTRL := Tmp;
   end Configure_Data;

   ---------------
   --Write_FIFO --
   ---------------

   procedure Write_FIFO
     (Controller : in out SDMMC_Controller; data : Word) is
   begin
      Controller.Periph.FIFO := data;
   end Write_FIFO;

   ---------------
   -- Read_FIFO --
   ---------------

   function Read_FIFO
     (Controller : in out SDMMC_Controller) return Word
   is
   begin
      return Controller.Periph.FIFO;
   end Read_FIFO;

   -------------------
   -- Command_Error --
   -------------------

   function Command_Error
     (Controller : in out SDMMC_Controller) return SD_Error
   is
      Start : constant Time := Clock;
   begin
      while not Controller.Periph.STA.CMDSENT loop
         if Clock - Start > Milliseconds (1000) then
            return Timeout_Error;
         end if;
      end loop;

      Clear_Static_Flags (Controller);

      return OK;
   end Command_Error;

   -----------------------
   -- Response_R1_Error --
   -----------------------

   function Response_R1_Error
     (Controller    : in out SDMMC_Controller;
      Command_Index : SDMMC_Command) return SD_Error
   is
      Start   : constant Time := Clock;
      Timeout : Boolean := False;
      R1      : Word;
   begin
      while not Controller.Periph.STA.CCRCFAIL
        and then not Controller.Periph.STA.CMDREND
        and then not Controller.Periph.STA.CTIMEOUT
      loop
         if Clock - Start > Milliseconds (1000) then
            Timeout := True;

            exit;
         end if;
      end loop;

      if Timeout or else Controller.Periph.STA.CTIMEOUT then
         --  Card is not v2.0 compliant or card does not support the set
         --  voltage range
         Controller.Periph.ICR.CTIMEOUTC := True;

         return Timeout_Error;

      elsif Controller.Periph.STA.CCRCFAIL then
         Controller.Periph.ICR.CCRCFAILC := True;

         return CRC_Check_Fail;
      end if;

      if SDMMC_Command (Controller.Periph.RESPCMD.RESPCMD) /=
        Command_Index
      then
         return Illegal_Cmd;
      end if;

      Clear_Static_Flags (Controller);

      R1 := Controller.Periph.RESP1;

      if (R1 and SD_OCR_ERRORMASK) = 0 then
         return OK;
      end if;

      if (R1 and SD_OCR_ADDR_OUT_OF_RANGE) /= 0 then
         return Address_Out_Of_Range;
      elsif (R1 and SD_OCR_ADDR_MISALIGNED) /= 0 then
         return Address_Missaligned;
      elsif (R1 and SD_OCR_BLOCK_LEN_ERR) /= 0 then
         return Block_Length_Error;
      elsif (R1 and SD_OCR_ERASE_SEQ_ERR) /= 0 then
         return Erase_Seq_Error;
      elsif (R1 and SD_OCR_BAD_ERASE_PARAM) /= 0 then
         return Bad_Erase_Parameter;
      elsif (R1 and SD_OCR_WRITE_PROT_VIOLATION) /= 0 then
         return Write_Protection_Violation;
      elsif (R1 and SD_OCR_LOCK_UNLOCK_FAILED) /= 0 then
         return Lock_Unlock_Failed;
      elsif (R1 and SD_OCR_COM_CRC_FAILED) /= 0 then
         return CRC_Check_Fail;
      elsif (R1 and SD_OCR_ILLEGAL_CMD) /= 0 then
         return Illegal_Cmd;
      elsif (R1 and SD_OCR_CARD_ECC_FAILED) /= 0 then
         return Card_ECC_Failed;
      elsif (R1 and SD_OCR_CC_ERROR) /= 0 then
         return CC_Error;
      elsif (R1 and SD_OCR_GENERAL_UNKNOWN_ERROR) /= 0 then
         return General_Unknown_Error;
      elsif (R1 and SD_OCR_STREAM_READ_UNDERRUN) /= 0 then
         return Stream_Read_Underrun;
      elsif (R1 and SD_OCR_STREAM_WRITE_UNDERRUN) /= 0 then
         return Stream_Write_Underrun;
      elsif (R1 and SD_OCR_CID_CSD_OVERWRITE) /= 0 then
         return CID_CSD_Overwrite;
      elsif (R1 and SD_OCR_WP_ERASE_SKIP) /= 0 then
         return WP_Erase_Skip;
      elsif (R1 and SD_OCR_CARD_ECC_DISABLED) /= 0 then
         return Card_ECC_Disabled;
      elsif (R1 and SD_OCR_ERASE_RESET) /= 0 then
         return Erase_Reset;
      elsif (R1 and SD_OCR_AKE_SEQ_ERROR) /= 0 then
         return AKE_SEQ_Error;
      else
         return General_Unknown_Error;
      end if;
   end Response_R1_Error;

   -----------------------
   -- Response_R2_Error --
   -----------------------

   function Response_R2_Error
     (Controller : in out SDMMC_Controller) return SD_Error
   is
   begin
      while not Controller.Periph.STA.CCRCFAIL
        and then not Controller.Periph.STA.CMDREND
        and then not Controller.Periph.STA.CTIMEOUT
      loop
         null;
      end loop;

      if Controller.Periph.STA.CTIMEOUT then
         --  Card is not v2.0 compliant or card does not support the set
         --  voltage range
         Controller.Periph.ICR.CTIMEOUTC := True;

         return Timeout_Error;

      elsif Controller.Periph.STA.CCRCFAIL then
         Controller.Periph.ICR.CCRCFAILC := True;

         return CRC_Check_Fail;
      end if;

      Clear_Static_Flags (Controller);

      return OK;
   end Response_R2_Error;

   -----------------------
   -- Response_R3_Error --
   -----------------------

   function Response_R3_Error
     (Controller : in out SDMMC_Controller) return SD_Error
   is
   begin
      while not Controller.Periph.STA.CCRCFAIL
        and then not Controller.Periph.STA.CMDREND
        and then not Controller.Periph.STA.CTIMEOUT
      loop
         null;
      end loop;

      if Controller.Periph.STA.CTIMEOUT then
         --  Card is not v2.0 compliant or card does not support the set
         --  voltage range
         Controller.Periph.ICR.CTIMEOUTC := True;

         return Timeout_Error;
      end if;

      Clear_Static_Flags (Controller);

      return OK;
   end Response_R3_Error;

   -----------------------
   -- Response_R6_Error --
   -----------------------

   function Response_R6_Error
     (Controller    : in out SDMMC_Controller;
      Command_Index : SDMMC_Command;
      RCA           :    out Word) return SD_Error
   is
      Response : Word;
   begin
      while not Controller.Periph.STA.CCRCFAIL
        and then not Controller.Periph.STA.CMDREND
        and then not Controller.Periph.STA.CTIMEOUT
      loop
         null;
      end loop;

      if Controller.Periph.STA.CTIMEOUT then
         --  Card is not v2.0 compliant or card does not support the set
         --  voltage range
         Controller.Periph.ICR.CTIMEOUTC := True;

         return Timeout_Error;

      elsif Controller.Periph.STA.CCRCFAIL then
         Controller.Periph.ICR.CCRCFAILC := True;

         return CRC_Check_Fail;
      end if;

      if SDMMC_Command (Controller.Periph.RESPCMD.RESPCMD) /=
        Command_Index
      then
         return Illegal_Cmd;
      end if;

      Clear_Static_Flags (Controller);

      Response := Controller.Periph.RESP1;

      if (Response and SD_R6_Illegal_Cmd) = SD_R6_Illegal_Cmd then
         return Illegal_Cmd;

      elsif (Response and SD_R6_General_Unknown_Error) =
        SD_R6_General_Unknown_Error
      then
         return General_Unknown_Error;

      elsif (Response and SD_R6_Com_CRC_Failed) = SD_R6_Com_CRC_Failed then
         return CRC_Check_Fail;
      end if;

      RCA := Response and 16#FFFF_0000#;

      return OK;
   end Response_R6_Error;

   -----------------------
   -- Response_R7_Error --
   -----------------------

   function Response_R7_Error
     (Controller : in out SDMMC_Controller) return SD_Error
   is
      Start : constant Time := Clock;
      Timeout : Boolean := False;
   begin
      while not Controller.Periph.STA.CCRCFAIL
        and then not Controller.Periph.STA.CMDREND
        and then not Controller.Periph.STA.CTIMEOUT
      loop
         if Clock - Start > Milliseconds (1000) then
            Timeout := True;

            exit;
         end if;
      end loop;

      if Timeout or else Controller.Periph.STA.CTIMEOUT then
         --  Card is not v2.0 compliant or card does not support the set
         --  voltage range
         Controller.Periph.ICR.CTIMEOUTC := True;

         return Timeout_Error;

      elsif Controller.Periph.STA.CCRCFAIL then
         Controller.Periph.ICR.CCRCFAILC := True;

         return CRC_Check_Fail;

      elsif Controller.Periph.STA.CMDREND then
         Controller.Periph.ICR.CMDRENDC := True;

         return OK;

      else
         return Error;
      end if;
   end Response_R7_Error;

   ------------------------
   -- SD_Select_Deselect --
   ------------------------

   function SD_Select_Deselect
     (Controller : in out SDMMC_Controller) return SD_Error
   is
   begin
      Send_Command
        (Controller,
         Command_Index      => Sel_Desel_Card,
         Argument           => Controller.RCA,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);

      return Response_R1_Error (Controller, Sel_Desel_Card);
   end SD_Select_Deselect;

   --------------
   -- Power_On --
   --------------

   function Power_On
     (Controller : in out SDMMC_Controller) return SD_Error
   is
      Ret           : SD_Error;
      Valid_Voltage : Boolean;
      Card_Type     : Word := SD_Std_Capacity;
      Response      : Word;
   begin
      Controller.Periph.CLKCR.CLKEN := False;
      delay until Clock + Milliseconds (1);

      Controller.Periph.POWER.PWRCTRL := Power_On;

      --  1ms: required power up waiting time before starting the SD
      --  initialization sequence
      delay until Clock + Milliseconds (1);

      Controller.Periph.CLKCR.CLKEN := True;

      --  CMD0: Go idle state
      --  no CMD reponse required
      Send_Command (Controller,
                    Command_Index      => Go_Idle_State,
                    Argument           => 0,
                    Response           => No_Response,
                    CPSM               => True,
                    Wait_For_Interrupt => False);

      Ret := Command_Error (Controller);

      if Ret /= OK then
         return Ret;
      end if;

      --  CMD8: Send Interface condition
      --  Send CMD8 to verify SD card interface operating condition
      --  Argument:
      --  - [31:12]: reserved, shall be set to '0'
      --  - [11:8]:  Supply voltage (VHS) 0x1 (range: 2.7-3.6V)
      --  - [7:0]:   Check Pattern (recommended 0xAA)
      Send_Command (Controller,
                    Command_Index      => HS_Send_Ext_CSD,
                    Argument           => SD_Check_Pattern,
                    Response           => Short_Response,
                    CPSM               => True,
                    Wait_For_Interrupt => False);

      Ret := Response_R7_Error (Controller);

      if Ret = OK then
         --  at least SD Card 2.0
         Controller.Card_Type := STD_Capacity_SD_Card_v2_0;
         Card_Type := SD_High_Capacity;

      else
         --  If SD Card, then it's v1.1
         Controller.Card_Type := STD_Capacity_SD_Card_V1_1;
      end if;

      --  Send CMD55
      Send_Command
        (Controller,
         Command_Index      => App_Cmd,
         Argument           => 0,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);

      Ret := Response_R1_Error (Controller, App_Cmd);

      if Ret /= OK then
         Controller.Card_Type := Multimedia_Card;
         --  Only support SD card for now
         return Unsupported_Card;

      else
         --  SD Card case: Send ACMD41 SD_App_Op_Cond with argument
         --  16#8010_0000#
         for J in 1 .. SD_MAX_VOLT_TRIAL loop
            Send_Command
              (Controller,
               Command_Index      => App_Cmd,
               Argument           => 0,
               Response           => Short_Response,
               CPSM               => True,
               Wait_For_Interrupt => False);

            Ret := Response_R1_Error (Controller, App_Cmd);
            if Ret /= OK then
               return Ret;
            end if;

            Send_Command
              (Controller,
               Command_Index      => SD_App_Op_Cond,
               Argument           => SD_Voltage_Window_SD or Card_Type,
               Response           => Short_Response,
               CPSM               => True,
               Wait_For_Interrupt => False);

            Ret := Response_R3_Error (Controller);

            if Ret /= OK then
               return Ret;
            end if;

            Response := Controller.Periph.RESP1;

            if Shift_Right (Response, 31) = 1 then
               Valid_Voltage := True;
               exit;
            end if;
         end loop;

         if not Valid_Voltage then
            return Invalid_Voltage_Range;
         end if;

         if (Response and SD_High_Capacity) = SD_High_Capacity then
            Controller.Card_Type := High_Capacity_SD_Card;
         end if;
      end if;

      return Ret;
   end Power_On;

   ---------------
   -- Power_Off --
   ---------------

   function Power_Off
     (Controller : in out SDMMC_Controller) return SD_Error
   is
   begin
      Controller.Periph.POWER.PWRCTRL := Power_Off;

      return OK;
   end Power_Off;

   ----------------------
   -- Initialize_Cards --
   ----------------------

   function Initialize_Cards
     (Controller : in out SDMMC_Controller) return SD_Error
   is
      SD_RCA : Word;
      Err    : SD_Error;
   begin
      if not Controller.Periph.CLKCR.CLKEN then
         return Request_Not_Applicable;
      end if;

      if Controller.Card_Type /= Secure_Digital_IO_Card then
         Send_Command
           (Controller,
            Command_Index      => All_Send_CID,
            Argument           => 0,
            Response           => Long_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);

         Err := Response_R2_Error (Controller);

         if Err /= OK then
            return Err;
         end if;

         Controller.CID :=
           (Controller.Periph.RESP1,
            Controller.Periph.RESP2,
            Controller.Periph.RESP3,
            Controller.Periph.RESP4);
      end if;

      if Controller.Card_Type = STD_Capacity_SD_Card_V1_1
        or else Controller.Card_Type = STD_Capacity_SD_Card_v2_0
        or else Controller.Card_Type = Secure_Digital_IO_Combo_Card
        or else Controller.Card_Type = High_Capacity_SD_Card
      then
         --  Send CMD3 Set_Rel_Addr with argument 0
         Send_Command
           (Controller,
            Command_Index      => Set_Rel_Addr,
            Argument           => 0,
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);

         Err := Response_R6_Error (Controller, Set_Rel_Addr, SD_RCA);

         if Err /= OK then
            return Err;
         end if;
      end if;

      if Controller.Card_Type /= Secure_Digital_IO_Card then
         Controller.RCA := SD_RCA;

         --  Send CMD9 Send_CSD with argument as card's RCA

         Send_Command
           (Controller,
            Command_Index      => Send_CSD,
            Argument           => SD_RCA,
            Response           => Long_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);

         Err := Response_R2_Error (Controller);

         if Err /= OK then
            return Err;
         end if;

         Controller.CSD :=
           (Controller.Periph.RESP1,
            Controller.Periph.RESP2,
            Controller.Periph.RESP3,
            Controller.Periph.RESP4);
      end if;

      return Err;
   end Initialize_Cards;

   --------------------
   -- Read_Card_Info --
   --------------------

   function Read_Card_Info
     (Controller : in out SDMMC_Controller;
      Info       :    out Card_Information) return SD_Error
   is
      Tmp : Byte;
   begin
      Info.Card_Type := Controller.Card_Type;
      Info.RCA       := Short (Shift_Right (Controller.RCA, 16));

      --  Analysis of CSD Byte 0
      Tmp := Byte (Shift_Right (Controller.CSD (0) and 16#FF00_0000#, 24));
      Info.SD_CSD.CSD_Structure := Shift_Right (Tmp and 16#C0#, 6);
      Info.SD_CSD.System_Specification_Version :=
        Shift_Right (Tmp and 16#3C#, 2);
      Info.SD_CSD.Reserved := Tmp and 16#03#;

      --  Byte 1
      Tmp := Byte (Shift_Right (Controller.CSD (0) and 16#00FF_0000#, 16));
      Info.SD_CSD.Data_Read_Access_Time_1 := Tmp;

      --  Byte 2
      Tmp := Byte (Shift_Right (Controller.CSD (0) and 16#0000_FF00#, 8));
      Info.SD_CSD.Data_Read_Access_Time_2 := Tmp;

      --  Byte 3
      Tmp := Byte (Controller.CSD (0) and 16#0000_00FF#);
      Info.SD_CSD.Max_Bus_Clock_Frequency := Tmp;

      --  Byte 4 & 5
      Info.SD_CSD.Card_Command_Class :=
        Short (Shift_Right (Controller.CSD (1) and 16#FFF0_0000#, 20));
      Info.SD_CSD.Max_Read_Data_Block_Length :=
        Byte (Shift_Right (Controller.CSD (1) and 16#000F_0000#, 16));

      --  Byte 6
      Tmp := Byte (Shift_Right (Controller.CSD (1) and 16#0000_FF00#, 8));
      Info.SD_CSD.Partial_Block_For_Read_Allowed := (Tmp and 16#80#) /= 0;
      Info.SD_CSD.Write_Block_Missalignment := (Tmp and 16#40#) /= 0;
      Info.SD_CSD.Read_Block_Missalignment := (Tmp and 16#20#) /= 0;
      Info.SD_CSD.DSR_Implemented := (Tmp and 16#10#) /= 0;
      Info.SD_CSD.Reserved_2 := 0;

      if Controller.Card_Type = STD_Capacity_SD_Card_V1_1
        or else Controller.Card_Type = STD_Capacity_SD_Card_v2_0
      then
         Info.SD_CSD.Device_Size := Shift_Left (Word (Tmp) and 16#03#, 10);

         --  Byte 7
         Tmp := Byte (Controller.CSD (1) and 16#0000_00FF#);
         Info.SD_CSD.Device_Size := Info.SD_CSD.Device_Size or
           Shift_Left (Word (Tmp), 2);

         --  Byte 8
         Tmp := Byte (Shift_Right (Controller.CSD (2) and 16#FF00_0000#, 24));
         Info.SD_CSD.Device_Size := Info.SD_CSD.Device_Size or
           Shift_Right (Word (Tmp and 16#C0#), 6);
         Info.SD_CSD.Max_Read_Current_At_VDD_Min :=
           Shift_Right (Tmp and 16#38#, 3);
         Info.SD_CSD.Max_Read_Current_At_VDD_Max :=
           Tmp and 16#07#;

         --  Byte 9
         Tmp := Byte (Shift_Right (Controller.CSD (2) and 16#00FF_0000#, 16));
         Info.SD_CSD.Max_Write_Current_At_VDD_Min :=
           Shift_Right (Tmp and 16#E0#, 5);
         Info.SD_CSD.Max_Write_Current_At_VDD_Max :=
           Shift_Right (Tmp and 16#1C#, 2);
         Info.SD_CSD.Device_Size_Multiplier :=
           Shift_Left (Tmp and 16#03#, 2);

         --  Byte 10
         Tmp := Byte (Shift_Right (Controller.CSD (2) and 16#0000_FF00#, 8));
         Info.SD_CSD.Device_Size_Multiplier :=
           Info.SD_CSD.Device_Size_Multiplier or
           Shift_Right (Tmp and 16#80#, 7);

         Info.Card_Block_Size :=
           2 ** Natural (Info.SD_CSD.Max_Read_Data_Block_Length);
         Info.Card_Capacity :=
           Unsigned_64 (Info.SD_CSD.Device_Size + 1) *
           2 ** Natural (Info.SD_CSD.Device_Size_Multiplier + 2) *
           Unsigned_64 (Info.Card_Block_Size);

      elsif Controller.Card_Type = High_Capacity_SD_Card then
         --  Byte 7
         Tmp := Byte (Controller.CSD (1) and 16#0000_00FF#);
         Info.SD_CSD.Device_Size := Shift_Left (Word (Tmp), 16);

         --  Byte 8 & 9
         Info.SD_CSD.Device_Size := Info.SD_CSD.Device_Size or
           (Shift_Right (Controller.CSD (2) and 16#FFFF_0000#, 16));

         Info.Card_Capacity :=
           Unsigned_64 (Info.SD_CSD.Device_Size + 1) * 512 * 1024;
         Info.Card_Block_Size := 512;

         --  Byte 10
         Tmp := Byte (Shift_Right (Controller.CSD (2) and 16#0000_FF00#, 8));
      else
         return Unsupported_Card;
      end if;

      Info.SD_CSD.Erase_Group_Size := Shift_Right (Tmp and 16#40#, 6);
      Info.SD_CSD.Erase_Group_Size_Multiplier :=
        Shift_Left (Tmp and 16#3F#, 1);

      --  Byte 11
      Tmp := Byte (Controller.CSD (2) and 16#0000_00FF#);
      Info.SD_CSD.Erase_Group_Size_Multiplier :=
        Info.SD_CSD.Erase_Group_Size_Multiplier or
        Shift_Right (Tmp and 16#80#, 7);
      Info.SD_CSD.Write_Protect_Group_Size := Tmp and 16#7F#;

      --  Byte 12
      Tmp := Byte (Shift_Right (Controller.CSD (3) and 16#FF00_0000#, 24));
      Info.SD_CSD.Write_Protect_Group_Enable := (Tmp and 16#80#) /= 0;
      Info.SD_CSD.Manufacturer_Default_ECC := Shift_Right (Tmp and 16#60#, 5);
      Info.SD_CSD.Write_Speed_Factor := Shift_Right (Tmp and 16#1C#, 2);
      Info.SD_CSD.Max_Write_Data_Block_Length :=
        Shift_Left (Tmp and 16#03#, 2);

      --  Byte 13
      Tmp := Byte (Shift_Right (Controller.CSD (3) and 16#00FF_0000#, 16));
      Info.SD_CSD.Max_Write_Data_Block_Length :=
        Info.SD_CSD.Max_Read_Data_Block_Length or
        Shift_Right (Tmp and 16#C0#, 6);
      Info.SD_CSD.Partial_Blocks_For_Write_Allowed := (Tmp and 16#20#) /= 0;
      Info.SD_CSD.Reserved_3 := 0;
      Info.SD_CSD.Content_Protection_Application := (Tmp and 16#01#) /= 0;

      --  Byte 14
      Tmp := Byte (Shift_Right (Controller.CSD (3) and 16#0000_FF00#, 8));
      Info.SD_CSD.File_Format_Group := (Tmp and 16#80#) /= 0;
      Info.SD_CSD.Copy_Flag := (Tmp and 16#40#) /= 0;
      Info.SD_CSD.Permanent_Write_Protection := (Tmp and 16#20#) /= 0;
      Info.SD_CSD.Temporary_Write_Protection := (Tmp and 16#10#) /= 0;
      Info.SD_CSD.File_Format := Shift_Right (Tmp and 16#0C#, 2);
      Info.SD_CSD.ECC_Code := Tmp and 16#03#;

      --  Byte 15
      Tmp := Byte (Controller.CSD (3) and 16#0000_00FF#);
      Info.SD_CSD.CSD_CRC := Shift_Right (Tmp and 16#FE#, 1);
      Info.SD_CSD.Reserved_4 := 0;

      --  Byte 0
      Tmp := Byte (Shift_Right (Controller.CID (0) and 16#FF00_0000#, 24));
      Info.SD_CID.Manufacturer_ID := Tmp;

      --  Byte 1 & 2
      Tmp := Byte (Shift_Right (Controller.CID (0) and 16#00FF_0000#, 16));
      Info.SD_CID.OEM_Application_ID (1) := Character'Val (Tmp);
      Tmp := Byte (Shift_Right (Controller.CID (0) and 16#0000_FF00#, 8));
      Info.SD_CID.OEM_Application_ID (2) := Character'Val (Tmp);

      --  Byte 3-7
      Tmp := Byte (Controller.CID (0) and 16#0000_00FF#);
      Info.SD_CID.Product_Name (1) := Character'Val (Tmp);
      Tmp := Byte (Shift_Right (Controller.CID (1) and 16#FF00_0000#, 24));
      Info.SD_CID.Product_Name (2) := Character'Val (Tmp);
      Tmp := Byte (Shift_Right (Controller.CID (1) and 16#00FF_0000#, 16));
      Info.SD_CID.Product_Name (3) := Character'Val (Tmp);
      Tmp := Byte (Shift_Right (Controller.CID (1) and 16#0000_FF00#, 8));
      Info.SD_CID.Product_Name (4) := Character'Val (Tmp);
      Tmp := Byte (Controller.CID (1) and 16#0000_00FF#);
      Info.SD_CID.Product_Name (5) := Character'Val (Tmp);

      --  Byte 8
      Tmp := Byte (Shift_Right (Controller.CID (2) and 16#FF00_0000#, 24));
      Info.SD_CID.Product_Revision.Major := UInt4 (Shift_Right (Tmp, 4));
      Info.SD_CID.Product_Revision.Minor := UInt4 (Tmp and 16#0F#);

      --  Byte 9 - 12
      Info.SD_CID.Product_Serial_Number :=
        Shift_Left (Controller.CID (2) and 16#00FF_FFFF#, 8) or
        Shift_Right (Controller.CID (3) and 16#FF00_0000#, 24);

      --  Byte 13 - 14
      Info.SD_CID.Manufacturing_Date.Month :=
        Manufacturing_Month'Val
          (Shift_Right (Controller.CID (3) and 16#0000_0F00#, 8) - 1);
      Info.SD_CID.Manufacturing_Date.Year :=
        Manufacturing_Year
          (2000 + Shift_Right (Controller.CID (3) and 16#000F_F000#, 12));

      --  Byte 15
      Tmp := Byte (Controller.CID (3) and 16#0000_00FF#);
      Info.SD_CID.CID_CRC := Shift_Right (Tmp and 16#FE#, 1);

      return OK;
   end Read_Card_Info;

   --------------
   -- Find_SCR --
   --------------
   --  Find (?) SC card's Card Configuration Regiser

   function Find_SCR
     (Controller : in out SDMMC_Controller;
      SCR        :    out SD_SCR) return SD_Error
   is
      Err  : SD_Error;
      Idx  : Natural;
      Tmp  : SD_SCR;
      Dead : Unsigned_32 with Unreferenced;

   begin
      Send_Command
        (Controller,
         Command_Index      => Set_Blocklen,
         Argument           => 8,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      Err := Response_R1_Error (Controller, Set_Blocklen);

      if Err /= OK then
         return Err;
      end if;

      Send_Command
        (Controller,
         Command_Index      => App_Cmd,
         Argument           => Controller.RCA,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      Err := Response_R1_Error (Controller, App_Cmd);

      if Err /= OK then
         return Err;
      end if;

      Configure_Data
        (Controller,
         Data_Length        => 8,
         Data_Block_Size    => Block_8B,
         Transfer_Direction => Read,
         Transfer_Mode      => Block,
         DPSM               => True,
         DMA_Enabled        => False);

      Send_Command
        (Controller,
         Command_Index      => SD_App_Send_SCR,
         Argument           => 0,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      Err := Response_R1_Error (Controller, SD_App_Send_SCR);

      if Err /= OK then
         return Err;
      end if;

      Idx := Tmp'First;

      while not Controller.Periph.STA.RXOVERR
        and then not Controller.Periph.STA.DCRCFAIL
        and then not Controller.Periph.STA.DTIMEOUT
        and then not Controller.Periph.STA.DBCKEND
      loop
         while Controller.Periph.STA.RXDAVL loop
            if Idx <= Tmp'Last then
               Tmp (Idx) := Read_FIFO (Controller);
               Idx := Idx + 1;
            else
               --  Flush the FIFO
               Dead := Read_FIFO (Controller);
            end if;
         end loop;
      end loop;

      if Controller.Periph.STA.DTIMEOUT then
         Controller.Periph.ICR.DTIMEOUTC := True;

         return Timeout_Error;

      elsif Controller.Periph.STA.DCRCFAIL then
         Controller.Periph.ICR.DCRCFAILC := True; -- clear

         return CRC_Check_Fail;

      elsif Controller.Periph.STA.RXOVERR then
         Controller.Periph.ICR.RXOVERRC := True;

         return Rx_Overrun;
      end if;

      Clear_Static_Flags (Controller);

      --  Translate into LSB
      SCR (1) := Shift_Left (Tmp (2) and SD_0TO7BITS, 24)
        or Shift_Left (Tmp (2) and SD_8TO715ITS, 8)
        or Shift_Right (Tmp (2) and SD_16TO23BITS, 8)
        or Shift_Right (Tmp (2) and SD_24TO31BITS, 24);
      SCR (2) := Shift_Left (Tmp (1) and SD_0TO7BITS, 24)
        or Shift_Left (Tmp (1) and SD_8TO715ITS, 8)
        or Shift_Right (Tmp (1) and SD_16TO23BITS, 8)
        or Shift_Right (Tmp (1) and SD_24TO31BITS, 24);

      return OK;
   end Find_SCR;

   -------------------
   -- Stop_Transfer --
   -------------------

   function Stop_Transfer
     (Controller : in out SDMMC_Controller) return SD_Error
   is
   begin
      Send_Command
        (Controller,
         Command_Index      => Stop_Transmission,
         Argument           => 0,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      return Response_R1_Error (Controller, Stop_Transmission);
   end Stop_Transfer;

   ----------------------
   -- Disable_Wide_Bus --
   ----------------------

   function Disable_Wide_Bus
     (Controller : in out SDMMC_Controller) return SD_Error
   is
      Err : SD_Error := OK;
      SCR : SD_SCR;
   begin
      if (Controller.Periph.RESP1 and SD_CARD_LOCKED) = SD_CARD_LOCKED then
         return Lock_Unlock_Failed;
      end if;

      Err := Find_SCR (Controller, SCR);

      if Err /= OK then
         return Err;
      end if;

      if (SCR (2) and SD_SINGLE_BUS_SUPPORT) /= 0 then
         Send_Command
           (Controller,
            Command_Index      => App_Cmd,
            Argument           => Controller.RCA,
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, App_Cmd);

         if Err /= OK then
            return Err;
         end if;

         Send_Command
           (Controller,
            Command_Index      => SD_App_Set_Buswidth,
            Argument           => 0,
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, SD_App_Set_Buswidth);

         if Err /= OK then
            return Err;
         end if;
      else
         return Request_Not_Applicable;
      end if;

      return Err;
   end Disable_Wide_Bus;

   ---------------------
   -- Enable_Wide_Bus --
   ---------------------

   function Enable_Wide_Bus
     (Controller : in out SDMMC_Controller) return SD_Error
   is
      Err : SD_Error := OK;
      SCR : SD_SCR;
   begin
      if (Controller.Periph.RESP1 and SD_CARD_LOCKED) = SD_CARD_LOCKED then
         return Lock_Unlock_Failed;
      end if;

      Err := Find_SCR (Controller, SCR);

      if Err /= OK then
         return Err;
      end if;

      if (SCR (2) and SD_WIDE_BUS_SUPPORT) /= 0 then
         Send_Command
           (Controller,
            Command_Index      => App_Cmd,
            Argument           => Controller.RCA,
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, App_Cmd);

         if Err /= OK then
            return Err;
         end if;

         Send_Command
           (Controller,
            Command_Index      => SD_App_Set_Buswidth,
            Argument           => 2,
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, SD_App_Set_Buswidth);

         if Err /= OK then
            return Err;
         end if;
      else
         return Request_Not_Applicable;
      end if;

      return Err;
   end Enable_Wide_Bus;

   ----------------
   -- Initialize --
   ----------------

   function Initialize
     (Controller : in out SDMMC_Controller;
      Info       : out Card_Information) return SD_Error
   is
      Ret : SD_Error;
   begin
      Ret := Power_Off (Controller);

      if Ret /= OK then
         return Ret;
      end if;

      --  Use the Default SDMMC peripheral configuration for SD card init
      Controller.Periph.CLKCR :=
        (CLKDIV         => 16#76#, --  400 kHz max
         --  Clock enable bit
         CLKEN          => False,
         --  Power saving configuration bit
         PWRSAV         => False,
         --  Clock divider bypass enable bit
         BYPASS         => False,
         --  Wide bus mode enable bit
         WIDBUS         => Bus_Wide_1B,
         --  SDIO_CK dephasing selection bit
         NEGEDGE        => Edge_Rising, -- Errata sheet STM: NEGEDGE=1 (falling) should *not* be used
         --  HW Flow Control enable
         HWFC_EN        => False, -- Errata sheet STM: glitches => DCRCFAIL asserted. Workaround: Do not use HW flow ctrl. *gasp*
         others         => <>);
      delay until Clock + Milliseconds (1);

      Controller.Periph.DTIMER := SD_DATATIMEOUT; -- gives us time to read/write FIFO before errors occur. FIXME: too long

      Ret := Power_On (Controller);

      if Ret /= OK then
         return Ret;
      end if;

      Ret := Initialize_Cards (Controller);

      if Ret /= OK then
         return Ret;
      end if;

      Ret := SD_Select_Deselect (Controller);

      if Ret /= OK then
         return Ret;
      end if;

      --  Now use the card to nominal speed : 25MHz
      Controller.Periph.CLKCR.CLKDIV := 0;
      Clear_Static_Flags (Controller);
      delay until Clock + Milliseconds (1);

      Ret := Read_Card_Info (Controller, Info);

      if Ret /= OK then
         return Ret;
      end if;

      Ret := Configure_Wide_Bus_Mode (Controller, Wide_Bus_4B);

      return Ret;
   end Initialize;

   -----------------------------
   -- Configure_Wide_Bus_Mode --
   -----------------------------

   function Configure_Wide_Bus_Mode
     (Controller : in out SDMMC_Controller;
      Wide_Mode  : Wide_Bus_Mode) return SD_Error
   is
      function To_WIDBUS_Field is new Ada.Unchecked_Conversion
        (Wide_Bus_Mode, WIDBUS_Field);
      Err : SD_Error;
   begin
      if Controller.Card_Type = STD_Capacity_SD_Card_V1_1
        or else Controller.Card_Type = STD_Capacity_SD_Card_v2_0
        or else Controller.Card_Type = High_Capacity_SD_Card
      then
         case Wide_Mode is
            when Wide_Bus_1B =>
               Err := Disable_Wide_Bus (Controller);
            when Wide_Bus_4B =>
               Err := Enable_Wide_Bus (Controller);
            when Wide_Bus_8B =>
               return Request_Not_Applicable;
         end case;

         if Err = OK then
            Controller.Periph.CLKCR.WIDBUS := To_WIDBUS_Field (Wide_Mode);
         end if;

      elsif Controller.Card_Type = Multimedia_Card then
         return Unsupported_Card;
      end if;

      return Err;
   end Configure_Wide_Bus_Mode;

   -----------------
   -- Read_Blocks --
   -----------------

   function Blocksize2DBLOCKSIZE (siz : Natural) return DBLOCKSIZE_Field is
   begin
      case (siz) is
         when 1 => return Block_1B;
         when 8 => return Block_8B;
         when 16 => return Block_16B;
         when 32 => return Block_32B;
         when 64 => return Block_64B;
         when 128 => return Block_128B;
         when 256 => return Block_256B;
         when others => return Block_512B;
      end case;
   end Blocksize2DBLOCKSIZE;

   -- TODO: read and write are very similar. Reduce code duplication.

   -- new and untested writing function
   function Write_Blocks
     (Controller : in out SDMMC_Controller;
      Addr       : Unsigned_64;
      Data       : SD_Data) return SD_Error
   is
      subtype Word_Data is SD_Data (1 .. 4);
      function From_Data is new Ada.Unchecked_Conversion
        (Word_Data, Word);
      R_Addr   : Unsigned_64 := Addr;
      N_Blocks : Positive;
      Err      : SD_Error;
      Idx      : Unsigned_32 := Data'First;
      cardstatus : HAL.Word;
      start    : Time := Clock;
      Timeout  : Boolean := False;
   begin
       Controller.Periph.DCTRL := (others => <>);

      -- So here we are. SD High Capacity does not allow partial
      -- (that is, blocks of size < card's blocklen) reads.
      -- this means, we get an rxoverflow here, unless we read
      -- very slowly
      Controller.Periph.CLKCR.CLKDIV := 16#76#; --  400 kHz max because we are polling/pushing
      Clear_Static_Flags (Controller);
      --  Wait 1ms: After a data write, data cannot be written to this register
      --  for three SDMMCCLK (48 MHz) clock periods plus two PCLK2 clock
      --  periods.
      delay until Clock + Milliseconds (1);

      if Controller.Card_Type = High_Capacity_SD_Card then
         R_Addr := Addr / BLOCKLEN; -- FIXME: does that hold for non-high-capacity cards?
      end if;

      N_Blocks := Data'Length / BLOCKLEN;

      Send_Command
        (Controller,
         Command_Index      => Set_Blocklen, -- for High-Capacity SD cards this does not affect data read/write. Is is always 512.
         Argument           => BLOCKLEN,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      Err := Response_R1_Error (Controller, Set_Blocklen);

      if Err /= OK then
         return Err;
      end if;

      Wait_Ready_loop :
      loop
         declare
            now : Time := Clock;
         begin
            if now - start > Milliseconds (10) then
               Timeout := True;
               exit Wait_Ready_Loop;
            end if;
         end;

         Send_Command
           (Controller,
            Command_Index      => Send_Status,
            Argument           => Controller.RCA,
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, Send_Status);

         if Err /= OK then
            return Err;
         end if;

         cardstatus := Controller.Periph.RESP1;
         exit Wait_Ready_Loop when (cardstatus and 16#100#) /= 0;
      end loop Wait_Ready_Loop;

      if Timeout then
         return Timeout_Error;
      end if;

      Configure_Data
        (Controller,
         Data_Length        => Data'Length,
         Data_Block_Size    => Blocksize2DBLOCKSIZE (BLOCKLEN),
         Transfer_Direction => Write,
         Transfer_Mode      => Block,
         DPSM               => True,
         DMA_Enabled        => False);

      if N_Blocks > 1 then
         Controller.Operation := Write_Multiple_Blocks_Operation;
         Send_Command
           (Controller,
            Command_Index      => Write_Multi_Block,
            Argument           => Word (R_Addr),
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, Write_Multi_Block);
      else
         Controller.Operation := Write_Single_Block_Operation;
         Send_Command
           (Controller,
            Command_Index      => Write_Single_Block,
            Argument           => Word (R_Addr),
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, Write_Single_Block);
      end if;

      if Err /= OK then
         return Err;
      end if;


      if N_Blocks > 1 then
         --  Poll on SDMMC flags
         while not Controller.Periph.STA.TXUNDERR
           and then not Controller.Periph.STA.DCRCFAIL
           and then not Controller.Periph.STA.DTIMEOUT
           and then not Controller.Periph.STA.STBITERR
           and then not Controller.Periph.STA.DATAEND -- end of data (=all blocks)
         loop
            if Controller.Periph.STA.TXFIFOHE then -- TX FIFO half empty
               for J in 1 .. 8 loop
                  Write_FIFO (Controller, From_Data (Data (Idx .. Idx + 3)));
                  Idx := Idx + 4;
               end loop;
            end if;
         end loop;
      else
         --  Poll on SDMMC flags
         while not Controller.Periph.STA.TXUNDERR
           and then not Controller.Periph.STA.DCRCFAIL
           and then not Controller.Periph.STA.DTIMEOUT
           and then not Controller.Periph.STA.STBITERR
           and then not Controller.Periph.STA.DBCKEND -- end of block
         loop
            if Controller.Periph.STA.TXFIFOHE then -- TX FIFO half empty
               for J in 1 .. 8 loop
                  Write_FIFO (Controller, From_Data (Data (Idx .. Idx + 3)));
                  Idx := Idx + 4;
               end loop;
            end if;
         end loop;
      end if;

      if N_Blocks > 1 and then Controller.Periph.STA.DATAEND then
         Err := Stop_Transfer (Controller);
      end if;

      --  check whether there were errors
      if Controller.Periph.STA.DTIMEOUT then
         Controller.Periph.ICR.DTIMEOUTC := True;
         return Timeout_Error;

      elsif Controller.Periph.STA.DCRCFAIL then
         Controller.Periph.ICR.DCRCFAILC := True;
         return CRC_Check_Fail;

      elsif Controller.Periph.STA.TXUNDERR then
         Controller.Periph.ICR.TXUNDERRC := True;
         return TX_Underrun;

      elsif Controller.Periph.STA.STBITERR then
         Controller.Periph.ICR.STBITERRC := True;
         return Startbit_Not_Detected;
      end if;

      Clear_Static_Flags (Controller);

      return Err;
   end Write_Blocks;

   function Read_Blocks
     (Controller : in out SDMMC_Controller;
      Addr       : Unsigned_64;
      Data       : out SD_Data) return SD_Error
   is
      subtype Word_Data is SD_Data (1 .. 4);
      function To_Data is new Ada.Unchecked_Conversion
        (Word, Word_Data);
      R_Addr   : Unsigned_64 := Addr;
      N_Blocks : Positive;
      Err      : SD_Error;
      Idx      : Unsigned_32 := Data'First;
      Dead     : Word with Unreferenced;

   begin

      Controller.Periph.DCTRL := (others => <>);

      -- So here we are. SD High Capacity does not allow partial
      -- (that is, blocks of size < card's blocklen) reads.
      -- this means, we get an rxoverflow here, unless we read
      -- very slowly
      Controller.Periph.CLKCR.CLKDIV := 16#76#; --  400 kHz max
      Clear_Static_Flags (Controller);
      --  Wait 1ms: After a data write, data cannot be written to this register
      --  for three SDMMCCLK (48 MHz) clock periods plus two PCLK2 clock
      --  periods.
      delay until Clock + Milliseconds (1);

      if Controller.Card_Type = High_Capacity_SD_Card then
         R_Addr := Addr / BLOCKLEN; -- FIXME: does that hold for non-high-capacity cards?
      end if;

      N_Blocks := Data'Length / BLOCKLEN;

      Send_Command
        (Controller,
         Command_Index      => Set_Blocklen, -- for High-Capacity SD cards this does not affect data read/write. Is is always 512.
         Argument           => BLOCKLEN,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      Err := Response_R1_Error (Controller, Set_Blocklen);

      if Err /= OK then
         return Err;
      end if;

      Configure_Data
        (Controller,
         Data_Length        => Data'Length,
         Data_Block_Size    => Blocksize2DBLOCKSIZE (BLOCKLEN),
         Transfer_Direction => Read,
         Transfer_Mode      => Block,
         DPSM               => True,
         DMA_Enabled        => False);

      if N_Blocks > 1 then
         Controller.Operation := Read_Multiple_Blocks_Operation;
         Send_Command
           (Controller,
            Command_Index      => Read_Multi_Block,
            Argument           => Word (R_Addr),
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, Read_Multi_Block);
      else
         Controller.Operation := Read_Single_Block_Operation;
         Send_Command
           (Controller,
            Command_Index      => Read_Single_Block,
            Argument           => Word (R_Addr),
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, Read_Single_Block);
      end if;

      if Err /= OK then
         return Err;
      end if;

      if N_Blocks > 1 then
         --  Poll on SDMMC flags
         while not Controller.Periph.STA.RXOVERR
           and then not Controller.Periph.STA.DCRCFAIL
           and then not Controller.Periph.STA.DTIMEOUT
           and then not Controller.Periph.STA.DATAEND -- end of data (=all blocks)
         loop
            if Controller.Periph.STA.RXFIFOHF then -- if FIFO at least half full (>=8 words, each 4byte)
               for J in 1 .. 8 loop -- get the 8 words
                  Data (Idx .. Idx + 3) :=
                    To_Data (Read_FIFO (Controller));
                  Idx := Idx + 4;
               end loop;
            end if;
         end loop;

      else
         --  Poll on SDMMC flags
         while not Controller.Periph.STA.RXOVERR
           and then not Controller.Periph.STA.DCRCFAIL -- FIXME: is this valid before DBCKEND?
           and then not Controller.Periph.STA.DTIMEOUT
           and then not Controller.Periph.STA.DBCKEND -- end of block
         loop
            if Controller.Periph.STA.RXFIFOHF then
               for J in 1 .. 8 loop
                  Data (Idx .. Idx + 3) :=
                    To_Data (Read_FIFO (Controller)); -- 4 bytes per FIFO
                  Idx := Idx + 4;
               end loop;
            end if;
         end loop;
      end if;

      if N_Blocks > 1 and then Controller.Periph.STA.DATAEND then
         Err := Stop_Transfer (Controller);
      end if;

      declare
         num_rx : STM32_SVD.SDIO.DLEN_DATALENGTH_Field;
         num_rem : STM32_SVD.SDIO.DCOUNT_DATACOUNT_Field;
         num_fifo : STM32_SVD.SDIO.FIFOCNT_FIFOCOUNT_Field;
      begin
         -- DEbug: check how much data is pending/transferred
         num_rem := Controller.Periph.DCOUNT.DATACOUNT; -- 496
         num_fifo := Controller.Periph.FIFOCNT.FIFOCOUNT;
         num_rx := Controller.Periph.DLEN.DATALENGTH; -- 512
      end;

      --  check whether there were errors
      if Controller.Periph.STA.DTIMEOUT then
         Controller.Periph.ICR.DTIMEOUTC := True;
         return Timeout_Error;

      elsif Controller.Periph.STA.DCRCFAIL then
         Controller.Periph.ICR.DCRCFAILC := True; -- clear
         return CRC_Check_Fail;

      elsif Controller.Periph.STA.RXOVERR then
         Controller.Periph.ICR.RXOVERRC := True;
         return Rx_Overrun;

      elsif Controller.Periph.STA.STBITERR then
         Controller.Periph.ICR.STBITERRC := True;
         return Startbit_Not_Detected;

      end if;

      for J in Unsigned_32'(1) .. SD_DATATIMEOUT loop
         exit when not Controller.Periph.STA.RXDAVL;
         Dead := Read_FIFO (Controller);
      end loop;

      Clear_Static_Flags (Controller);

      return Err;
   end Read_Blocks;

   ---------------------
   -- Read_Blocks_DMA --
   ---------------------

   function Read_Blocks_DMA
     (Controller : in out SDMMC_Controller;
      Addr       : Unsigned_64;
      DMA        : STM32.DMA.DMA_Controller;
      Stream     : STM32.DMA.DMA_Stream_Selector;
      Data       : out SD_Data) return SD_Error
   is
      Read_Address : constant Unsigned_64 :=
                       (if Controller.Card_Type = High_Capacity_SD_Card
                        then Addr / 512 else Addr); -- FIXME: why 512? Cluster size of SD card?

      Data_Len_Bytes : constant Natural := (Data'Length / 512) * 512;
      Data_Len_Words : constant Natural := Data_Len_Bytes / 4;
      N_Blocks       : constant Natural := Data_Len_Bytes / BLOCKLEN;
      Data_Addr      : constant Address := Data (Data'first)'Address;

      Err            : SD_Error;
      Command        : SDMMC_Command;
      use STM32.DMA;
   begin
      if not STM32.DMA.Compatible_Alignments (DMA,
                                              Stream,
                                              Controller.Periph.FIFO'Address,
                                              Data_Addr)
      then
         return DMA_Alignment_Error;
      end if;

      Controller.Periph.DCTRL := (DTEN   => False,
                                  others => <>);
      --  Wait 1ms: After a data write, data cannot be written to this register
      --  for three SDMMCCLK (48 MHz) clock periods plus two PCLK2 clock
      --  periods.


      Controller.Periph.CLKCR.CLKDIV := 16#0#; --  switch to nominal speed, in case polling was active before

      delay until Clock + Milliseconds (1);

      Enable_Interrupt (Controller, Data_CRC_Fail_Interrupt);
      Enable_Interrupt (Controller, Data_Timeout_Interrupt);
      Enable_Interrupt (Controller, Data_End_Interrupt);
      Enable_Interrupt (Controller, RX_Overrun_Interrupt);

      STM32.DMA.Start_Transfer_with_Interrupts
        (Unit               => DMA,
         Stream             => Stream,
         Source             => Controller.Periph.FIFO'Address,
         Destination        => Data_Addr,
         Data_Count         => Unsigned_16 (Data_Len_Words), -- because DMA is set up with words
         Enabled_Interrupts => (Transfer_Error_Interrupt    => True,
                                FIFO_Error_Interrupt        => True,
                                Transfer_Complete_Interrupt => True,
                                others                      => False));

      Send_Command
        (Controller,
         Command_Index      => Set_Blocklen,
         Argument           => BLOCKLEN,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      Err := Response_R1_Error (Controller, Set_Blocklen);

      if Err /= OK then
         return Err;
      end if;

      Configure_Data
        (Controller,
         Data_Length        => UInt25 (N_Blocks) * BLOCKLEN,
         Data_Block_Size    => Blocksize2DBLOCKSIZE (BLOCKLEN),
         Transfer_Direction => Read,
         Transfer_Mode      => Block,
         DPSM               => True,
         DMA_Enabled        => True);

      if N_Blocks > 1 then
         Command := Read_Multi_Block;
         Controller.Operation := Read_Multiple_Blocks_Operation;
      else
         Command := Read_Single_Block;
         Controller.Operation := Read_Single_Block_Operation;
      end if;

      Send_Command
        (Controller,
         Command_Index      => Command,
         Argument           => Word (Read_Address),
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      Err := Response_R1_Error (Controller, Command);

      return Err;
   end Read_Blocks_DMA;

   -- new and untested writing function
   function Write_Blocks_DMA
     (Controller : in out SDMMC_Controller;
      Addr       : Unsigned_64;
      DMA        : STM32.DMA.DMA_Controller;
      Stream     : STM32.DMA.DMA_Stream_Selector;
      Data       : SD_Data) return SD_Error
   is
      Write_Address : constant Unsigned_64 :=
                       (if Controller.Card_Type = High_Capacity_SD_Card
                        then Addr / 512 else Addr); -- 512 is the min. block size of SD 2.0 card

      Data_Len_Bytes : constant Natural := (Data'Length / 512) * 512;
      --DMA_FLUSH      : constant := 4; --  DMA requires 4 words to flush
      Data_Len_Words : constant Natural := Data_Len_Bytes / 4;
      N_Blocks       : constant Natural := Data_Len_Bytes / BLOCKLEN;
      Data_Addr      : constant Address := Data (Data'first)'Address;

      Err        : SD_Error;
      cardstatus : HAL.Word;
      start      : Time := Clock;
      Timeout    : Boolean := False;
      Command    : SDMMC_Command;

      use STM32.DMA;
   begin

      if not STM32.DMA.Compatible_Alignments (DMA,
                                              Stream,
                                              Controller.Periph.FIFO'Address,
                                              Data_Addr)
      then
         return DMA_Alignment_Error;
      end if;

      --  this is all according tom STM RM0090 sec.31.3.2 p. 1036. But something is wrong.

      Controller.Periph.DCTRL := (DTEN   => False,
                                  others => <>);
      --  Wait 1ms: After a data write, data cannot be written to this register
      --  for three SDMMCCLK (48 MHz) clock periods plus two PCLK2 clock
      --  periods.
      --Controller.Periph.CLKCR.CLKDIV := 16#0#; --  switch to nominal speed, in case polling was active before
      delay until Clock + Milliseconds (1);

      Clear_Static_Flags (Controller);

      --  wait until card is ready for data added
      Wait_Ready_loop :
      loop
         declare
            now : Time := Clock;
         begin
            if now - start > Milliseconds (100) then
               Timeout := True;
               exit Wait_Ready_Loop;
            end if;
         end;

         Send_Command
           (Controller,
            Command_Index      => Send_Status,
            Argument           => Controller.RCA,
            Response           => Short_Response,
            CPSM               => True,
            Wait_For_Interrupt => False);
         Err := Response_R1_Error (Controller, Send_Status);

         if Err /= OK then
            return Err;
         end if;

         cardstatus := Controller.Periph.RESP1;
         exit Wait_Ready_Loop when (cardstatus and 16#100#) /= 0;
      end loop Wait_Ready_Loop;

      if Timeout then
         return Timeout_Error;
      end if;

      Enable_Interrupt (Controller, Data_CRC_Fail_Interrupt);
      Enable_Interrupt (Controller, Data_Timeout_Interrupt);
      Enable_Interrupt (Controller, Data_End_Interrupt); -- this never comes
      Enable_Interrupt (Controller, TX_Underrun_Interrupt); -- not used in https://github.com/lvniqi/STM32F4xx_DSP_StdPeriph_Lib_V1.3.0/blob/master/Libraries/SDIO/sdio_sdcard.c
      -- TODO: stop bit interrupt

      -- start DMA first
      STM32.DMA.Start_Transfer_with_Interrupts
        (Unit               => DMA,
         Stream             => Stream,
         Destination        => Controller.Periph.FIFO'Address,
         Source             => Data_Addr,
         Data_Count         => Unsigned_16 (Data_Len_Words), -- because DMA is set up with words
         Enabled_Interrupts => (Transfer_Error_Interrupt    => True,
                                FIFO_Error_Interrupt        => True, -- test: comment to see what happens
                                Transfer_Complete_Interrupt => True,
                                others                      => False));

      --  set block size
      Send_Command
        (Controller,
         Command_Index      => Set_Blocklen,
         Argument           => BLOCKLEN,
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      Err := Response_R1_Error (Controller, Set_Blocklen);

      if Err /= OK then
         return Err;
      end if;

      --  set write address & single/multi mode
      if N_Blocks > 1 then
         Command := Write_Multi_Block;
         Controller.Operation := Write_Multiple_Blocks_Operation;
      else
         Command := Write_Single_Block;
         Controller.Operation := Write_Single_Block_Operation;
      end if;
      Send_Command
        (Controller,
         Command_Index      => Command,
         Argument           => Word (Write_Address),
         Response           => Short_Response,
         CPSM               => True,
         Wait_For_Interrupt => False);
      Err := Response_R1_Error (Controller, Command);
      --  according to RM0090 we should wait for SDIO_STA[6] = CMDREND interrupt, which is this:
      if Err /= OK then
         return Err;
      end if;

      --  and now enable the card with DTEN, which is this:
      Configure_Data
        (Controller,
         Data_Length        => UInt25 (N_Blocks) * BLOCKLEN,
         Data_Block_Size    => Blocksize2DBLOCKSIZE (BLOCKLEN),
         Transfer_Direction => Write,
         Transfer_Mode      => Block,
         DPSM               => True,
         DMA_Enabled        => True);

      --  according to RM0090: wait for STA[10]=DBCKEND
      --  check that no channels are still enabled by polling DMA Enabled Channel Status Reg

      return Err;
   end Write_Blocks_DMA;

   -------------------------
   -- Get_Transfer_Status --
   -------------------------

--     function Get_Transfer_Status
--       (Controller : in out SDMMC_Controller) return SD_Error
--     is
--     begin
--        if Controller.Periph.STA.DTIMEOUT then
--           Controller.Periph.ICR.DTIMEOUTC := True;
--           return Timeout_Error;
--
--        elsif Controller.Periph.STA.DCRCFAIL then
--           Controller.Periph.ICR.DCRCFAILC := True; -- clear
--           return CRC_Check_Fail;
--
--        elsif Controller.Periph.STA.TXUNDERR then
--           Controller.Periph.ICR.TXUNDERRC := True;
--           return TX_Underrun;
--
--        elsif Controller.Periph.STA.STBITERR then
--           Controller.Periph.ICR.STBITERRC := True;
--           return Startbit_Not_Detected;
--
--        elsif Controller.Periph.STA.RXOVERR then
--           Controller.Periph.ICR.RXOVERRC := True;
--           return Rx_Overrun;
--        end if;
--
--        return OK;
--     end Get_Transfer_Status;

end STM32.SDMMC;
