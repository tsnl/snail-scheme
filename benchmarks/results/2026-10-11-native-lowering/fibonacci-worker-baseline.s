
build/ablation/fibonacci-baseline:     file format elf64-x86-64


Disassembly of section .text:

000000000009dec0 <f.589>:
   9dec0:	55                   	push   %rbp
   9dec1:	41 56                	push   %r14
   9dec3:	53                   	push   %rbx
   9dec4:	48 83 ec 10          	sub    $0x10,%rsp
   9dec8:	89 fb                	mov    %edi,%ebx
   9deca:	83 ff 01             	cmp    $0x1,%edi
   9decd:	7f 17                	jg     9dee6 <f.589+0x26>
   9decf:	01 f3                	add    %esi,%ebx
   9ded1:	71 3b                	jno    9df0e <f.589+0x4e>
   9ded3:	bf 08 00 00 00       	mov    $0x8,%edi
   9ded8:	e8 d3 f5 fe ff       	call   8d4b0 <f.0>
   9dedd:	48 83 ec 08          	sub    $0x8,%rsp
   9dee1:	e8 4a 37 01 00       	call   b1630 <native_trap>
   9dee6:	8d 7b ff             	lea    -0x1(%rbx),%edi
   9dee9:	89 f5                	mov    %esi,%ebp
   9deeb:	e8 d0 ff ff ff       	call   9dec0 <f.589>
   9def0:	48 83 ec 08          	sub    $0x8,%rsp
   9def4:	41 89 c6             	mov    %eax,%r14d
   9def7:	83 c3 fe             	add    $0xfffffffe,%ebx
   9defa:	89 df                	mov    %ebx,%edi
   9defc:	89 ee                	mov    %ebp,%esi
   9defe:	e8 bd ff ff ff       	call   9dec0 <f.589>
   9df03:	48 83 ec 08          	sub    $0x8,%rsp
   9df07:	89 c3                	mov    %eax,%ebx
   9df09:	44 01 f3             	add    %r14d,%ebx
   9df0c:	70 c5                	jo     9ded3 <f.589+0x13>
   9df0e:	89 d8                	mov    %ebx,%eax
   9df10:	48 83 c4 10          	add    $0x10,%rsp
   9df14:	5b                   	pop    %rbx
   9df15:	41 5e                	pop    %r14
   9df17:	5d                   	pop    %rbp
   9df18:	c2 08 00             	ret    $0x8

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
