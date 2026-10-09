import std/[os, strutils, times, algorithm]
import cli
import ../codegen/targets/target

# --- FIPS 180-4 SHA-256 Implementation ---
type
  Sha256Context = object
    state: array[8, uint32]
    count: uint64
    buffer: array[64, uint8]

const K256: array[64, uint32] = [
  0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32,
  0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
  0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32,
  0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
  0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32,
  0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
  0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32,
  0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
  0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32,
  0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
  0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32,
  0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
  0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32,
  0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
  0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
  0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32
]

template rotr(x: uint32, n: static int): uint32 =
  (x shr n) or (x shl (32 - n))

template ch(x, y, z: uint32): uint32 =
  (x and y) xor ((not x) and z)

template maj(x, y, z: uint32): uint32 =
  (x and y) xor (x and z) xor (y and z)

template sigma0(x: uint32): uint32 =
  rotr(x, 2) xor rotr(x, 13) xor rotr(x, 22)

template sigma1(x: uint32): uint32 =
  rotr(x, 6) xor rotr(x, 11) xor rotr(x, 25)

template gamma0(x: uint32): uint32 =
  rotr(x, 7) xor rotr(x, 18) xor (x shr 3)

template gamma1(x: uint32): uint32 =
  rotr(x, 17) xor rotr(x, 19) xor (x shr 10)

proc initSha256*(): Sha256Context =
  result.state = [
    0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
    0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32
  ]
  result.count = 0

proc transform(ctx: var Sha256Context, data: ptr UncheckedArray[uint8]) =
  var w: array[64, uint32]
  for i in 0 ..< 16:
    w[i] = (uint32(data[i * 4]) shl 24) or
           (uint32(data[i * 4 + 1]) shl 16) or
           (uint32(data[i * 4 + 2]) shl 8) or
           (uint32(data[i * 4 + 3]))
  for i in 16 ..< 64:
    w[i] = gamma1(w[i - 2]) + w[i - 7] + gamma0(w[i - 15]) + w[i - 16]

  var a = ctx.state[0]
  var b = ctx.state[1]
  var c = ctx.state[2]
  var d = ctx.state[3]
  var e = ctx.state[4]
  var f = ctx.state[5]
  var g = ctx.state[6]
  var h = ctx.state[7]

  for i in 0 ..< 64:
    let t1 = h + sigma1(e) + ch(e, f, g) + K256[i] + w[i]
    let t2 = sigma0(a) + maj(a, b, c)
    h = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2

  ctx.state[0] += a
  ctx.state[1] += b
  ctx.state[2] += c
  ctx.state[3] += d
  ctx.state[4] += e
  ctx.state[5] += f
  ctx.state[6] += g
  ctx.state[7] += h

proc update*(ctx: var Sha256Context, data: string) =
  var index = int((ctx.count shr 3) and 63)
  ctx.count += uint64(data.len) shl 3
  let partLen = 64 - index
  var i = 0

  if data.len >= partLen:
    if partLen > 0 and index > 0:
      copyMem(addr ctx.buffer[index], unsafeAddr data[0], partLen)
      ctx.transform(cast[ptr UncheckedArray[uint8]](addr ctx.buffer[0]))
      i = partLen
      index = 0
    while i + 63 < data.len:
      ctx.transform(cast[ptr UncheckedArray[uint8]](unsafeAddr data[i]))
      i += 64

  if i < data.len:
    copyMem(addr ctx.buffer[index], unsafeAddr data[i], data.len - i)

proc finish*(ctx: var Sha256Context): string =
  let index = int((ctx.count shr 3) and 63)
  let padLen = if index < 56: 56 - index else: 120 - index
  let totalBits = ctx.count

  var padStr = newString(padLen)
  padStr[0] = chr(0x80)
  for k in 1 ..< padLen: padStr[k] = chr(0)
  ctx.update(padStr)

  var bitsStr = newString(8)
  for k in 0 ..< 8:
    bitsStr[k] = chr(uint8((totalBits shr ((7 - k) * 8)) and 0xFF))
  ctx.update(bitsStr)

  result = ""
  for s in ctx.state:
    result.add(s.toHex(8).toLowerAscii())

