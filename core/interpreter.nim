import strutils
import tables
import math

type
  VmState* = ref object
    registers*: array[0..15, int64]
    globalPool*: Table[string, int64]
    localPool*: Table[string, int64]
    bufferPool*: Table[string, int64]
    stringTable*: Table[string, string]
    stringPtrs*: Table[string, int64]
    heapMaps*: Table[int64, Table[int64, int64]]
    heapArrays*: Table[int64, seq[int64]]
    nextHeapId*: int64
    labels*: Table[string, int]
    callStack*: seq[tuple[returnIp: int, frameIdx: int, destReg: string]]
    frameStack*: seq[Table[string, int64]]
    argStack*: seq[int64]
    argFrameBases*: seq[int]
    argFrameCounts*: seq[int]
    currentLabel*: string
    mainInvoked*: bool
    exitCode*: int

proc newVmState*(): VmState =
  VmState(
    registers: [0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64, 0'i64],
    globalPool: initTable[string, int64](),
    localPool: initTable[string, int64](),
    bufferPool: initTable[string, int64](),
    stringTable: initTable[string, string](),
    stringPtrs: initTable[string, int64](),
    heapMaps: initTable[int64, Table[int64, int64]](),
    heapArrays: initTable[int64, seq[int64]](),
    nextHeapId: 1000'i64,
    labels: initTable[string, int](),
    callStack: @[],
    frameStack: @[initTable[string, int64]()],
    argStack: @[],
    argFrameBases: @[0],
    argFrameCounts: @[0],
    currentLabel: "",
    mainInvoked: false,
    exitCode: 0
  )

proc tag(x: int64): int64 {.inline.} =
  (x * 2'i64) + 1'i64

proc untag(x: int64): int64 {.inline.} =
  x shr 1

proc allocHeapId*(state: VmState): int64 {.inline.} =
  state.nextHeapId += 16'i64
  return state.nextHeapId

proc currentFrame(state: VmState): var Table[string, int64] {.inline.} =
  if state.frameStack.len == 0:
    state.frameStack.add(initTable[string, int64]())
  state.frameStack[^1]

proc getRegisterIndex(name: string): int =
  case name
  of "r0", "sra", "%rax": return 0
  of "r1", "%rdi": return 1
  of "r2", "%rsi": return 2
  of "r3", "%rdx": return 3
  of "r4", "%rcx", "src": return 4
  of "r5", "%r8": return 5
  of "r6", "%r9": return 6
  of "r7", "%r10": return 7
  of "r8", "%r11": return 8
  of "r9", "%rbx", "srb": return 9
  of "r10", "%r12", "srd", "sre": return 10
  of "r11", "%r13": return 11
  of "r12", "%r14": return 12
  of "r13", "%r15": return 13
  of "r14": return 14
  of "r15": return 15
  else: return -1

proc resolveVal*(arg: string, state: VmState): int64 =
  if arg == "" or arg == "00" or arg == "0":
    return 0'i64

  var clean = arg.replace("!", "")
  if clean.startsWith("[") and clean.endsWith("]"):
    clean = clean[1..^2]

  let regIdx = getRegisterIndex(clean)
  if regIdx >= 0:
    return state.registers[regIdx]

  # Frame slot $-8(%rbp)
  if clean.contains("(%rbp)"):
    let key = clean.replace("$", "")
    return state.currentFrame().getOrDefault(key, 0'i64)

  # Global pool @01..
  if clean.startsWith("@"):
    return state.globalPool.getOrDefault(clean[1..^1], 0'i64)

  # Local pool $01..
  if clean.startsWith("$"):
    let inner = clean[1..^1]
    if inner.startsWith("str_"):
      if state.stringTable.hasKey(inner):
        if not state.stringPtrs.hasKey(inner):
          let id = allocHeapId(state)
          state.stringPtrs[inner] = id
          state.stringTable["heap_" & $id] = state.stringTable[inner]
        return state.stringPtrs[inner]
      return 0'i64
    try:
      return parseBiggestInt(inner)
    except ValueError:
      return state.localPool.getOrDefault(inner, 0'i64)

  # Buffer pool %01..
  if clean.startsWith("%"):
    return state.bufferPool.getOrDefault(clean[1..^1], 0'i64)

  # Direct integer
  try:
    return parseBiggestInt(clean)
  except ValueError:
    if state.stringTable.hasKey(clean):
      if not state.stringPtrs.hasKey(clean):
        let id = allocHeapId(state)
        state.stringPtrs[clean] = id
        state.stringTable["heap_" & $id] = state.stringTable[clean]
      return state.stringPtrs[clean]
    return 0'i64

proc storeVal*(dest: string, val: int64, state: VmState) =
  if dest == "" or dest == "00" or dest == "0":
    state.registers[0] = val
    return

  var clean = dest.replace("!", "")
  if clean.startsWith("[") and clean.endsWith("]"):
    clean = clean[1..^2]

  let regIdx = getRegisterIndex(clean)
  if regIdx >= 0:
    state.registers[regIdx] = val
    return

  # Frame slot $-8(%rbp)
  if clean.contains("(%rbp)"):
    let key = clean.replace("$", "")
    state.currentFrame()[key] = val
    return

  # Global pool @01..
  if clean.startsWith("@"):
    state.globalPool[clean[1..^1]] = val
    return

  # Local pool $01..
  if clean.startsWith("$"):
    state.localPool[clean[1..^1]] = val
    return

  # Buffer pool %01..
  if clean.startsWith("%"):
    state.bufferPool[clean[1..^1]] = val
    return

  state.registers[0] = val

proc parseHexStr(hex: string): string =
  var res = ""
  var i = 0
  while i < hex.len - 1:
    try:
      let b = parseHexInt(hex[i..i+1])
      res.add(chr(b))
    except: discard
    i.inc(2)
  return res

proc getStrContent(val: int64, state: VmState): string =
  if state.stringTable.hasKey("heap_" & $val):
    return state.stringTable["heap_" & $val]
  elif (val and 1'i64) == 1'i64:
    return $(untag(val))
  else:
    return $val

proc callBuiltinRuntime(name: string, state: VmState): bool =
  case name
  of "runtime_add":
    let a = state.registers[1]
    let b = state.registers[2]
    state.registers[0] = tag(untag(a) + untag(b))
    return true
  of "runtime_sub":
    let a = state.registers[1]
    let b = state.registers[2]
    state.registers[0] = tag(untag(a) - untag(b))
    return true
  of "runtime_mul":
    let a = state.registers[1]
    let b = state.registers[2]
    state.registers[0] = tag(untag(a) * untag(b))
    return true
  of "runtime_div":
    let a = state.registers[1]
    let b = state.registers[2]
    let d = untag(b)
    state.registers[0] = if d != 0: tag(untag(a) div d) else: tag(0)
    return true
  of "runtime_mod":
    let a = state.registers[1]
    let b = state.registers[2]
    let d = untag(b)
    state.registers[0] = if d != 0: tag(untag(a) mod d) else: tag(0)
    return true
  of "runtime_lt":
    let a = state.registers[1]
    let b = state.registers[2]
    state.registers[0] = if untag(a) < untag(b): 3'i64 else: 1'i64
    return true
  of "runtime_gt":
    let a = state.registers[1]
    let b = state.registers[2]
    state.registers[0] = if untag(a) > untag(b): 3'i64 else: 1'i64
    return true
  of "runtime_le":
    let a = state.registers[1]
    let b = state.registers[2]
    state.registers[0] = if untag(a) <= untag(b): 3'i64 else: 1'i64
    return true
  of "runtime_ge":
    let a = state.registers[1]
    let b = state.registers[2]
    state.registers[0] = if untag(a) >= untag(b): 3'i64 else: 1'i64
    return true
  of "runtime_eq":
    let a = state.registers[1]
    let b = state.registers[2]
    let isStrA = state.stringTable.hasKey("heap_" & $a)
    let isStrB = state.stringTable.hasKey("heap_" & $b)
    if isStrA and isStrB:
      let strA = state.stringTable["heap_" & $a]
      let strB = state.stringTable["heap_" & $b]
      state.registers[0] = if strA == strB: 3'i64 else: 1'i64
    else:
      state.registers[0] = if a == b: 3'i64 else: 1'i64
    return true
  of "runtime_neq":
    let a = state.registers[1]
    let b = state.registers[2]
    let isStrA = state.stringTable.hasKey("heap_" & $a)
    let isStrB = state.stringTable.hasKey("heap_" & $b)
    if isStrA and isStrB:
      let strA = state.stringTable["heap_" & $a]
      let strB = state.stringTable["heap_" & $b]
      state.registers[0] = if strA != strB: 3'i64 else: 1'i64
    else:
      state.registers[0] = if a != b: 3'i64 else: 1'i64
    return true
  of "runtime_and":
    let a = state.registers[1] == 3'i64
    let b = state.registers[2] == 3'i64
    state.registers[0] = if a and b: 3'i64 else: 1'i64
    return true
  of "runtime_or":
    let a = state.registers[1] == 3'i64
    let b = state.registers[2] == 3'i64
    state.registers[0] = if a or b: 3'i64 else: 1'i64
    return true
  of "runtime_auto_unwrap":
    let val = state.registers[1]
    if (val and 1'i64) == 1'i64:
      state.registers[0] = val
    else:
      let arrId = val and (not 7'i64)
      if state.heapArrays.hasKey(arrId):
        let arr = state.heapArrays[arrId]
        if arr.len > 0:
          let statusVal = arr[0]
          var statusStr = ""
          if state.stringTable.hasKey("heap_" & $statusVal):
            statusStr = state.stringTable["heap_" & $statusVal]
          if statusStr == "ok" and arr.len > 1:
            state.registers[0] = arr[1]
          elif statusStr == "err":
            let errMsg = if arr.len > 1: getStrContent(arr[1], state) else: "Runtime error"
            echo "Newton error: ", errMsg
            state.registers[0] = 1'i64
          else:
            state.registers[0] = val
        else:
          state.registers[0] = val
      else:
        state.registers[0] = val
    return true
  of "new_array", "alloc_flat_array":
    let id = allocHeapId(state)
    state.heapArrays[id] = @[]
    state.registers[0] = id or 4'i64
    return true
  of "collection_set":
    let arrId = state.registers[1] and (not 7'i64)
    let idx = untag(state.registers[2])
    let val = state.registers[3]
    if state.heapArrays.hasKey(arrId):
      if idx >= state.heapArrays[arrId].len:
        state.heapArrays[arrId].setLen(int(idx + 1))
      state.heapArrays[arrId][int(idx)] = val
    state.registers[0] = 0'i64
    return true
  of "collection_get":
    let arrId = state.registers[1] and (not 7'i64)
    let idx = untag(state.registers[2])
    if state.heapArrays.hasKey(arrId) and idx >= 0 and idx < state.heapArrays[arrId].len:
      state.registers[0] = state.heapArrays[arrId][int(idx)]
    elif state.stringTable.hasKey("heap_" & $state.registers[1]):
      let s = state.stringTable["heap_" & $state.registers[1]]
      if idx >= 0 and idx < s.len:
        state.registers[0] = tag(int64(ord(s[int(idx)])))
      else:
        state.registers[0] = 1'i64
    else:
      state.registers[0] = 1'i64
    return true
  of "collection_get_key":
    let id = state.registers[1] and (not 7'i64)
    let keyIdx = untag(state.registers[2])
    if state.heapMaps.hasKey(id):
      var i = 0
      var found = false
      for k in state.heapMaps[id].keys():
        if i == int(keyIdx):
          state.registers[0] = k
          found = true
          break
        i.inc()
      if not found:
        state.registers[0] = 1'i64
    else:
      state.registers[0] = state.registers[2]
    return true
  of "newton_inc":
    state.registers[0] = state.registers[1] + 2'i64
    return true
  of "newton_to_int":
    state.registers[0] = state.registers[1]
    return true
  of "string_char":
    let c = untag(state.registers[1])
    let id = allocHeapId(state)
    state.stringTable["heap_" & $id] = $(chr(int(c and 0xFF)))
    state.registers[0] = id
    return true
  of "string_ord":
    let strVal = state.registers[1]
    let s = getStrContent(strVal, state)
    state.registers[0] = if s.len > 0: tag(int64(ord(s[0]))) else: 1'i64
    return true
  of "int_to_string":
    let val = untag(state.registers[1])
    let id = allocHeapId(state)
    state.stringTable["heap_" & $id] = $val
    state.registers[0] = id
    return true
  of "print_string":
    let val = state.registers[1]
    if state.stringTable.hasKey("heap_" & $val):
      stdout.write(state.stringTable["heap_" & $val])
    elif (val and 1'i64) == 1'i64:
      stdout.write($(untag(val)))
    else:
      stdout.write($val)
    return true
  of "string_substring":
    let strVal = state.registers[1]
    let startIdx = untag(state.registers[2])
    let lenVal = untag(state.registers[3])
    let s = getStrContent(strVal, state)
    let sub = if startIdx < s.len:
                s[int(startIdx) ..< min(s.len, int(startIdx + lenVal))]
              else: ""
    let id = allocHeapId(state)
    state.stringTable["heap_" & $id] = sub
    state.registers[0] = id
    return true
  of "newton_box_float":
    state.registers[0] = state.registers[1]
    return true
  of "newton_sizeof":
    let id = state.registers[1] and (not 7'i64)
    if state.heapArrays.hasKey(id):
      state.registers[0] = tag(int64(state.heapArrays[id].len))
    elif state.heapMaps.hasKey(id):
      state.registers[0] = tag(int64(state.heapMaps[id].len))
    elif state.stringTable.hasKey("heap_" & $state.registers[1]):
      state.registers[0] = tag(int64(state.stringTable["heap_" & $state.registers[1]].len))
    else:
      state.registers[0] = 1'i64
    return true
  else:
    state.registers[0] = 0'i64
    return false

proc interpretProgram*(instructions: seq[string]): int =
  var state = newVmState()

  # 1. Pre-scan labels and string definitions
  var idx = 0
  while idx < instructions.len:
    let op = instructions[idx]
    let a0 = if idx + 1 < instructions.len: instructions[idx + 1] else: ""
    let a1 = if idx + 2 < instructions.len: instructions[idx + 2] else: ""

    if op == "0J": # LBL
      let clean = a0.replace("[", "").replace("]", "")
      state.labels[clean] = idx
    elif op == "1E": # STR
      let label = a0.replace("$", "")
      var hex = a1.replace("[", "").replace("]", "")
      state.stringTable[label] = parseHexStr(hex)

    idx.inc(4)

  # 2. Find Entrypoint
  var ip = 0
  if state.labels.hasKey("ENTRY"):
    ip = state.labels["ENTRY"]
  elif state.labels.hasKey("L500"):
    ip = state.labels["L500"]

  # 3. Main Virtual Machine Loop
  while ip < instructions.len:
    let op = instructions[ip]
    let a0 = if ip + 1 < instructions.len: instructions[ip + 1] else: ""
    let a1 = if ip + 2 < instructions.len: instructions[ip + 2] else: ""
    let a2 = if ip + 3 < instructions.len: instructions[ip + 3] else: ""

    var nextIp = ip + 4

    case op
    of "00": # NOP
      discard

    of "01": # READ
      let line = stdin.readLine()
      try:
        storeVal(a0, tag(parseBiggestInt(line)), state)
      except:
        storeVal(a0, 1'i64, state)

    of "02": # WRITE
      if a0 == "[srnl]":
        stdout.write("\n")
      elif a0.startsWith("[\"") and a0.endsWith("\"]"):
        stdout.write(a0[2..^3].replace("\\n", "\n").replace("\\r", "\r").replace("\\t", "\t"))
      elif a0.startsWith("$str_") or a0.startsWith("str_"):
        let key = a0.replace("$", "")
        if state.stringTable.hasKey(key):
          stdout.write(state.stringTable[key])
        else:
          stdout.write($resolveVal(a0, state))
      else:
        let val = resolveVal(a0, state)
        if state.stringTable.hasKey("heap_" & $val):
          stdout.write(state.stringTable["heap_" & $val])
        elif (val and 1'i64) == 1'i64:
          stdout.write($(untag(val)))
        else:
          stdout.write($val)

    of "1F": # WRITES
      let key = a0.replace("$", "").replace("[", "").replace("]", "")
      if state.stringTable.hasKey(key):
        stdout.write(state.stringTable[key])
      else:
        let val = resolveVal(a0, state)
        if state.stringTable.hasKey("heap_" & $val):
          stdout.write(state.stringTable["heap_" & $val])
        elif (val and 1'i64) == 1'i64:
          stdout.write($(untag(val)))
        else:
          stdout.write($val)

    of "03": # STORE: STORE dest, src
      let val = resolveVal(a1, state)
      storeVal(a0, val, state)

    of "0A": # COPY: COPY src, dest
      let val = resolveVal(a0, state)
      storeVal(a1, val, state)

    of "40": # MOV: MOV dest, src
      let val = resolveVal(a1, state)
      storeVal(a0, val, state)

    of "0G": # UPD: UPD dest, src
      let val = resolveVal(a1, state)
      storeVal(a0, val, state)

    # --- Tagged Arithmetic ---
    of "05": # ADD
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let res = tag(untag(v1) + untag(v2))
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, res, state)

    of "06": # SUB
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let res = tag(untag(v1) - untag(v2))
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, res, state)

    of "07": # MUL
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let res = tag(untag(v1) * untag(v2))
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, res, state)

    of "08": # DIV
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let d = untag(v2)
      let res = if d != 0: tag(untag(v1) div d) else: tag(0)
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, res, state)

    # --- Raw 64-Bit Integer Arithmetic ---
    of "43": # IADD
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, v1 + v2, state)

    of "44": # ISUB
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, v1 - v2, state)

    of "45": # IMUL
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, v1 * v2, state)

    of "46": # IDIV
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      let res = if v2 != 0: v1 div v2 else: 0'i64
      storeVal(dest, res, state)

    of "0E": # INC
      let cur = resolveVal(a0, state)
      storeVal(a0, cur + 2'i64, state)

    of "0F": # DEC
      let cur = resolveVal(a0, state)
      storeVal(a0, cur - 2'i64, state)

    # --- Comparisons ---
    of "0M": # LT
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let res = if untag(v1) < untag(v2): 3'i64 else: 1'i64
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, res, state)

    of "0N": # GT
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let res = if untag(v1) > untag(v2): 3'i64 else: 1'i64
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, res, state)

    of "0D": # CMP
      let v1 = resolveVal(a0, state)
      let v2 = resolveVal(a1, state)
      let res = if v1 == v2: 3'i64 else: 1'i64
      let dest = if a2 != "" and a2 != "00" and a2 != "0": a2 else: "r0"
      storeVal(dest, res, state)

    # --- Type & String Operators ---
    of "0T": # TYPEOF
      let val = resolveVal(a1, state)
      let typeStr =
        if state.stringTable.hasKey("heap_" & $val): "string"
        elif state.heapArrays.hasKey(val and (not 7'i64)): "list"
        elif state.heapMaps.hasKey(val and (not 7'i64)): "map"
        elif (val and 1'i64) == 1'i64: "number"
        else: "number"
      let id = allocHeapId(state)
      state.stringTable["heap_" & $id] = typeStr
      storeVal(a0, id, state)

    of "0O": # ITS
      let val = untag(resolveVal(a1, state))
      let id = allocHeapId(state)
      state.stringTable["heap_" & $id] = $val
      storeVal(a0, id, state)

    of "2D": # CAT
      let s1 = getStrContent(resolveVal(a1, state), state)
      let s2 = getStrContent(resolveVal(a2, state), state)
      let id = allocHeapId(state)
      state.stringTable["heap_" & $id] = s1 & s2
      storeVal(a0, id, state)

    # --- Branching & Control Flow ---
    of "0J": # LBL
      state.currentLabel = a0.replace("[", "").replace("]", "")

    of "0B": # JMP
      let target = a0.replace("[", "").replace("]", "")
      if state.labels.hasKey(target):
        nextIp = state.labels[target]

    of "0C", "0K": # JNZ
      let target = a0.replace("[", "").replace("]", "")
      let cond = state.registers[0]
      if cond != 0 and cond != 1:
        if state.labels.hasKey(target):
          nextIp = state.labels[target]

    of "0P": # JF
      let cond = resolveVal(a0, state)
      let target = a1.replace("[", "").replace("]", "")
      if cond == 0 or cond == 1:
        if state.labels.hasKey(target):
          nextIp = state.labels[target]

    # --- Functions & Calling Convention ---
    of "1A": # PUSH
      let val = resolveVal(a0, state)
      state.argStack.add(val)

    of "1D": # GETARG
      var argIdx = 0
      try: argIdx = parseInt(a1)
      except: discard
      let base = state.argFrameBases[^1]
      let count = state.argFrameCounts[^1]
      # cdecl / Newton stack convention: last pushed argument is index 0
      let idx = count - 1 - argIdx
      let val = if idx >= 0 and (base + idx) < state.argStack.len:
                  state.argStack[base + idx]
                elif (base + argIdx) < state.argStack.len:
                  state.argStack[base + argIdx]
                else: 0'i64
      storeVal(a0, val, state)

    of "1B": # CALL
      let target = a0.replace("[", "").replace("]", "")
      var argCount = 0
      try: argCount = parseInt(a1)
      except: discard

      if target.startsWith("F_") or target.startsWith("L"):
        if state.labels.hasKey(target):
          state.callStack.add((nextIp, state.frameStack.len - 1, a2))
          state.frameStack.add(initTable[string, int64]())
          let newBase = max(0, state.argStack.len - argCount)
          state.argFrameBases.add(newBase)
          state.argFrameCounts.add(argCount)
          nextIp = state.labels[target]
      else:
        # Runtime procedure call
        discard callBuiltinRuntime(target, state)
        if a2 != "" and a2 != "00" and a2 != "0":
          storeVal(a2, state.registers[0], state)

    of "1C": # RET
      if a0 != "" and a0 != "00" and a0 != "0":
        state.registers[0] = resolveVal(a0, state)

      if state.callStack.len > 0:
        let frame = state.callStack.pop()
        discard state.frameStack.pop()
        let oldBase = state.argFrameBases.pop()
        discard state.argFrameCounts.pop()
        state.argStack.setLen(oldBase)
        if frame.destReg != "" and frame.destReg != "00" and frame.destReg != "0":
          storeVal(frame.destReg, state.registers[0], state)
        nextIp = frame.returnIp
      else:
        if state.mainInvoked:
          return 0
        return int(state.registers[0])

    of "0L": # EXIT
      if not state.mainInvoked and state.labels.hasKey("F_main"):
        state.mainInvoked = true
        state.callStack.add((instructions.len, state.frameStack.len - 1, ""))
        state.frameStack.add(initTable[string, int64]())
        state.argFrameBases.add(state.argStack.len)
        state.argFrameCounts.add(0)
        nextIp = state.labels["F_main"]
      else:
        let code = resolveVal(a0, state)
        return int(untag(code))

    of "41": # NSUB
      # Stack space allocation noop in interpreter
      discard

    of "42": # NADD
      # Stack space release noop in interpreter
      discard

    of "20": # NEWMAP
      let id = allocHeapId(state)
      state.heapMaps[id] = initTable[int64, int64]()
      storeVal(a0, id or 2'i64, state)

    of "21": # MSET
      let mapId = resolveVal(a0, state) and (not 7'i64)
      let k = resolveVal(a1, state)
      let v = resolveVal(a2, state)
      if state.heapMaps.hasKey(mapId):
        state.heapMaps[mapId][k] = v

    of "22": # MGET
      let mapId = resolveVal(a1, state) and (not 7'i64)
      let k = resolveVal(a2, state)
      if state.heapMaps.hasKey(mapId) and state.heapMaps[mapId].hasKey(k):
        storeVal(a0, state.heapMaps[mapId][k], state)
      else:
        storeVal(a0, 1'i64, state)

    of "23": # MLEN
      let id = resolveVal(a1, state) and (not 7'i64)
      if state.heapMaps.hasKey(id):
        storeVal(a0, tag(int64(state.heapMaps[id].len)), state)
      elif state.heapArrays.hasKey(id):
        storeVal(a0, tag(int64(state.heapArrays[id].len)), state)
      else:
        storeVal(a0, 1'i64, state)

    of "30": # NEWARR
      let id = allocHeapId(state)
      state.heapArrays[id] = @[]
      storeVal(a0, id or 4'i64, state)

    of "0H": # MALLOC
      discard

    of "0I": # FREE
      discard

    else:
      discard

    ip = nextIp

  if state.mainInvoked:
    return 0
  return int(state.registers[0])
