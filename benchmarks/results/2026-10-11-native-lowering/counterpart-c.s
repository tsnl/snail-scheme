	.file	"counterpart.c"
	.text
	.globl	construct                       # -- Begin function construct
	.p2align	4
	.type	construct,@function
construct:                              # @construct
	.cfi_startproc
# %bb.0:
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%r15
	pushq	%r14
	pushq	%rbx
	pushq	%rax
	.cfi_offset %rbx, -40
	.cfi_offset %r14, -32
	.cfi_offset %r15, -24
	movq	%rdx, %rbx
	movq	%rsi, %r14
	movq	%rdi, %r15
	movl	$40, %edi
	callq	native_alloc@PLT
	movq	$7, (%rax)
	movq	$3, 8(%rax)
	movq	%r15, 16(%rax)
	movq	%r14, 24(%rax)
	movq	%rbx, 32(%rax)
	addq	$8, %rsp
	popq	%rbx
	popq	%r14
	popq	%r15
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	xorl	%edi, %edi
	xorl	%edx, %edx
	xorl	%esi, %esi
	retq
.Lfunc_end0:
	.size	construct, .Lfunc_end0-construct
	.cfi_endproc
                                        # -- End function
	.globl	roundtrip                       # -- Begin function roundtrip
	.p2align	4
	.type	roundtrip,@function
roundtrip:                              # @roundtrip
	.cfi_startproc
# %bb.0:
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%r15
	pushq	%r14
	pushq	%rbx
	pushq	%rax
	.cfi_offset %rbx, -40
	.cfi_offset %r14, -32
	.cfi_offset %r15, -24
	movq	%rdx, %rbx
	movq	%rsi, %r14
	movq	%rdi, %r15
	movl	$40, %edi
	callq	native_alloc@PLT
	movq	$7, (%rax)
	movq	$3, 8(%rax)
	movq	%r15, 16(%rax)
	movq	%r14, 24(%rax)
	movq	%rbx, 32(%rax)
	movq	%r14, %rax
	addq	$8, %rsp
	popq	%rbx
	popq	%r14
	popq	%r15
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	xorl	%edi, %edi
	xorl	%edx, %edx
	xorl	%esi, %esi
	retq
.Lfunc_end1:
	.size	roundtrip, .Lfunc_end1-roundtrip
	.cfi_endproc
                                        # -- End function
	.globl	local_roundtrip                 # -- Begin function local_roundtrip
	.p2align	4
	.type	local_roundtrip,@function
local_roundtrip:                        # @local_roundtrip
	.cfi_startproc
# %bb.0:
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	movq	%rsi, %rax
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	xorl	%esi, %esi
	retq
.Lfunc_end2:
	.size	local_roundtrip, .Lfunc_end2-local_roundtrip
	.cfi_endproc
                                        # -- End function
	.ident	"clang version 21.1.8"
	.section	".note.GNU-stack","",@progbits
	.addrsig
