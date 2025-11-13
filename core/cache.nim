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
    

proc generateHash(str: seq[string]): string =
    var total: int = 0 
    var count: int = 0
    var hash: string = ""

    # Byte total of the file
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


proc generateData*(fname: string, instructions: seq[string]): int =
    let instruction_counter: string = $(instructions.len / 4)
    cacheData.add("<Project>")
    cacheData.add("    <Name> " & vm_file_out & " </Name>")
    cacheData.add("    <File> \"" & fname & "\" </File> ")
    cacheData.add("    <Verif> " & generateHash(instructions) & " </Verif>")
    cacheData.add("    <ProjectData>")
    cacheData.add("        <Instructions> " & instruction_counter[0..<instruction_counter.len-2] & " </Instructions>")
    cacheData.add("        <Program> " & instructions.join("") & " </Program>")
    cacheData.add("    </ProjectData>")
    cacheData.add("    <CompilerVersion> \"0.1 Neutron\" </CompilerVersion>")
    cacheData.add("</Project>")
    return 0
    

proc writeCache*(file_path: string): int =
    let file_location: int = (file_path <?> stripDir(file_path)).Region[0]
    var directory: string = file_path[0..(file_location - 1)]

    try:
        let file: File = open("./" & directory & ".g_cache/script.xml", fmWrite) 
        for item in cacheData:
            file.writeLine(item)
        file.close()
    except IOError:
        let status: int = execCmd("mkdir " & directory & ".g_cache/")
        if status != 0:
            return status
        let file: File = open("./" & directory & ".g_cache/script.xml", fmWrite)
        for item in cacheData:
            file.writeLine(item)
        file.close()

    return 0


proc compareCache*(file_path: string): int =
    let file_location: int = (file_path <?> stripDir(file_path)).Region[0]
    var directory: string = file_path[0..(file_location - 1)]   

    try:
        let cache: seq[string] = readFile("./" & directory & ".g_cache/script.xml").splitLines()
        var out_file: string = ""
        for position, item in cache.pairs():
            if position < cacheData.len and cacheData[position] != item:
                return 1
            elif position < cacheData.len and cacheData[position].contains("<Name>"):
                out_file = (cacheData[position] <?> vm_file_out).Pattern
        if fileExists(out_file):
            return 0
        else:
            return 1

    # No Cache File => Skip Comparison
    except IOError:
        return 0
