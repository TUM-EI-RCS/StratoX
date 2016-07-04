-- Institution: Technische Universität München
-- Department: Realtime Computer Systems (RCS)
-- Project: StratoX
-- Module: Helper
--
-- Authors: Emanuel Regnath (emanuel.regnath@tum.de)
--
-- Description: Helper functions
-- 
-- ToDo:
-- [ ] Implementation


package Helper is


   generic
      type Numeric_Type is range <>;
   function addWrap( 
                     x   : Numeric_Type; 
                     inc : Numeric_Type)
                    return Numeric_Type;



--    function deltaWrap( 
--      low  : Integer; 
--      high : Integer) 
--    return Integer 
--    is ( if low < high then (high - low)
--         else (high'Last - low) + (high - low'First) );



   -- to polar

   procedure delay_ms( ms : Natural);
   

   --  Saturate a Float value within a given range.
   function Saturate
     (Value     : Float;
      Min_Value : Float;
      Max_Value : Float) return Float is
     (if Value < Min_Value then
         Min_Value
      elsif Value > Max_Value then
         Max_Value
      else
         Value);
   pragma Inline (Saturate);

end Helper;
