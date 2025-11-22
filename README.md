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

### Spcial Register List:
	sra
	srb
	src
	srd
	sre
	srnl (used for only for newline char | value should not be changed)

### Instructions: (NAME: OPCDE: [Arguments])
	NOP:    00 [None, None, None]
	READ:   01 [Store Location, None None]
	WRITE:  02 [Data Location/String, None, None]
	STORE:  03 [Store Location, Data, None]
	DEL:    04 [Location, None, None]
	COPY:   05 [Copy Location, Data, None]
	UPD:    0G [Location, Data, None)
	MALLOC: 0H [Memory Pool Type, Amount, None]
	FREE:   0I [Memory Pool Type, None, None]

	ADD:    05 [Data Location/Number, Data Location/Number, Store Location [sra by default]]
	SUB:    06 [Data Location/Number, Data Location/Number, Store Location [sra by default]]
	MUL:    07 [Data Location/Number, Data Location/Number, Store Location [sra by default]]
	DIV:    08 [Data Location/Number, Data Location/Number, Store Location [sra by default]]
	EXP:    09 [Data Location/Number, Data Location/Number, Store Location [sra by default]]
	INC:    0E [Data Location, None, None]
	DEC:    0F [Data Location, None, None]

	JMP:    0B [Labal, None, None]
	JNZ:    0C [Label, None, None]
	JEZ:    0K [Label, None, None]
	CMP:    0D [Data Location, Data Location, None]

	LBL:    0J [String, None, None]

	EXIT:   0L [Data Location/Number, None, None]
