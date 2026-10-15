	.file	"counterpart-baseline.ll"
	.text
	.globl	wasm.construct                  # -- Begin function wasm.construct
	.p2align	4
	.type	wasm.construct,@function
wasm.construct:                         # @wasm.construct
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%r15
	.cfi_def_cfa_offset 16
	pushq	%r14
	.cfi_def_cfa_offset 24
	pushq	%r12
	.cfi_def_cfa_offset 32
	pushq	%rbx
	.cfi_def_cfa_offset 40
	pushq	%rax
	.cfi_def_cfa_offset 48
	.cfi_offset %rbx, -40
	.cfi_offset %r12, -32
	.cfi_offset %r14, -24
	.cfi_offset %r15, -16
	movq	%rdx, %rbx
	movq	%rsi, %r14
	movq	%rdi, %r15
	movl	$7, %edi
	movl	$3, %esi
	xorl	%edx, %edx
	callq	native_array_new@PLT
	movq	%rax, %r12
	movq	%rax, %rdi
	xorl	%esi, %esi
	callq	native_array_slot@PLT
	movq	%r15, (%rax)
	movq	%r12, %rdi
	movl	$1, %esi
	callq	native_array_slot@PLT
	movq	%r14, (%rax)
	movq	%r12, %rdi
	movl	$2, %esi
	callq	native_array_slot@PLT
	movq	%rbx, (%rax)
	movq	%r12, %rax
	addq	$8, %rsp
	.cfi_def_cfa_offset 40
	popq	%rbx
	.cfi_def_cfa_offset 32
	popq	%r12
	.cfi_def_cfa_offset 24
	popq	%r14
	.cfi_def_cfa_offset 16
	popq	%r15
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end0:
	.size	wasm.construct, .Lfunc_end0-wasm.construct
	.cfi_endproc
                                        # -- End function
	.globl	wasm.roundtrip                  # -- Begin function wasm.roundtrip
	.p2align	4
	.type	wasm.roundtrip,@function
wasm.roundtrip:                         # @wasm.roundtrip
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%r15
	.cfi_def_cfa_offset 16
	pushq	%r14
	.cfi_def_cfa_offset 24
	pushq	%r12
	.cfi_def_cfa_offset 32
	pushq	%rbx
	.cfi_def_cfa_offset 40
	pushq	%rax
	.cfi_def_cfa_offset 48
	.cfi_offset %rbx, -40
	.cfi_offset %r12, -32
	.cfi_offset %r14, -24
	.cfi_offset %r15, -16
	movq	%rdx, %rbx
	movq	%rsi, %r14
	movq	%rdi, %r15
	movl	$7, %edi
	movl	$3, %esi
	xorl	%edx, %edx
	callq	native_array_new@PLT
	movq	%rax, %r12
	movq	%rax, %rdi
	xorl	%esi, %esi
	callq	native_array_slot@PLT
	movq	%r15, (%rax)
	movq	%r12, %rdi
	movl	$1, %esi
	callq	native_array_slot@PLT
	movq	%r14, (%rax)
	movq	%r12, %rdi
	movl	$2, %esi
	callq	native_array_slot@PLT
	movq	%rbx, (%rax)
	movq	%r12, %rdi
	movl	$1, %esi
	callq	native_array_slot@PLT
	movq	(%rax), %rax
	addq	$8, %rsp
	.cfi_def_cfa_offset 40
	popq	%rbx
	.cfi_def_cfa_offset 32
	popq	%r12
	.cfi_def_cfa_offset 24
	popq	%r14
	.cfi_def_cfa_offset 16
	popq	%r15
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end1:
	.size	wasm.roundtrip, .Lfunc_end1-wasm.roundtrip
	.cfi_endproc
                                        # -- End function
	.globl	native_module_init              # -- Begin function native_module_init
	.p2align	4
	.type	native_module_init,@function
native_module_init:                     # @native_module_init
# %bb.0:                                # %entry
	retq
.Lfunc_end2:
	.size	native_module_init, .Lfunc_end2-native_module_init
                                        # -- End function
	.section	".note.GNU-stack","",@progbits
	.addrsig
