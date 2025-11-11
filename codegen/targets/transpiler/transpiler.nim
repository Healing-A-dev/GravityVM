import tables


var vm_transpiler* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
