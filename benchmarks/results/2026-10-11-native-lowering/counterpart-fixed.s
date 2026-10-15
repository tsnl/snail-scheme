	.file	"counterpart-fixed.ll"
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
	pushq	%rbx
	.cfi_def_cfa_offset 32
	.cfi_offset %rbx, -32
	.cfi_offset %r14, -24
	.cfi_offset %r15, -16
	movq	%rdx, %rbx
	movq	%rsi, %r14
	movq	%rdi, %r15
	movl	$40, %edi
	callq	native_alloc@PLT
	testq	%rax, %rax
	je	.LBB0_2
# %bb.1:                                # %f.0.exit
	movq	$7, (%rax)
	movq	$3, 8(%rax)
	movq	%r15, 16(%rax)
	movq	%r14, 24(%rax)
	movq	%rbx, 32(%rax)
	popq	%rbx
	.cfi_def_cfa_offset 24
	popq	%r14
	.cfi_def_cfa_offset 16
	popq	%r15
	.cfi_def_cfa_offset 8
	retq
.LBB0_2:                                # %trap11.i
	.cfi_def_cfa_offset 32
	callq	native_trap@PLT
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
	pushq	%rbx
	.cfi_def_cfa_offset 32
	.cfi_offset %rbx, -32
	.cfi_offset %r14, -24
	.cfi_offset %r15, -16
	movq	%rdx, %rbx
	movq	%rsi, %r14
	movq	%rdi, %r15
	movl	$40, %edi
	callq	native_alloc@PLT
	testq	%rax, %rax
	je	.LBB1_2
# %bb.1:                                # %f.1.exit
	movq	$7, (%rax)
	movq	$3, 8(%rax)
	movq	%r15, 16(%rax)
	movq	%r14, 24(%rax)
	movq	%rbx, 32(%rax)
	movq	%rax, %rdi
	movl	$1, %esi
	callq	native_array_slot@PLT
	movq	(%rax), %rax
	popq	%rbx
	.cfi_def_cfa_offset 24
	popq	%r14
	.cfi_def_cfa_offset 16
	popq	%r15
	.cfi_def_cfa_offset 8
	retq
.LBB1_2:                                # %trap11.i
	.cfi_def_cfa_offset 32
	callq	native_trap@PLT
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