proc sha256*(data: string): string =
  var ctx = initSha256()
  ctx.update(data)
  return ctx.finish()

proc sha256File*(path: string): string =
  if not fileExists(path): return ""
  try:
    let content = readFile(path)
    return sha256(content)
  except:
    return ""

# --- Cache Management ---
const homeDirectory: string = getEnv("HOME")
const gravityDirectory*: string = homeDirectory / ".cache" / "GravityVM"
const entriesDirectory*: string = gravityDirectory / "entries"

var MAX_ENTRIES*: int = 500
var COMPARE_CACHE*: int = 1
var currentCacheKey*: string = ""

proc ensureCacheDirs(): void =
  try:
    if not dirExists(gravityDirectory):
      createDir(gravityDirectory)
    if not dirExists(entriesDirectory):
      createDir(entriesDirectory)
  except:
    discard

proc loadCacheConfig*(): void =
  ensureCacheDirs()
  let configFile = gravityDirectory / ".config"
  if not fileExists(configFile):
    try:
      let f = open(configFile, fmWrite)
      f.writeLine("MAX_ENTRIES = 500")
      f.writeLine("COMPARE_CACHE = 1")
      f.writeLine("MAX_CACHE_MB = 512")
      f.close()
    except:
      discard
    MAX_ENTRIES = 500
    COMPARE_CACHE = 1
    return

  try:
    let lines = readFile(configFile).splitLines()
    for line in lines:
      let trimmed = line.strip()
      if trimmed.startsWith("MAX_ENTRIES"):
        let parts = trimmed.split('=')
        if parts.len == 2:
          MAX_ENTRIES = parseInt(parts[1].strip())
      elif trimmed.startsWith("COMPARE_CACHE"):
        let parts = trimmed.split('=')
        if parts.len == 2:
          COMPARE_CACHE = parseInt(parts[1].strip())
  except:
    MAX_ENTRIES = 500
    COMPARE_CACHE = 1

proc computeCacheKey*(sourceFile: string): string =
  var hasher = initSha256()

  if fileExists(sourceFile):
    hasher.update("SRC:" & sha256File(sourceFile))
  else:
    hasher.update("SRCPATH:" & sourceFile)

  hasher.update("ARCH:" & (if vm_architecture.isNil: hostCPU else: vm_architecture[]))
  hasher.update("TARGET:" & (if vm_target.isNil: hostOS else: vm_target[]))
  hasher.update("BACKEND:" & vm_execTarget)
  hasher.update("OBJECT:" & $vm_generateObjectFile)
  hasher.update("VERSION:" & vm_version)

  for lf in vm_linkerfiles:
    if fileExists(lf):
      try:
        let info = getFileInfo(lf)
        hasher.update("LINKER:" & lf & ":" & $info.size & ":" & $toUnix(info.lastWriteTime))
      except:
        hasher.update("LINKER:" & lf)
    else:
      hasher.update("FLAG:" & lf)

  return hasher.finish()

proc generateData*(fname: string, instructions: seq[string]): int {.discardable.} =
  currentCacheKey = computeCacheKey(fname)
  return 0

proc pruneLruCache(): void =
  try:
    var metaFiles: seq[tuple[path: string, mtime: Time]] = @[]
    for kind, path in walkDir(entriesDirectory):
      if kind == pcFile and path.endsWith(".meta"):
        metaFiles.add((path: path, mtime: getFileInfo(path).lastWriteTime))

    if metaFiles.len > MAX_ENTRIES:
      # Sort oldest first
      metaFiles.sort(proc(a, b: tuple[path: string, mtime: Time]): int =
        if a.mtime < b.mtime: -1
        elif a.mtime > b.mtime: 1
        else: 0
      )
      let toRemove = metaFiles.len - MAX_ENTRIES
      for i in 0 ..< toRemove:
        let metaPath = metaFiles[i].path
        let binPath = metaPath[0..<(metaPath.len - 5)] & ".bin"
        if fileExists(metaPath): removeFile(metaPath)
        if fileExists(binPath): removeFile(binPath)
  except:
    discard

