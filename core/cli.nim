import ../codegen/codegen
import ../codegen/targets/target
import memory
import pattern
import os
import strutils

var
    vm_debug*: bool = C_setDebug(false)
    vm_recompile*: bool = false
    vm_file_out*: string = ""
    vm_file_in*: string = ""
    vm_build*: bool = false
    vm_run*: bool = false
    vm_version*: string = c_version
    vm_execTarget*: string = "native"
    vm_execPlatform*: string = ""
    vm_linkerfiles*: seq[string] = @[]
    vm_generateObjectFile*: bool

let BACKENDS: seq[string] = vm_languages[]

const TARGETS: seq[string] = @[
  "linux64",
  "win64",
  "darwin",
]

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
    const message_head: string = "Gravity Virtual Machine\n---------------------------\nUsage: gvm <command> <options> <flags>\n"
    const message_body: seq[string] = @[
        "Commands:",
        "  disassemble            Disassembles the given file and displays each intruction",
        "  build                  Compile the given bytecode file",
        "  run                    Compile and run the given bytecode file",
        "  generate-object        Compile the given bytecode file to an object file",
        "  clean-cache            Removes all cached information from the cache directory",
        "",
        "Options:",
        "  -i: | <input_file>              Specify the input file",
        "  -o: | <output_file>             Specify the output file <Optional>",
        "  -b: | <language>                Specify the language to compile/transpile to",
        "  -f: | <language>                Specify the fallback language to recompile to",
        "  -w: | <true|false>              Set the warning state to either show (or not show) warnings",
        "  -L: | <path/to/file>            Specify a file to link with (can be used more than once)",
        "  -P: | <platform>                Specify the target platform",
        "  -verbose: | <true|false>        Set the verbosity of the virtual machine <Default: false>",
        "  -intermediates: | <true|false>  Prevent clean-up after execution, keeping all intermediate files <Default: false>",
        "",
        "Flags:",
        "  --help                 Display this message and exit",
        "  --version              Display the current version of gravity",
        "  --targets              Display all available compilation langauges/targets",
        "  --platforms            Display all available platforms",
    ]
    echo message_head & "\n" & message_body.join("\n")
    quit()


proc parseArgs*(argc: int, argv: seq[string]): void =
    if argc == 0:
        displayHelpMessage()
    else:
        for i in 0..(argc - 1):
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

                # Target Language
                elif (arg[0..1] == "b:"):
                    if arg.len < 3:
                        echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
                        echo "|> Reason: Language argument expected after -b:"
                        quit()
                    case arg[2..<(arg.len)]
                    of "native":
                        vm_recompile = C_setState("recompile", true)
                        vm_execTarget = "native"
                    of "c":
                        vm_recompile = C_setState("recompile", true)
                        vm_execTarget = "c"
                        C_setTranspile(true, "c")
                    of "lua":
                        vm_recompile = C_setState("recompile", true)
                        vm_execTarget = "lua"
                        C_setTranspile(true, "lua")
                    of "js":
                        vm_recompile = C_setState("recompile", true)
                        vm_execTarget = "javascript"
                        C_setTranspile(true, "javascript")
                    else:
                        echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
                        echo "|> Reason: Unsupported Language: " & arg[2..<(arg.len)]
                        quit()

                # Fallbacks
                elif (arg[0..1] == "f:"):
                    if arg.len < 3:
                        echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
                        echo "|> Reason: Language argument expected after -f:"
                        quit()
                    case arg[2..<(arg.len)]
                    of "native":
                        c_backup = "native"
                    of "c":
                        c_backup = "c"
                    of "lua":
                        c_backup = "lua"
                    of "js":
                        c_backup = "js"
                    else:
                        echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
                        echo "|> Reason: Unsupported Language: " & arg[2..<(arg.len)]
                        quit()

                # Linker Files
                elif (arg[0..1] == "L:"):
                    if arg.len < 3:
                       echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
                       echo "|> Reason: Language argument expected after -L:"
                       quit()
                    let file: string = arg[2..<(arg.len)]
                    c_linkerfiles.add(file)
                    vm_linkerfiles.add(file)

                # Target Platform
                elif (arg[0..1] == "P:"):
                    if arg.len < 3:
                      echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
                      echo "|> Reason: Language argument expected after -L:"
                    let platform: string = arg[2..<(arg.len)]
                    C_setPlatform("amd64", platform)

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
                    echo "\e[1mgravity: \e[0m"
                    echo "|> Version: " & c_version
                    echo "|> Lisence: MIT 2025"
                    quit()

                # Langauges
                elif (arg == "-targets"):
                    echo "Available Compilation Targets:"
                    for target in BACKENDS:
                      echo " > " & target
                    quit()

                # Platforms
                elif (arg == "-platforms"):
                    echo "Supported Platforms:"
                    for platform in TARGETS:
                      echo " > " & platform
                    quit()

                # Verbose
                elif (arg == "verbose:true"):
                    c_verbose = true

                elif (arg == "verbose:fale"):
                    c_verbose = false

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
            of "generate-object":
                generateObjectFile = true
                c_generateObjectFile = true
                vm_generateObjectFile = true
                vm_build = C_setState("build", true)
            of "clean-cache":
                const homedir: string = getEnv("HOME")
                const gvmdir: string = homedir / ".cache" / "GravityVM"
                for kind, name in  walkDir(gvmdir):
                    if $kind == "pcFile" and not name.endsWith(".config"):
                        removeFile(name)
                echo "\e[1mCache Cleared!\e[0m"
                quit()
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
