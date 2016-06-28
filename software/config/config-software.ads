-- Institution: Technische Universität München
-- Department:  Realtime Computer Systems (RCS)
-- Project:     StratoX
-- Module:      Software Configuration
--
-- Authors: Emanuel Regnath (emanuel.regnath@tum.de)
--
-- Description:
-- Configuration of the Software, adjust these parameters to your needs

with Units;
with Logger;

package Config.Software is

   DEBUG_MODE_IS_ACTIVE : constant Boolean := True;

   CFG_LOGGER_LEVEL_UART : constant Logger.Log_Level := Logger.DEBUG;

   MAIN_TICK_RATE_MS : constant := 40;   -- Tickrate in Milliseconds

   -- PX4IO Timeout RC  : 2000ms
   -- PX4IO Timeout FMU (no controls) : 500ms

   -- Bus Timeouts
   I2C_READ_TIMEOUT : constant Units.Time_Type := Units.Time_Type (10.0);

   -- filter configuration

   -- PID configuration

         
   
   -- PID Controller
   CFG_PID_PITCH_P : constant := 0.550;
   CFG_PID_PITCH_I : constant := 0.040;
   CFG_PID_PITCH_D : constant := 0.020;
   
   CFG_PID_ROLL_P : constant := 0.450;
   CFG_PID_ROLL_I : constant := 0.060;
   CFG_PID_ROLL_D : constant := 0.020;

   CFG_PID_HEADING_P : constant := 0.450;
   CFG_PID_HEADING_I : constant := 0.060;
   CFG_PID_HEADING_D : constant := 0.020;


end Config.Software;
