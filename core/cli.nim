import ../codegen/codegen
import pattern

var vm_debug*: bool = C_setDebug(false)
var vm_recompile*: bool = false
var vm_file_out*: string = ""
var vm_file_in*: string = ""
var vm_build*: bool = false
var vm_run*: bool = false
var vm_version*: string = c_version
var vm_execTarget*: string = ""


proc join(list: seq[auto], sep: string = ""): string =
    let length: int = list.len-1
    var outstr: string = ""
    for i in 0..length:
        if i < length:
            outstr = outstr & $list[i] & sep
        else:
            outstr = outstr & $list[i]
    return outstr


proc displayHelpMessage(): void =
    const message_head: string = "Usage: gravity <command> <options?>"
    const message_body: seq[string] = @[
        "Commands:",
        "  disassemble            Disassembles the given file and displays each intruction",
        "  build                  Compile the given bytecode file",
        "  run                    Compile and run the given bytecode file",
        "Options:",
        "  --help                     Display this message and exit",
        "  --version                  Display the current version of gravity",
        "  -i:[input_file]            Set the input file",
        "  -o:[output_file]           Set the output file <Optional>",
        "  -f:[native|perl]           Force recompilation, ignoring the current cache file | Force perl transpilation instead of automatic compilation/transpilation",
        "  -w:[true (default)|false]  Set the warning state to either show (or not show) warnings",
        "  -intermediates:[true|false (default)]  Prevent clean-up after execution, keeping all intermediate files",
    ]
    echo message_head & "\n" & message_body.join("\n")
    quit()


proc parseArgs*(argc: int, argv: seq[string]): void =
    if argc == 0:
        displayHelpMessage()
    else:
        for i in 0..(argc-1):
            var arg: string = argv[i]
            case arg[0]:
            of '-':
                arg = arg[1..<arg.len]
                # Output file
                if (arg <?> "o:").Result:
                    let fname:string = arg.chomp("o:")
                    vm_file_out = C_setOutputFile(fname)

                # Input File
                elif (arg <?> "i:").Result:
                    let fname:string = arg.chomp("i:")
                    if (fname <?> ".").Result:
                        let fname_out = fname[0..(fname <?> ".").Region[0] - 1]
                        vm_file_out = C_setOutputFile(fname_out)
                    vm_file_in = C_setInputFile(fname)

                # Force Recompile
                elif (arg == "f:native"):
                    vm_recompile = C_setState("recompile", true)
                    vm_execTarget = "native"

                # Force Transpile
                elif (arg == "f:perl"):
                    vm_recompile = C_setState("recompile", true)
                    vm_execTarget = "perl"
                    C_setTranspile(true)

                # Help Message
                elif (arg == "-help"):
                    displayHelpMessage()

                # Clean Up
                elif (arg == "intermidiates:true"):
                    C_setState("cleanup", false)
                    vm_recompile = C_setState("recompile", true)

                elif (arg == "intermidiates:false"):
                    C_setState("cleanup", true)
                    vm_recompile = C_setState("recompile", true)

                # Version
                elif (arg == "-version"):
                    echo "GravityVM (gravity): "
                    echo "|> Version: " & c_version
                    echo "|> Lisence: MIT 2025"
                    quit()

                # Warnings
                elif (arg == "w:true"):
                    echo "IMPLEMENT WARNINGS!!!"
                    echo "CREATE c_warn!!!"

                elif (arg == "w:false"):
                    echo "WARNINGS OFF <IMPLEMENT>!!!"

                else:
                    echo "gravity: invalid option: " & $argv[i]
                    displayHelpMessage()
            else:
                discard

            case argv[0]
            of "build":
                vm_build = C_setState("build", true)
            of "disassemble":
                vm_debug = C_setDebug(true)
            of "run":
                vm_build = C_setState("build", true)
                vm_run = C_setState("run", true)
            else:
                echo "gravity: invalid command: " & argv[0]
                displayHelpMessage()

    # Error Handling
    if vm_file_in == "":
        echo "\e[1mgravity: <\e[91mIO-Error\e[0m\e[1m>\e[0m"
        echo "|> Compilation Stopped!"
        echo "|> Reason: No input file specified"
        quit()

    try:
        discard open(vm_file_in, fmRead)
    except IOError as e:
        echo "\e[1mgravity: <\e[91mIO-Error\e[0m\e[1m>\e[0m"
        echo "|> Compilation Stopped!"
        echo "|> Reason: Cannot open file '" & vm_file_in  & "'"
        echo "|\e[90m--------\e[0m> File or directory does not exist"
        #echo "\e[90m|> nim: " & e.msg & "\e[0m"
        quit()

    # Hard set debug mode to false (if it was never set to true)
    if not vm_debug:
        discard C_setDebug(false,false)
