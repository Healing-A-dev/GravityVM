# GravityVM
------
> [!WARNING]
> GravityVM is VERY work in progress, and I have a lot more to get done with it as well!
-------
### About:
GravityVM is a small, lightweight, memory/register based virtual machine that operates on a custom bytecode format.

	Memory addresses range from "01" -> "zz".
	The bytecode format that GravityVM operates on follows a 4 block structure: INSTRUCTION ARG0 ARG1 ARG2.


	Each bytecode is a total length of 2 characters (ie. "02") with a few exceptions.
	Exception 1:
	   Anything surrounded by '[]' is either a string value, a float, any integer with a value over 100, or a special register location
	Exception 2:
	   Anything begining with [@, $, %] represent pointers to a location in a given memory pool


	There are 4 possible memory locations within Gravity:
	 - Global Memory Pool [@]
	 - Local Memory Pool [$]
	 - Buffer Memory Pool [%]
	 - Special Register Locations [<register-location>]


	Supports multiple backends:
	 - Compile to native code (default)
	 - C
	 - Lua
	 - Javascript
	 

### Spcial Register List:
	sra
	srb
	src
	srd
	sre
	srnl (used for only for newline char | value should NOT be changed)

### Instructions: (NAME: OPCDE: [Arguments])
    00:  NOP         [00, 00, 00]
    01:  READ        [Location, 00, 00]
    02:  WRITE       [Location/Hex String, 00, 00]
    03:  STORE       [Location, Data, 00]
    04:  DEL         [Location, 00]
    05:  ADD         [Location/Number, Location/Number, Location <Default: sra>]
    06:  SUB         [Location/Number, Location/Number, Location <Default: sra>]
    07:  MUL         [Location/Number, Location/Number, Location <Default: sra>]
    08:  DIV         [Location/Number, Location/Number, Location <Default: sra>]
    09:  EXP         [Location/Number, Location/Number, Location <Default: sra>]
    0A:  COPY        [Location, Data, 00]
    0B:  JMP         [Label, 00, 00]
    0C:  JNZ         [Label, 00, 00]
    0D:  CMP         [Location, Location, 00]
    0E:  INC         [Location, 00]
    0F:  DEC         [Location, 00]
    0G:  UPD         [Location, Data, 00]
    0H:  MALLOC      [Memory Pool Type, 00, 00]
    0I:  FREE        [Memory Pool Type, 00, 00]
    0J:  LBL         [Hex String, 00, 00]
    0K:  JNZ         [Label, 00, 00]
    0L:  EXIT        [Location/Number, 00, 00]
    0M:  LT          []
    0N:  GT          []
    0P:  JF          []
    0O:  ITS         []
    0T:  TYPEOF      []
    1A:  PUSH        []
    1B:  CALL        []
    1C:  RET         []
    1D:  GETARG      []
    1E:  STR         []
    1F:  WRITES      []
    1G:  CALLD       []
    1H:  EXPO        []
    1I:  ETRN        []
    20:  NEWMAP      []
    21:  MSET        []
    22:  MGET        []
    23:  MLEN        []
    24:  MHEAD       []
    25:  MKEY        []
    26:  MVAL        []
    27:  MNEXT       []
    30:  NEWARR      []
    28:  FOPEN       []
    29:  FWRITE      []
    2A:  FREAD       []
    2B:  FCLOSE      []
    2E:  READF       []
    2C:  ARGV        []
    2D:  CAT         []
    3A:  MOVSD       []
    3B:  FSTORE      []
    40:  MOV         []
    41:  NSUB        []
    42:  NADD        []
    50:  NET_SOCKET  []
    51:  NET_BIND    []
    52:  NET_LISTEN  []
    53:  NET_ACCEPT  []
    54:  NET_WRITE   []
    55:  NET_CLOSE   []
    56:  NET_RECV    []
----
# Example Program
- Note: Gravity does NOT support comments, they are only here for documentation purposes:
```
// Allocate (Reserve) 10 slots in the local memory pool (only 2 are needed, but for example purposes i will allocate more)
0H $00 10 00

// Allocating (Reserving) 3842 (the maximum) spots in the global and buffer (temporary) memory pools repectivly (Only for example)
0H @00 3842 00
0H %00 3842 00

// Storing '10' into the local memory pool (at position 01 ($01)
03 $01 10 00

// Storing '20' into the global memory pool (at position 0a ($0a)
03 @0a 20 00

// Add $01 and @0a
05 $01 @0a 00

// OPTION 1:
// Print register [sra] directly
02 [sra] 00 00
02 [srnl] 00 00 // Newline character

// OPTION 2:
// Move [sra] to a memory pool location and display the memory pool location
0A %01 [sra] 00
02 %01 00 00
02 [srnl] 00 00


// Note, string can be directly printed:
// 02 [Hello, World\n] 00 00 -> Hello, World

// Exit code safely
0L 0 00 00

// Free Local, Global, and Buffer memory pools respectivly
0I $00 00 00
0I @00 00 00
0I %00 00 00
```
