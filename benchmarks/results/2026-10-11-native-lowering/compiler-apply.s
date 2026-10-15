
build/ablation/compiler-baseline:     file format elf64-x86-64


Disassembly of section .text:

000000000024f780 <f.65>:
  24f780:	50                   	push   %rax
  24f781:	48 85 ff             	test   %rdi,%rdi
  24f784:	74 21                	je     24f7a7 <f.65+0x27>
  24f786:	89 f8                	mov    %edi,%eax
  24f788:	83 e0 01             	and    $0x1,%eax
  24f78b:	75 1a                	jne    24f7a7 <f.65+0x27>
  24f78d:	48 83 3f 1e          	cmpq   $0x1e,(%rdi)
  24f791:	75 14                	jne    24f7a7 <f.65+0x27>
  24f793:	48 8b 47 08          	mov    0x8(%rdi),%rax
  24f797:	48 85 c0             	test   %rax,%rax
  24f79a:	74 0b                	je     24f7a7 <f.65+0x27>
  24f79c:	48 8b 7f 10          	mov    0x10(%rdi),%rdi
  24f7a0:	48 8b 40 08          	mov    0x8(%rax),%rax
  24f7a4:	59                   	pop    %rcx
  24f7a5:	ff e0                	jmp    *%rax
  24f7a7:	e8 d4 48 13 00       	call   384080 <native_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
