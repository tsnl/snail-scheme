
build/ablation/compiler-baseline:     file format elf64-x86-64


Disassembly of section .text:

0000000000384140 <native_array_new>:
  384140:	55                   	push   %rbp
  384141:	48 89 e5             	mov    %rsp,%rbp
  384144:	41 57                	push   %r15
  384146:	41 56                	push   %r14
  384148:	41 55                	push   %r13
  38414a:	41 54                	push   %r12
  38414c:	53                   	push   %rbx
  38414d:	50                   	push   %rax
  38414e:	48 89 d3             	mov    %rdx,%rbx
  384151:	41 89 f6             	mov    %esi,%r14d
  384154:	49 89 ff             	mov    %rdi,%r15
  384157:	41 89 f5             	mov    %esi,%r13d
  38415a:	4a 8d 3c ed 10 00 00 	lea    0x10(,%r13,8),%rdi
  384161:	00 
  384162:	48 8b 0d 6f ac 08 00 	mov    0x8ac6f(%rip),%rcx        # 40edd8 <collection_interval>
  384169:	48 85 c9             	test   %rcx,%rcx
  38416c:	74 36                	je     3841a4 <native_array_new+0x64>
  38416e:	48 8b 05 6b ac 08 00 	mov    0x8ac6b(%rip),%rax        # 40ede0 <allocations>
  384175:	48 ff c0             	inc    %rax
  384178:	48 89 05 61 ac 08 00 	mov    %rax,0x8ac61(%rip)        # 40ede0 <allocations>
  38417f:	48 89 c2             	mov    %rax,%rdx
  384182:	48 09 ca             	or     %rcx,%rdx
  384185:	48 c1 ea 20          	shr    $0x20,%rdx
  384189:	0f 84 e0 00 00 00    	je     38426f <native_array_new+0x12f>
  38418f:	31 d2                	xor    %edx,%edx
  384191:	48 f7 f1             	div    %rcx
  384194:	48 85 d2             	test   %rdx,%rdx
  384197:	75 0b                	jne    3841a4 <native_array_new+0x64>
  384199:	49 89 fc             	mov    %rdi,%r12
  38419c:	e8 6f 04 00 00       	call   384610 <GC_gcollect@plt>
  3841a1:	4c 89 e7             	mov    %r12,%rdi
  3841a4:	e8 77 04 00 00       	call   384620 <GC_malloc@plt>
  3841a9:	49 89 c4             	mov    %rax,%r12
  3841ac:	e8 ff 03 00 00       	call   3845b0 <GC_invoke_finalizers@plt>
  3841b1:	4d 85 e4             	test   %r12,%r12
  3841b4:	0f 84 20 01 00 00    	je     3842da <native_array_new+0x19a>
  3841ba:	41 f6 c4 01          	test   $0x1,%r12b
  3841be:	0f 85 16 01 00 00    	jne    3842da <native_array_new+0x19a>
  3841c4:	4d 89 3c 24          	mov    %r15,(%r12)
  3841c8:	4d 89 6c 24 08       	mov    %r13,0x8(%r12)
  3841cd:	45 85 f6             	test   %r14d,%r14d
  3841d0:	0f 84 ea 00 00 00    	je     3842c0 <native_array_new+0x180>
  3841d6:	41 83 fe 0a          	cmp    $0xa,%r14d
  3841da:	72 20                	jb     3841fc <native_array_new+0xbc>
  3841dc:	49 8d 4d ff          	lea    -0x1(%r13),%rcx
  3841e0:	89 ca                	mov    %ecx,%edx
  3841e2:	f7 d2                	not    %edx
  3841e4:	f7 c2 fe ff ff ff    	test   $0xfffffffe,%edx
  3841ea:	0f 94 c2             	sete   %dl
  3841ed:	48 c1 e9 20          	shr    $0x20,%rcx
  3841f1:	0f 95 c1             	setne  %cl
  3841f4:	08 d1                	or     %dl,%cl
  3841f6:	0f 84 85 00 00 00    	je     384281 <native_array_new+0x141>
  3841fc:	31 c9                	xor    %ecx,%ecx
  3841fe:	4c 89 ee             	mov    %r13,%rsi
  384201:	48 89 ca             	mov    %rcx,%rdx
  384204:	48 83 e6 03          	and    $0x3,%rsi
  384208:	74 15                	je     38421f <native_array_new+0xdf>
  38420a:	48 89 ca             	mov    %rcx,%rdx
  38420d:	0f 1f 00             	nopl   (%rax)
  384210:	8d 7a 02             	lea    0x2(%rdx),%edi
  384213:	49 89 1c fc          	mov    %rbx,(%r12,%rdi,8)
  384217:	48 ff c2             	inc    %rdx
  38421a:	48 ff ce             	dec    %rsi
  38421d:	75 f1                	jne    384210 <native_array_new+0xd0>
  38421f:	4c 29 e9             	sub    %r13,%rcx
  384222:	48 83 f9 fc          	cmp    $0xfffffffffffffffc,%rcx
  384226:	0f 87 94 00 00 00    	ja     3842c0 <native_array_new+0x180>
  38422c:	48 83 c2 02          	add    $0x2,%rdx
  384230:	49 f7 dd             	neg    %r13
  384233:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  38423a:	84 00 00 00 00 00 
  384240:	89 d1                	mov    %edx,%ecx
  384242:	49 89 1c cc          	mov    %rbx,(%r12,%rcx,8)
  384246:	8d 4a 01             	lea    0x1(%rdx),%ecx
  384249:	49 89 1c cc          	mov    %rbx,(%r12,%rcx,8)
  38424d:	8d 4a 02             	lea    0x2(%rdx),%ecx
  384250:	49 89 1c cc          	mov    %rbx,(%r12,%rcx,8)
  384254:	8d 4a 03             	lea    0x3(%rdx),%ecx
  384257:	49 89 1c cc          	mov    %rbx,(%r12,%rcx,8)
  38425b:	4a 8d 0c 2a          	lea    (%rdx,%r13,1),%rcx
  38425f:	48 83 c1 04          	add    $0x4,%rcx
  384263:	48 83 c2 04          	add    $0x4,%rdx
  384267:	48 83 f9 02          	cmp    $0x2,%rcx
  38426b:	75 d3                	jne    384240 <native_array_new+0x100>
  38426d:	eb 51                	jmp    3842c0 <native_array_new+0x180>
  38426f:	31 d2                	xor    %edx,%edx
  384271:	f7 f1                	div    %ecx
  384273:	48 85 d2             	test   %rdx,%rdx
  384276:	0f 85 28 ff ff ff    	jne    3841a4 <native_array_new+0x64>
  38427c:	e9 18 ff ff ff       	jmp    384199 <native_array_new+0x59>
  384281:	44 89 e9             	mov    %r13d,%ecx
  384284:	83 e1 fc             	and    $0xfffffffc,%ecx
  384287:	66 48 0f 6e c3       	movq   %rbx,%xmm0
  38428c:	66 0f 70 c0 44       	pshufd $0x44,%xmm0,%xmm0
  384291:	4a 8d 14 ed 00 00 00 	lea    0x0(,%r13,8),%rdx
  384298:	00 
  384299:	48 83 e2 e0          	and    $0xffffffffffffffe0,%rdx
  38429d:	31 f6                	xor    %esi,%esi
  38429f:	90                   	nop
  3842a0:	f3 41 0f 7f 44 34 10 	movdqu %xmm0,0x10(%r12,%rsi,1)
  3842a7:	f3 41 0f 7f 44 34 20 	movdqu %xmm0,0x20(%r12,%rsi,1)
  3842ae:	48 83 c6 20          	add    $0x20,%rsi
  3842b2:	48 39 f2             	cmp    %rsi,%rdx
  3842b5:	75 e9                	jne    3842a0 <native_array_new+0x160>
  3842b7:	44 39 e9             	cmp    %r13d,%ecx
  3842ba:	0f 85 3e ff ff ff    	jne    3841fe <native_array_new+0xbe>
  3842c0:	4c 89 e0             	mov    %r12,%rax
  3842c3:	48 83 c4 08          	add    $0x8,%rsp
  3842c7:	5b                   	pop    %rbx
  3842c8:	41 5c                	pop    %r12
  3842ca:	41 5d                	pop    %r13
  3842cc:	41 5e                	pop    %r14
  3842ce:	41 5f                	pop    %r15
  3842d0:	5d                   	pop    %rbp
  3842d1:	31 c9                	xor    %ecx,%ecx
  3842d3:	31 ff                	xor    %edi,%edi
  3842d5:	31 d2                	xor    %edx,%edx
  3842d7:	31 f6                	xor    %esi,%esi
  3842d9:	c3                   	ret
  3842da:	e8 a1 fd ff ff       	call   384080 <native_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
