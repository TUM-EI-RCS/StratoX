package FAT_Filesystem.Directories with SPARK_Mode is

   type Directory_Handle is private; -- used to read directories

   function Open_Root_Directory
     (FS  : FAT_Filesystem_Access;
      Dir : out Directory_Handle) return Status_Code;

   type Directory_Entry is private; -- used to represent one item in directory

   function Open
     (E   : Directory_Entry;
      Dir : out Directory_Handle) return Status_Code
     with Pre => Is_Subdirectory (E);
   --  get handle of given item. Handle can be used with Read().

   function Make_Directory
     (Parent  : in Directory_Entry;
      newname : String;
      D_Entry : out Directory_Entry) return Status_Code
     with Pre => newname'Length <= 12;
   --  create a new directory within the given one
   --  we only allow short names for now

   procedure Close (Dir : in out Directory_Handle);

   function Read (Dir : in out Directory_Handle;
                  DEntry : out Directory_Entry) return Status_Code;
   --  @summary get the next entry in the given directory

   function Name (E : Directory_Entry) return String;

   function Is_Read_Only (E : Directory_Entry) return Boolean;

   function Is_Hidden (E : Directory_Entry) return Boolean;

   function Is_System_File (E : Directory_Entry) return Boolean;

   function Is_Subdirectory (E : Directory_Entry) return Boolean;

   function Is_Archive (E : Directory_Entry) return Boolean;

private
   pragma SPARK_Mode (Off);

   type FAT_Directory_Entry_Attribute is record
      Read_Only : Boolean;
      Hidden    : Boolean;
      System_File : Boolean;
      Volume_Label : Boolean;
      Subdirectory : Boolean;
      Archive      : Boolean;
   end record with Size => 8, Pack;

   type FAT_Directory_Entry is record
      Filename   : String (1 .. 8);
      Extension  : String (1 .. 3);
      Attributes : FAT_Directory_Entry_Attribute;
      Reserved   : String (1 .. 8);
      Cluster_H  : Unsigned_16;
      Time       : Unsigned_16;
      Date       : Unsigned_16;
      Cluster_L  : Unsigned_16;
      Size       : Unsigned_32; -- TODO: what is this?
   end record with Size => 32 * 8; --  32 Byte per entry

   for FAT_Directory_Entry use record
      Filename   at 16#00# range 0 .. 63;
      Extension  at 16#08# range 0 .. 23;
      Attributes at 16#0B# range 0 .. 7;
      Reserved   at 16#0C# range 0 .. 63;
      Cluster_H  at 16#14# range 0 .. 15;
      Time       at 16#16# range 0 .. 15;
      Date       at 16#18# range 0 .. 15;
      Cluster_L  at 16#1A# range 0 .. 15;
      Size       at 16#1C# range 0 .. 31;
   end record;

   VFAT_Directory_Entry_Attribute : constant FAT_Directory_Entry_Attribute :=
                                      (Subdirectory => False,
                                       Archive      => False,
                                       others       => True);
   --  Attrite value 16#F0# defined at offset 16#0B# and identifying a VFAT
   --  entry rather than a regular directory entry

   type VFAT_Sequence_Number is mod 2 ** 5
     with Size => 5;

   type VFAT_Sequence is record
      Sequence : VFAT_Sequence_Number;
      Stop_Bit : Boolean;
   end record with Size => 8, Pack;

   type VFAT_Directory_Entry is record
      VFAT_Attr : VFAT_Sequence;
      Name_1    : Wide_String (1 .. 5);
      Attribute : FAT_Directory_Entry_Attribute;
      E_Type    : Unsigned_8;
      Checksum  : Unsigned_8;
      Name_2    : Wide_String (1 .. 6);
      Cluster   : Unsigned_16;
      Name_3    : Wide_String (1 .. 2);
   end record with Pack, Size => 32 * 8;

--     type File_Object_Structure is record
--        FS              : FAT_Filesystem_Access;
--        Flags           : Unsigned_8;
--        Err             : Unsigned_8;
--        File_Ptr        : Unsigned_32 := 0;
--        File_Size       : Unsigned_32;
--        Start_Cluster   : Unsigned_32;
--        Current_Cluster : Unsigned_32;
--     end record;

   type Directory_Handle is record
      FS              : FAT_Filesystem_Access;
      Current_Index   : Unsigned_16; -- current entry in the directory
      Start_Cluster   : Unsigned_32; -- first cluster of the direcory
      Current_Cluster : Unsigned_32; -- cluster belonging to current_index
      Current_Block   : Unsigned_32; -- block belonging to current index
   end record;
   --  used to read directories

   type Directory_Entry is record
      FS            : FAT_Filesystem_Access;
      Long_Name        : String (1 .. 128); -- long name (VFAT)
      Long_Name_First  : Natural := 129; -- where it starts
      Short_Name       : String (1 .. 12); -- short name
      Short_Name_Last  : Natural := 0; -- where it starts
      Attributes    : FAT_Directory_Entry_Attribute;
      Start_Cluster : Unsigned_32;
      Size          : Unsigned_32; -- TODO: what is this?
   end record;
   --  each item in a directory is described by this

   function Allocate_Entry
     (Parent_Ent : in  Directory_Entry;
      Ent_Addr   : out FAT_Address) return Status_Code;
   --  find a location for a new entry within Parent_Ent

   procedure Set_Shortname (newname : String; E : in out FAT_Directory_Entry)
     with Pre => newname'Length > 0;

   function Directory_To_FAT_Entry
     (D_Entry : in Directory_Entry;
      F_Entry : out FAT_Directory_Entry) return Status_Code;

   function FAT_To_Directory_Entry
     (FS : FAT_Filesystem_Access;
      F_Entry : in FAT_Directory_Entry;
      D_Entry : in out Directory_Entry;
      Last_Seq : in out VFAT_Sequence_Number) return Status_Code;

   function Is_Read_Only (E : Directory_Entry) return Boolean
   is (E.Attributes.Read_Only);

   function Is_Hidden (E : Directory_Entry) return Boolean
   is (E.Attributes.Hidden);

   function Is_System_File (E : Directory_Entry) return Boolean
   is (E.Attributes.System_File);

   function Is_Subdirectory (E : Directory_Entry) return Boolean
   is (E.Attributes.Subdirectory);

   function Is_Archive (E : Directory_Entry) return Boolean
   is (E.Attributes.Archive);

end FAT_Filesystem.Directories;
