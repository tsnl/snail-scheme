
build/ablation/fibonacci-fixed:     file format elf64-x86-64


Disassembly of section .text:

000000000009e140 <f.589>:
   9e140:	55                   	push   %rbp
   9e141:	41 56                	push   %r14
   9e143:	53                   	push   %rbx
   9e144:	48 83 ec 10          	sub    $0x10,%rsp
   9e148:	89 fb                	mov    %edi,%ebx
   9e14a:	83 ff 01             	cmp    $0x1,%edi
   9e14d:	7f 17                	jg     9e166 <f.589+0x26>
   9e14f:	01 f3                	add    %esi,%ebx
   9e151:	71 3b                	jno    9e18e <f.589+0x4e>
   9e153:	bf 08 00 00 00       	mov    $0x8,%edi
   9e158:	e8 93 f3 fe ff       	call   8d4f0 <f.0>
   9e15d:	48 83 ec 08          	sub    $0x8,%rsp
   9e161:	e8 8a 54 01 00       	call   b35f0 <native_trap>
   9e166:	8d 7b ff             	lea    -0x1(%rbx),%edi
   9e169:	89 f5                	mov    %esi,%ebp
   9e16b:	e8 d0 ff ff ff       	call   9e140 <f.589>
   9e170:	48 83 ec 08          	sub    $0x8,%rsp
   9e174:	41 89 c6             	mov    %eax,%r14d
   9e177:	83 c3 fe             	add    $0xfffffffe,%ebx
   9e17a:	89 df                	mov    %ebx,%edi
   9e17c:	89 ee                	mov    %ebp,%esi
   9e17e:	e8 bd ff ff ff       	call   9e140 <f.589>
   9e183:	48 83 ec 08          	sub    $0x8,%rsp
   9e187:	89 c3                	mov    %eax,%ebx
   9e189:	44 01 f3             	add    %r14d,%ebx
   9e18c:	70 c5                	jo     9e153 <f.589+0x13>
   9e18e:	89 d8                	mov    %ebx,%eax
   9e190:	48 83 c4 10          	add    $0x10,%rsp
   9e194:	5b                   	pop    %rbx
   9e195:	41 5e                	pop    %r14
   9e197:	5d                   	pop    %rbp
   9e198:	c2 08 00             	ret    $0x8

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
