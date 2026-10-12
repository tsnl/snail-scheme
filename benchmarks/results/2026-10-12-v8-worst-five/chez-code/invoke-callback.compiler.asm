output of np-generate-code (assembly):

invoke-callback: 
entry.41:
0:       subi           (imm 1), $trap
5:       beq            lt.40(60)
ej.42:
7:       cmpi           (imm 2), %ac0
11:      bne            lf.39(42)
dcl.43:
13:      mov            %r8, %cp
16:      mov            %rdi, %r8
19:      mov            %cp, %rcx
22:      andi           (imm 7), %rcx
26:      cmpi           (imm 5), %rcx
30:      bne            lf.38(11)
lt.44:
32:      movi           (imm 1), %ac0
39:      jmp            (disp 3 %cp)
lf.38:
43:      movi           (imm 4294967295), %ts
53:      jmp            %ts
55:      relocation:    (x86_64-jump 65 (library-code #(libspec call-error 112)))
lf.39:
55:      movi           (imm 4294967295), %ts
65:      jmp            %ts
67:      relocation:    (x86_64-jump 65 (library-code #(libspec doargerr 176)))
lt.40:
67:      movi           (imm 4294967295), %ts
77:      jmp            %ts
79:      relocation:    (x86_64-jump 65 (library-code #(libspec event-detour 180)))
79:      <end invoke-callback>

dcl.45:
0:       movi           (literal 0 (closure . #($c-func (...) #f (...) #f))), %ac0
10:      jmp            (disp 0 %sfp)
14:      <end>
