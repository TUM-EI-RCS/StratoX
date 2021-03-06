--  Institution: Technische Universität München
--  Department:  Realtime Computer Systems (RCS)
--  Project:     StratoX
--
-- Authors: Emanuel Regnath (emanuel.regnath@tum.de)
pragma SPARK_Mode (Off);

with STM32.USARTs;
with STM32.Device;
with HIL.Config;

with Ada.Interrupts;       use Ada.Interrupts;
with Ada.Interrupts.Names; use Ada.Interrupts.Names;

with Generic_Queue; 
with HIL.Devices;

--  @summary
--  Target-specific mapping for HIL of UART
package body HIL.UART with
   SPARK_Mode => Off
is  
   
   procedure configure with SPARK_Mode => Off is 
   begin
      -- UART 1
      -- STM32.USARTs.Enable( STM32.Device.USART_1 );
      STM32.USARTs.Set_Stop_Bits( STM32.Device.USART_1, STM32.USARTs.Stopbits_1 );
      STM32.USARTs.Set_Word_Length( STM32.Device.USART_1, STM32.USARTs.Word_Length_8 );
      STM32.USARTs.Set_Parity( STM32.Device.USART_1, STM32.USARTs.No_Parity );
      STM32.USARTs.Set_Baud_Rate( STM32.Device.USART_1, 9_600 );
      STM32.USARTs.Set_Oversampling_Mode( STM32.Device.USART_1, STM32.USARTs.Oversampling_By_16 );
      STM32.USARTs.Set_Mode( STM32.Device.USART_1, STM32.USARTs.Tx_Rx_Mode );
      STM32.USARTs.Set_Flow_Control( STM32.Device.USART_1, STM32.USARTs.No_Flow_Control );

      -- UART 6 (PX4IO)
      STM32.USARTs.Enable( STM32.Device.USART_6 );
      STM32.USARTs.Set_Stop_Bits( STM32.Device.USART_6, STM32.USARTs.Stopbits_1 );
      STM32.USARTs.Set_Word_Length( STM32.Device.USART_6, STM32.USARTs.Word_Length_8 );
      STM32.USARTs.Set_Parity( STM32.Device.USART_6, STM32.USARTs.No_Parity );
      STM32.USARTs.Set_Baud_Rate( STM32.Device.USART_6, HIL.Config.PX4IO_BAUD_RATE_HZ );
      STM32.USARTs.Set_Oversampling_Mode( STM32.Device.USART_6, STM32.USARTs.Oversampling_By_16 );
      STM32.USARTs.Set_Mode( STM32.Device.USART_6, STM32.USARTs.Tx_Rx_Mode );
      STM32.USARTs.Set_Flow_Control( STM32.Device.USART_6, STM32.USARTs.No_Flow_Control );
      
      
      -- UART 3 (Serial 2, Tele 2, Console)
      STM32.USARTs.Enable( STM32.Device.USART_3 );
      STM32.USARTs.Set_Stop_Bits( STM32.Device.USART_3, STM32.USARTs.Stopbits_1 );
      STM32.USARTs.Set_Word_Length( STM32.Device.USART_3, STM32.USARTs.Word_Length_8 );
      STM32.USARTs.Set_Parity( STM32.Device.USART_3, STM32.USARTs.No_Parity );
      STM32.USARTs.Set_Baud_Rate( STM32.Device.USART_3, 57_600 );
      STM32.USARTs.Set_Oversampling_Mode( STM32.Device.USART_3, STM32.USARTs.Oversampling_By_16 );
      STM32.USARTs.Set_Mode( STM32.Device.USART_3, STM32.USARTs.Tx_Rx_Mode );
      STM32.USARTs.Set_Flow_Control( STM32.Device.USART_3, STM32.USARTs.No_Flow_Control );

      -- UART 4 (Serial 3, GPS)
      STM32.USARTs.Enable( STM32.Device.UART_4 );
      STM32.USARTs.Set_Stop_Bits( STM32.Device.UART_4, STM32.USARTs.Stopbits_1 );
      STM32.USARTs.Set_Word_Length( STM32.Device.UART_4, STM32.USARTs.Word_Length_8 );
      STM32.USARTs.Set_Parity( STM32.Device.UART_4, STM32.USARTs.No_Parity );
      STM32.USARTs.Set_Baud_Rate( STM32.Device.UART_4, HIL.Config.UBLOX_BAUD_RATE_HZ );
      STM32.USARTs.Set_Oversampling_Mode( STM32.Device.UART_4, STM32.USARTs.Oversampling_By_16 );
      STM32.USARTs.Set_Mode( STM32.Device.UART_4, STM32.USARTs.Tx_Rx_Mode );
      STM32.USARTs.Set_Flow_Control( STM32.Device.UART_4, STM32.USARTs.No_Flow_Control );
      
      -- UART 7 (SER 5)
      STM32.USARTs.Enable( STM32.Device.USART_7 );
      STM32.USARTs.Set_Stop_Bits( STM32.Device.USART_7, STM32.USARTs.Stopbits_1 );
      STM32.USARTs.Set_Word_Length( STM32.Device.USART_7, STM32.USARTs.Word_Length_8 );
      STM32.USARTs.Set_Parity( STM32.Device.USART_7, STM32.USARTs.No_Parity );
      STM32.USARTs.Set_Baud_Rate( STM32.Device.USART_7, 9_600 );
      STM32.USARTs.Set_Oversampling_Mode( STM32.Device.USART_7, STM32.USARTs.Oversampling_By_8 );
      STM32.USARTs.Set_Mode( STM32.Device.USART_7, STM32.USARTs.Tx_Rx_Mode );
      STM32.USARTs.Set_Flow_Control( STM32.Device.USART_7, STM32.USARTs.No_Flow_Control );


      -- Interrupts
      -- Enable GPS Interrupt
      STM32.USARTs.Enable_Interrupts( STM32.Device.UART_4, STM32.USARTs.Received_Data_Not_Empty );
      
      -- Logger Interrupt
      
  
     

   end configure;
      

   
   type Buffer_Index_Type is mod BUFFER_MAX;
   type Buffer_Type is array(Buffer_Index_Type) of Byte;
   package Byte_Buffer_Pack is new Generic_Queue(Index_Type => Buffer_Index_Type, Element_Type => Byte);   
      
      
   protected UART_Interrupt_Handler is
      pragma Interrupt_Priority (HIL.Devices.IRQ_PRIO_UART4);
      
      procedure get_Buffer(data : out Data_Type; len : out Natural);
   private
      buffer_pointer : Buffer_Index_Type := 0;
      Queue : Byte_Buffer_Pack.Buffer_Tag;
      Buffer : Buffer_Type := (others => Byte(0));
   
      procedure Handle_Interrupt
        with Attach_Handler => Ada.Interrupts.Names.UART4_Interrupt,
             Unreferenced;

   end UART_Interrupt_Handler;


   protected Logger_UART_Interrupt_Handler is
      pragma Interrupt_Priority (HIL.Devices.IRQ_PRIO_UART_LOG);
      
      procedure push_Buffer(data : Data_Type);
   private
      buffer_pointer : Buffer_Index_Type := 0;
      Queue : Byte_Buffer_Pack.Buffer_Tag;
      Buffer : Buffer_Type := (others => Byte(0));
   
      procedure Handle_Interrupt
        with Attach_Handler => Ada.Interrupts.Names.USART3_Interrupt,
             Unreferenced;

   end Logger_UART_Interrupt_Handler;



   procedure write (Device : in Device_ID_Type; Data : in Data_Type) is
   begin
      case (Device) is
      when HIL.Devices.GPS =>
         for i in Data'Range loop
            STM32.USARTs.Transmit( STM32.Device.UART_4, HAL.UInt9( Data(i) ) );
         end loop;
      when HIL.Devices.Console =>
         Logger_UART_Interrupt_Handler.push_Buffer(data);
         STM32.USARTs.Enable_Interrupts( STM32.Device.USART_3, STM32.USARTs.Transmit_Data_Register_Empty );
