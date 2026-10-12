output of np-generate-code (assembly):

copy-characters: 
entry.10:
0:       cmpi           (imm 2), %ac0
4:       bne            lf.9(617)
dcl.11:
10:      mov            %r8, %rcx
13:      mov            %rcx, %rdx
16:      andi           (imm 7), %rdx
20:      cmpi           (imm 7), %rdx
24:      bne            Llib.8(456)
lt.12:
30:      mov            (disp 1 %rcx), %rdx
34:      andi           (imm 1535), %rdx
41:      cmpi           (imm 478), %rdx
48:      bne            Llib.8(432)
lt.13:
54:      mov            (disp 25 %rcx), %rdx
58:      cmpi           (imm 0), %rdx
62:      beq            Llib.8(418)
lf.14:
68:      lea            (disp 4 %rdx), %rsi
72:      mov            %rsi, (disp 25 %rcx)
76:      mov            (disp 49 %rcx), %rsi
80:      movl           (index 0 %rdx %rsi), %ac0
loop.0:
83:      cmpi           (imm 54), %ac0
87:      beq            lt.7(382)
lf.15:
93:      subi           (imm 1), $trap
98:      beq            lt.6(295)
ej.2:
104:     mov            %ac0, %rdx
107:     andi           (imm 255), %rdx
114:     cmpi           (imm 22), %rdx
118:     bne            Llib.5(204)
lt.16:
124:     mov            %rdi, %rdx
127:     andi           (imm 7), %rdx
131:     cmpi           (imm 7), %rdx
135:     bne            Llib.5(187)
lt.17:
141:     mov            (disp 1 %rdi), %rdx
145:     andi           (imm 1791), %rdx
152:     cmpi           (imm 734), %rdx
159:     bne            Llib.5(163)
lt.18:
165:     mov            (disp 17 %rdi), %rdx
169:     cmpi           (imm 0), %rdx
173:     beq            Llib.5(149)
lf.19:
179:     lea            (disp 4 %rdx), %rsi
183:     mov            %rsi, (disp 17 %rdi)
187:     mov            (disp 33 %rdi), %rsi
191:     movl           %ac0, (index 0 %rdx %rsi)
ej.3:
194:     mov            %rcx, %rdx
197:     andi           (imm 7), %rdx
201:     cmpi           (imm 7), %rdx
205:     bne            Llib.4(50)
lt.20:
207:     mov            (disp 1 %rcx), %rdx
211:     andi           (imm 1535), %rdx
218:     cmpi           (imm 478), %rdx
225:     bne            Llib.4(30)
lt.21:
227:     mov            (disp 25 %rcx), %rdx
231:     cmpi           (imm 0), %rdx
235:     beq            Llib.4(20)
lf.22:
237:     lea            (disp 4 %rdx), %rsi
241:     mov            %rsi, (disp 25 %rcx)
245:     mov            (disp 49 %rcx), %rsi
249:     movl           (index 0 %rdx %rsi), %ac0
252:     bra            loop.0(-174)
Llib.4:
257:     mov            %rcx, %r8
260:     mov            %rcx, (disp 8 %sfp)
264:     mov            %rdi, (disp 16 %sfp)
268:     addi           (imm 24), %sfp
docall.23:
272:     lea            (riprel 32), %rcx
279:     mov            %rcx, (disp 0 %sfp)
283:     movi           (imm 4294967295), %ts
293:     jmp            %ts
295:     relocation:    (x86_64-jump 65 (library-code #(libspec safe-read-char 33825)))
rpl.24:
295:     code-top-link  
303:     mrv pt:        (3 3 error)
311:     subi           (imm 24), %sfp
315:     mov            (disp 8 %sfp), %rcx
319:     mov            (disp 16 %sfp), %rdi
323:     bra            loop.0(-245)
Llib.5:
328:     mov            %ac0, %r8
331:     mov            %rcx, (disp 8 %sfp)
335:     mov            %rdi, (disp 16 %sfp)
339:     addi           (imm 24), %sfp
docall.25:
343:     lea            (riprel 32), %rcx
350:     mov            %rcx, (disp 0 %sfp)
354:     movi           (imm 4294967295), %ts
364:     jmp            %ts
366:     relocation:    (x86_64-jump 65 (library-code #(libspec safe-write-char 34857)))
rpl.26:
366:     code-top-link  
374:     mrv pt:        (3 3 continue)
mrvl.27:
382:     subi           (imm 24), %sfp
386:     mov            (disp 8 %sfp), %rcx
390:     mov            (disp 16 %sfp), %rdi
394:     bra            ej.3(-205)
lt.6:
399:     mov            %rcx, (disp 8 %sfp)
403:     mov            %rdi, (disp 16 %sfp)
407:     mov            %ac0, (disp 24 %sfp)
411:     addi           (imm 32), %sfp
docall.28:
415:     lea            (riprel 32), %rcx
422:     mov            %rcx, (disp 0 %sfp)
426:     movi           (imm 4294967295), %ts
436:     jmp            %ts
438:     relocation:    (x86_64-jump 65 (library-code #(libspec event 32817)))
rpl.29:
438:     code-top-link  
446:     mrv pt:        (7 4 continue)
mrvl.30:
454:     subi           (imm 32), %sfp
458:     mov            (disp 8 %sfp), %rcx
462:     mov            (disp 16 %sfp), %rdi
466:     mov            (disp 24 %sfp), %ac0
470:     bra            ej.2(-371)
lt.7:
475:     movi           (imm 46), %ac0
482:     jmp            (disp 0 %sfp)
Llib.8:
486:     subi           (imm 1), $trap
491:     bne            ej.1(63)
lt.31:
493:     mov            %rcx, (disp 8 %sfp)
497:     mov            %rdi, (disp 16 %sfp)
501:     addi           (imm 24), %sfp
docall.32:
505:     lea            (riprel 32), %rcx
512:     mov            %rcx, (disp 0 %sfp)
516:     movi           (imm 4294967295), %ts
526:     jmp            %ts
528:     relocation:    (x86_64-jump 65 (library-code #(libspec event 32817)))
rpl.33:
528:     code-top-link  
536:     mrv pt:        (3 3 continue)
mrvl.34:
544:     subi           (imm 24), %sfp
548:     mov            (disp 8 %sfp), %rcx
552:     mov            (disp 16 %sfp), %rdi
ej.1:
556:     mov            %rcx, %r8
559:     mov            %rcx, (disp 8 %sfp)
563:     mov            %rdi, (disp 16 %sfp)
567:     addi           (imm 24), %sfp
docall.35:
571:     lea            (riprel 32), %rcx
578:     mov            %rcx, (disp 0 %sfp)
582:     movi           (imm 4294967295), %ts
592:     jmp            %ts
594:     relocation:    (x86_64-jump 65 (library-code #(libspec safe-read-char 33825)))
rpl.36:
594:     code-top-link  
602:     mrv pt:        (3 3 error)
610:     subi           (imm 24), %sfp
614:     mov            (disp 8 %sfp), %rcx
618:     mov            (disp 16 %sfp), %rdi
622:     bra            loop.0(-544)
lf.9:
627:     movi           (imm 4294967295), %ts
637:     jmp            %ts
639:     relocation:    (x86_64-jump 65 (library-code #(libspec doargerr 176)))
639:     <end copy-characters>

dcl.37:
0:       movi           (literal 0 (closure . #($c-func (...) #f (...) #f))), %ac0
10:      jmp            (disp 0 %sfp)
14:      <end>
