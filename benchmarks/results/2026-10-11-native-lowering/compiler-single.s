
build/ablation/compiler-baseline:     file format elf64-x86-64


Disassembly of section .text:

00000000001b5f60 <f.62>:
  1b5f60:	50                   	push   %rax
  1b5f61:	48 85 ff             	test   %rdi,%rdi
  1b5f64:	74 2d                	je     1b5f93 <f.62+0x33>
  1b5f66:	40 f6 c7 01          	test   $0x1,%dil
  1b5f6a:	75 20                	jne    1b5f8c <f.62+0x2c>
  1b5f6c:	48 83 3f 46          	cmpq   $0x46,(%rdi)
  1b5f70:	75 1a                	jne    1b5f8c <f.62+0x2c>
  1b5f72:	48 8b 47 08          	mov    0x8(%rdi),%rax
  1b5f76:	48 85 c0             	test   %rax,%rax
  1b5f79:	74 21                	je     1b5f9c <f.62+0x3c>
  1b5f7b:	89 c1                	mov    %eax,%ecx
  1b5f7d:	83 e1 01             	and    $0x1,%ecx
  1b5f80:	75 1a                	jne    1b5f9c <f.62+0x3c>
  1b5f82:	83 78 08 01          	cmpl   $0x1,0x8(%rax)
  1b5f86:	75 19                	jne    1b5fa1 <f.62+0x41>
  1b5f88:	48 8b 78 10          	mov    0x10(%rax),%rdi
  1b5f8c:	48 89 f8             	mov    %rdi,%rax
  1b5f8f:	59                   	pop    %rcx
  1b5f90:	c2 08 00             	ret    $0x8
  1b5f93:	31 ff                	xor    %edi,%edi
  1b5f95:	48 89 f8             	mov    %rdi,%rax
  1b5f98:	59                   	pop    %rcx
  1b5f99:	c2 08 00             	ret    $0x8
  1b5f9c:	e8 df e0 1c 00       	call   384080 <native_trap>
  1b5fa1:	bf 05 00 00 00       	mov    $0x5,%edi
  1b5fa6:	e8 e5 37 fd ff       	call   189790 <f.0>
  1b5fab:	48 83 ec 08          	sub    $0x8,%rsp
  1b5faf:	e8 cc e0 1c 00       	call   384080 <native_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
