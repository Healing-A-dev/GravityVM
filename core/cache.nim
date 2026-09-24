import strutils
import cli
import pattern
import osproc
import os

var cacheData: seq[string] = @[]
const homeDirectory: string = getEnv("HOME")
const gravityDirectory: string = homeDirectory / ".cache" / "GravityVM"
var CONFIG: seq[string]
var MAX_ENTRIES: int
var COMPARE_CACHE: int

proc loadCacheConfig*(): void =
    if not fileExists(gravityDirectory / ".config"):
        let file = open(gravityDirectory / ".config", fmWrite)
        defer: close(file)
        file.write("MAX_ENTRIES = 9\nCOMPARE_CACHE = 0")
    CONFIG = readFile(gravityDirectory / ".config").splitLines()
    MAX_ENTRIES = parseInt(CONFIG[0].replace("MAX_ENTRIES = ", ""))
    COMPARE_CACHE = parseInt(CONFIG[1].replace("COMPARE_CACHE = ", ""))


# Directory Stripper
proc stripDir(file_path: string ): string =
    var directory: seq[char] = @[]
    var tmp: seq[char] = @[]

    if not file_path.contains("/"):
        return file_path

    directory.add(file_path[file_path.len - 1])
    while directory[directory.len - 1] != '/':
        directory.add(file_path[file_path.len - 1 - (directory.len - 1)])

    var s: int  = directory.len - 2
    while s > 0:
        tmp.add(directory[s])
        s.dec()

    return tmp.join()


proc indexCache(directory: string): tuple[Count: int, Files: seq[string]] =
    var files: seq[string] = @[]
    for kind, name in  walkDir(directory):
        var kind: string = $kind
        if kind == "pcFile":
            files.add(name)

    # Subtracting 1 from the count to compensate for the .config file
    return (Count: files.len - 1, Files: files)


proc generateHash(str: seq[string]): string =
    var total: int = 0
    var count: int = 0
    var hash: string = ""

    for str_block in str:
        for character in str_block:
            total = total + character.ord

    # Generate hash
    var tmp: string = $total
    if (tmp.len mod 2) != 0:
        while count < tmp.len-2:
            hash = hash & (parseInt(tmp[count] & tmp[count+1]) + 32).char()
            count.inc(2)
        hash = hash & (parseInt($tmp[count]) + 32).char()
    else:
        while count < tmp.len-1:
            hash = hash & (parseInt(tmp[count] & tmp[count+1]) + 32).char()
            count.inc(2)

    return $total & hash


proc generateData*(fname: string, instructions: seq[string]): int {.discardable.} =
    var vm_execTargetI = vm_execTarget
    if vm_generateObjectFile == true:
        vm_execTargetI = "object"
    let instruction_counter: string = $(instructions.len / 4)
    cacheData.add("(Start: Project")
    cacheData.add("    (Definition: Name => \"" & vm_file_out & "\")")
    cacheData.add("    (Definition: File => \"" & fname & "\")")
    cacheData.add("    (Definition: ProjectIdentifier => " & $vm_execTarget & "." & generateHash(instructions) & "." & $instructions.len & "-" & $instruction_counter & ")")
    cacheData.add("    (Definition: CompilerVersion => " & vm_version & ")")
    cacheData.add("    (Definition: LinkerFiles => @" & vm_linkerfiles.join(", @") & ")")
    cacheData.add("End: Project)")
    return 0


proc writeCache*(file_path: string): int {.discardable.} =
    let file_location: tuple = (file_path <?> stripDir(file_path))
    var directory: string = ""
    let cache_index: tuple = indexCache(gravityDirectory)

    # Automatically clean cache if over the allowed limit
    if cache_index.Count + 1 > MAX_ENTRIES:
        for file in cache_index.Files:
            if not file.contains("/.config"):
                try:
                    removeFile(file)
                except IOError as e:
                    echo "[Warning] failed to remove file: " & file
                    echo "|----> Info: " & e.msg

    try:
        let file: File = open(gravityDirectory / file_location.Pattern & ".script", fmWrite)
        for item in cacheData:
            file.writeLine(item)
        file.close()
    except IOError:
        let status: int = execCmd("mkdir -p " & gravityDirectory)
        if status != 0: return status
        let file: File = open(gravityDirectory / file_location.Pattern & ".script", fmWrite)
        for item in cacheData:
            file.writeLine(item)
        file.close()
    return 0


proc compareCache*(file_path: string): int =
    # Skip entire check if not comparing cache
    # Reason for implementing this is because of the current way the cache works
    # IF a cache file is found (and is the same as the one generated for the new file) -> Check for already compiled executable
    # This is a major security problem because it will blindly run any executable that is the same name as the expected output (if an executable of the same name is found)
    # --------------------------------------------------- #
    # TODO: Implement a different cache comparison system #
    # --------------------------------------------------- #
    if COMPARE_CACHE == 0:
        return 1

    # Cache Comparison
    let file_location: tuple = (file_path <?> stripDir(file_path))
    var cmpProjectID: bool = false
    try:
        let cache: seq[string] = readFile(gravityDirectory / file_location.Pattern & ".script").splitLines()
        var out_file: string = ""
        var fsize: int = 0
        for position, item in cache.pairs():
            if position < cacheData.len and cacheData[position] != item:
                return 1
            elif position < cacheData.len and cacheData[position].contains("(Definition: Name =>"):
                out_file = (cacheData[position] <?> vm_file_out).Pattern
            elif position < cacheData.len and cacheData[position].contains("(Definition: ProjectIdentifier =>"):
                if cache[position] == cacheData[position]:
                    cmpProjectID = true

        if fileExists(out_file) and cmpProjectID:
            return 0
        else:
            return 1

    # No Cache File
    except IOError:
        return 1
