/*
 * Copyright 2012, Alex Smith, alex@alex-smith.me.uk.
 * Distributed under the terms of the MIT License.
 */


#include <asm_defs.h>

#define __x86_64__
#include <arch/x86/descriptors.h>

#include "mmu.h"
#undef __x86_64__


#define GDT_LIMIT 0x800


.code32


/*!	void long_enter_kernel(int currentCPU, uint64 stackTop); */
FUNCTION(long_enter_kernel):
	// Preserve the arguments. We may no longer be able to use the stack once
	// paging is disabled.
	movl	4(%esp), %ebx
	movl	8(%esp), %edi
	movl	12(%esp), %esi

	// Currently running with 32-bit paging tables at an identity mapped
	// address. To switch to 64-bit paging we must first disable 32-bit paging,
	// otherwise loading the new CR3 will fault.
	movl	%cr0, %eax
	andl	$~(1 << 31), %eax
	movl	%eax, %cr0

	// Enable PAE and PGE
	movl	%cr4, %eax
	orl		$(1 << 5) | (1 << 7), %eax
	movl	%eax, %cr4

	// Point CR3 to the kernel's PML4.
	movl	gLongPhysicalPML4, %eax
	movl	%eax, %cr3

	// Enable long mode by setting EFER.LME.
	movl	$0xc0000080, %ecx
	rdmsr
	orl		$(1 << 8), %eax
	wrmsr

	// Re-enable paging, which will put us in compatibility mode as we are
	// currently in a 32-bit code segment.
	movl	%cr0, %ecx
	orl		$(1 << 31), %ecx
	movl	%ecx, %cr0

	// Load 64-bit enabled GDT
	lgdtl	long_gdtr

	// Jump into the 64-bit code segment.
	ljmp	$KERNEL_CODE_SELECTOR, $.Llmode
.align 8
.code64
.Llmode:
	// Set data segments.
	mov		$KERNEL_DATA_SELECTOR, %ax
	mov		%ax, %ss
	xor		%ax, %ax
	mov		%ax, %ds
	mov		%ax, %es
	mov		%ax, %fs
	mov		%ax, %gs

	// Set the stack pointer.
	movl	%edi, %esp
	shl		$32, %rsi
	orq		%rsi, %rsp

	// Clear the stack frame/RFLAGS.
	xorq	%rbp, %rbp
	push	$0
	popf

	// Get arguments and call the kernel entry point.
	leaq	gKernelArgs(%rip), %rdi
	movl	%ebx, %esi
	movq	gLongKernelEntry(%rip), %rax
	call	*%rax

	
.data


long_gdtr:
	.word	BOOT_GDT_SEGMENT_COUNT * 8 - 1
SYMBOL(gLongGDT):
	.long	0

SYMBOL(gLongPhysicalPML4):
	.long	0

SYMBOL(gLongKernelEntry):
	.quad	0