proc resolveOutputArtifact(): string =
  let baseTarget = if vm_file_out != "": vm_file_out else: "out"
  if vm_generateObjectFile:
    if baseTarget.endsWith(".o"): baseTarget else: baseTarget & ".o"
  elif not vm_target.isNil and vm_target[] == "win64":
    if baseTarget.endsWith(".exe"): baseTarget else: baseTarget & ".exe"
  else:
    baseTarget

proc compareCache*(file_path: string): int =
  if COMPARE_CACHE == 0:
    return 1

  if currentCacheKey == "":
    currentCacheKey = computeCacheKey(file_path)

  let metaPath = entriesDirectory / (currentCacheKey & ".meta")
  let binPath = entriesDirectory / (currentCacheKey & ".bin")

  if not fileExists(metaPath) or not fileExists(binPath):
    return 1

  # Check linker files
  for lf in vm_linkerfiles:
    if fileExists(lf):
      try:
        let cachedMeta = readFile(metaPath)
        let info = getFileInfo(lf)
        let expectedTag = "LINKER:" & lf & ":" & $info.size & ":" & $toUnix(info.lastWriteTime)
        if not cachedMeta.contains(expectedTag):
          return 1
      except:
        return 1

  # Check if output file exists and matches
  let outTarget = resolveOutputArtifact()
  try:
    if fileExists(outTarget) and fileExists(binPath):
      if getFileInfo(outTarget).size == getFileInfo(binPath).size:
        return 0

    if fileExists(binPath):
      copyFile(binPath, outTarget)
      setFilePermissions(outTarget, {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})
      return 0
  except:
    return 1

  return 1

proc writeCache*(file_path: string): int {.discardable.} =
  if COMPARE_CACHE == 0:
    return 0

  ensureCacheDirs()
  if currentCacheKey == "":
    currentCacheKey = computeCacheKey(file_path)

  let outTarget = resolveOutputArtifact()
  if not fileExists(outTarget):
    return 0

  let metaPath = entriesDirectory / (currentCacheKey & ".meta")
  let binPath = entriesDirectory / (currentCacheKey & ".bin")

  try:
    copyFile(outTarget, binPath)

    var metaContent = ""
    metaContent.add("KEY=" & currentCacheKey & "\n")
    metaContent.add("SOURCE=" & file_path & "\n")
    metaContent.add("OUTPUT=" & outTarget & "\n")
    metaContent.add("ARCH=" & (if vm_architecture.isNil: hostCPU else: vm_architecture[]) & "\n")
    metaContent.add("TARGET=" & (if vm_target.isNil: hostOS else: vm_target[]) & "\n")
    metaContent.add("BACKEND=" & vm_execTarget & "\n")
    metaContent.add("IS_OBJECT=" & $vm_generateObjectFile & "\n")
    metaContent.add("VERSION=" & vm_version & "\n")
    for lf in vm_linkerfiles:
      if fileExists(lf):
        let info = getFileInfo(lf)
        metaContent.add("LINKER:" & lf & ":" & $info.size & ":" & $toUnix(info.lastWriteTime) & "\n")
      else:
        metaContent.add("FLAG:" & lf & "\n")

    writeFile(metaPath, metaContent)

    pruneLruCache()
  except:
    discard

  return 0

proc cleanCache*(): void =
  ensureCacheDirs()
  try:
    for kind, path in walkDir(entriesDirectory):
      if kind == pcFile:
        removeFile(path)
  except:
    discard