--           for i in Data'Range loop
--              STM32.USARTs.Transmit( STM32.Device.USART_3, HAL.UInt9( Data(i) ) );
--           end loop;
      when HIL.Devices.PX4IO =>
         for i in Data'Range loop
            STM32.USARTs.Transmit( STM32.Device.USART_6, HAL.UInt9( Data(i) ) );
         end loop; 
      end case;
   end write;


   procedure read (Device : in Device_ID_Type; Data : out Data_Type; n_read : out Natural) 
     with SPARK_Mode => Off is
   begin
      case (Device) is
      when HIL.Devices.GPS =>
         UART_Interrupt_Handler.get_Buffer (Data, n_read);
      when HIL.Devices.Console =>
         for i in Data'Range loop
            STM32.USARTs.Receive (STM32.Device.USART_3, HAL.UInt9( Data(i)));
         end loop; 
         n_read := Data'Length;           
      when HIL.Devices.PX4IO =>
         for i in Data'Range loop
            STM32.USARTs.Receive (STM32.Device.USART_6, HAL.UInt9( Data(i)));
         end loop;
         n_read := Data'Length;                  
      end case;
   end read;
   

   function toData_Type( Message : String ) return Data_Type is
      Bytes : Data_Type( Message'Range ) := (others => 0);
   begin
      for pos in Message'Range loop
         Bytes(pos) := Character'Pos( Message(pos) );
      end loop;
      return Bytes;
   end toData_Type;



   
   
   protected body UART_Interrupt_Handler is
      

      procedure get_Buffer(data : out Data_Type; len : out Natural) is
         buf_data : Byte_Buffer_Pack.Element_Array(1 .. data'Length);
         qlen : constant Byte_Buffer_Pack.Length_Type := Queue.Length;
      begin
         data := (others => Byte( 0 ) );
         if not Queue.Empty then
            if data'Length <= qlen then
               -- more data than caller can take
               Queue.get_front (buf_data);
               data := Data_Type (buf_data); -- FIXME: slow cast of entire array
               len := data'Length;
            else
               -- not enough data to fill caller
               len := qlen;
               Queue.get_front (buf_data (1 .. qlen));
               data (data'First .. data'First + qlen - 1) := Data_Type (buf_data (1 .. qlen));
            end if;
         else
            len := 0;
         end if;
      end get_Buffer;

      procedure Handle_Interrupt with SPARK_Mode => Off is 
         data : HAL.UInt9;
      begin
          --  check for data arrival
         if STM32.USARTs.Status (STM32.Device.UART_4, STM32.USARTs.Read_Data_Register_Not_Empty) and
           STM32.USARTs.Interrupt_Enabled (STM32.Device.UART_4, STM32.USARTs.Received_Data_Not_Empty)
         then
            STM32.USARTs.Receive( STM32.Device.UART_4, data);
            -- STM32.USARTs.Transmit( STM32.Device.USART_3, HAL.UInt9(65) );
            Queue.push_back( Byte( data ) );
            STM32.USARTs.Clear_Status (STM32.Device.UART_4, STM32.USARTs.Read_Data_Register_Not_Empty);
         end if;
         
      end Handle_Interrupt;
    
   end UART_Interrupt_Handler;
   
   protected body Logger_UART_Interrupt_Handler is
      

      procedure push_Buffer(data : Data_Type) is
      begin
         for index in data'Range loop
            Queue.push_back( Byte( data(index) ) );
         end loop;
      end push_Buffer;

      procedure Handle_Interrupt is
         data : Byte;
      begin
          --  check for data arrival
         if STM32.USARTs.Status (STM32.Device.USART_3, STM32.USARTs.Transmit_Data_Register_Empty) and
           STM32.USARTs.Interrupt_Enabled (STM32.Device.USART_3, STM32.USARTs.Transmit_Data_Register_Empty)
         then
            if not Queue.Empty then
               Queue.pop_front( data );
               STM32.USARTs.Transmit( STM32.Device.USART_3, HAL.UInt9( data ));
            else 
               STM32.USARTs.Disable_Interrupts( STM32.Device.USART_3, STM32.USARTs.Transmit_Data_Register_Empty );
            end if;
            STM32.USARTs.Clear_Status (STM32.Device.USART_3, STM32.USARTs.Transmit_Data_Register_Empty);
         end if;
         
      end Handle_Interrupt;
    
   end Logger_UART_Interrupt_Handler;     
        
end HIL.UART;
