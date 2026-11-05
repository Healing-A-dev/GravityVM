import strutils
import tables

# Instruction base36 opcodes requiring 3-address normalization
const MATH_OPCODES = [
  "05", # ADD
  "06", # SUB
  "07", # MUL
  "08", # DIV
  "43", # IADD
  "44", # ISUB
  "45", # IMUL
  "46", # IDIV
  "0M", # LT
  "0N", # GT
  "0D", # CMP
]

proc normalizeOperand(operand: string): string =
  case operand
  of "sra", "%rax": return "r0"
  of "[sra]", "[%rax]": return "[r0]"
  of "%rdi": return "r1"
  of "%rsi": return "r2"
  of "%rdx": return "r3"
  of "%rcx": return "r4"
  of "%r8": return "r5"
  of "%r9": return "r6"
  of "%r10": return "r7"
  of "%r11": return "r8"
  of "%rbx": return "r9"
  of "%r12": return "r10"
  of "%r13": return "r11"
  of "%r14": return "r12"
  of "%r15": return "r13"
  else: return operand

proc liftV1ToRegisters*(instructions: seq[string]): seq[string] =
  var res = newSeq[string](instructions.len)

  # Copy and normalize registers / 3-address destinations
  var i = 0
  while i < instructions.len:
    let op = instructions[i]
    var a0 = instructions[i + 1]
    var a1 = instructions[i + 2]
    var a2 = instructions[i + 3]

    # Normalize accumulator names to r0
    a0 = normalizeOperand(a0)
    a1 = normalizeOperand(a1)
    a2 = normalizeOperand(a2)

    # If math opcode lacks destination, set destination to r0
    if op in MATH_OPCODES:
      if a2 == "" or a2 == "00" or a2 == "0" or a2 == "sra":
        a2 = "r0"

    res[i] = op
    res[i + 1] = a0
    res[i + 2] = a1
    res[i + 3] = a2
    i.inc(4)

  # Peephole pass: optimize redundant stack temporaries
  # If MOV -N(%rbp), r0 / %rax followed by PUSH -N(%rbp), replace with PUSH r0
  i = 0
  while i < res.len - 4:
    let op0 = res[i]
    let a0 = res[i + 1] # dest
    let a1 = res[i + 2] # src

    let op1 = res[i + 4]
    let b0 = res[i + 5]

    if op0 == "40" and (a1 == "r0" or a1 == "%rax") and a0.contains("(%rbp)"):
      if op1 == "1A" and (b0 == a0 or b0 == a0.replace("$", "")):
        # Replace PUSH slot with PUSH r0
        res[i + 5] = "r0"

    i.inc(4)

  return res

