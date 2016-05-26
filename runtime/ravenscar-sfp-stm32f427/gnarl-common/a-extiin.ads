------------------------------------------------------------------------------
--                                                                          --
--                         GNAT RUN-TIME COMPONENTS                         --
--                                                                          --
--         A D A . E X E C U T I O N _ T I M E . I N T E R R U P T S        --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
-- This specification is derived from the Ada Reference Manual for use with --
-- GNAT.  In accordance with the copyright of that document, you can freely --
-- copy and modify this specification,  provided that if you redistribute a --
-- modified version,  any changes that you have made are clearly indicated. --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Interrupts;

package Ada.Execution_Time.Interrupts with SPARK_Mode => Off is

   function Clock (Interrupt : Ada.Interrupts.Interrupt_ID) return CPU_Time;

   function Supported (Interrupt : Ada.Interrupts.Interrupt_ID) return Boolean;

end Ada.Execution_Time.Interrupts;
