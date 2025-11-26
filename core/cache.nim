import strutils
import cli
import pattern
import osproc
import os

var cacheData: seq[string] = @[]

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
    return (Count: files.len, Files: files)


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
    let instruction_counter: string = $(instructions.len / 4)
    cacheData.add("(Start: Project")
    cacheData.add("    (Definition: Name => " & vm_file_out & ")")
    cacheData.add("    (Definition: File => \"" & fname & "\")")
    cacheData.add("    (Definition: Identifier => " & generateHash(instructions) & ")")
    cacheData.add("    (Class: ProjectData => (")
    cacheData.add("        (Definition: Instructions => " & instruction_counter[0..<instruction_counter.len-2] & ")")
    cacheData.add("        (Definition: Program => " & instructions.join("") & ")")
    cacheData.add("        (Definition: Target => " & vm_execTarget & ")")
    cacheData.add("    ))")
    cacheData.add("    (Definition: CompilerVersion => \"" & vm_version & "\")")
    cacheData.add("End: Project)")
    return 0


proc writeCache*(file_path: string): int {.discardable.} =
    let file_location: tuple = (file_path <?> stripDir(file_path))
    var directory: string = file_path[0..(file_location.Region[0] - 1)]
    let cache_index: tuple = indexCache(directory & ".g_cache")

    if cache_index.Count + 1 == 2:
        for file in cache_index.Files:
            removeFile(file)

    try:
        let file: File = open("./" & directory & ".g_cache/" & file_location.Pattern & ".script", fmWrite)
        for item in cacheData:
            file.writeLine(item)
        file.close()
    except IOError:
        let status: int = execCmd("mkdir " & directory & ".g_cache/")
        if status != 0:
            return status
        let file: File = open("./" & directory & ".g_cache/" & file_location.Pattern & ".script", fmWrite)
        for item in cacheData:
            file.writeLine(item)
        file.close()

    return 0


proc compareCache*(file_path: string): int =
    let file_location: tuple = (file_path <?> stripDir(file_path))
    var directory: string = file_path[0..(file_location.Region[0] - 1)]
    try:
        let cache: seq[string] = readFile("./" & directory & ".g_cache/" & file_location.Pattern & ".script").splitLines()
        var out_file: string = ""
        for position, item in cache.pairs():
            if position < cacheData.len and cacheData[position] != item:
                return 1
            elif position < cacheData.len and cacheData[position].contains("(Definition: Name =>"):
                out_file = (cacheData[position] <?> vm_file_out).Pattern

        if fileExists(out_file):
            return 0
        else:
            return 1

    # No Cache File
    except IOError:
        return 1
