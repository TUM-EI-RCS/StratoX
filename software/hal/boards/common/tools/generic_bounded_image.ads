with Interfaces; use Interfaces;

--  @summary functions to provide a string image of numbers
--  overapproximating the length, otherwise too much code needed.
package Generic_Bounded_Image with SPARK_Mode is

   generic
      type T is (<>); -- any modular type or discrete
   function Image_32 (item : T) return String
     with Post => Image_32'Result'Length in 1 .. 32 and Image_32'Result'First = 1, Inline;

   generic
      type T is (<>); -- any modular type or discrete
   function Image_4 (item : T) return String
     with Post => Image_4'Result'Length in 1 .. 4 and Image_4'Result'First = 1, Inline;

end Generic_Bounded_Image;
