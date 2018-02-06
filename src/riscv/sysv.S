/* -----------------------------------------------------------------------
   ffi.c - Copyright (c) 2015 Michael Knyszek <mknyszek@berkeley.edu>
                         2015 Andrew Waterman <waterman@cs.berkeley.edu>
                         2018 Stef O'Rear <sorear2@gmail.com>

   RISC-V Foreign Function Interface

   Permission is hereby granted, free of charge, to any person obtaining
   a copy of this software and associated documentation files (the
   ``Software''), to deal in the Software without restriction, including
   without limitation the rights to use, copy, modify, merge, publish,
   distribute, sublicense, and/or sell copies of the Software, and to
   permit persons to whom the Software is furnished to do so, subject to
   the following conditions:

   The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED ``AS IS'', WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
   DEALINGS IN THE SOFTWARE.
   ----------------------------------------------------------------------- */

#define LIBFFI_ASM
#include <fficonfig.h>
#include <ffi.h>

/* Define aliases so that we can handle all ABIs uniformly */

#if __SIZEOF_POINTER__ == 8
#define PTRS 8
#define LARG ld
#define SARG sd
#else
#define PTRS 4
#define LARG lw
#define SARG sw
#endif

#if __riscv_flen == 64
#define FLTS 8
#define FLARG fld
#define FSARG fsd
#elif __riscv_flen == 32
#define FLTS 4
#define FLARG flw
#define FSARG fsw
#else
#define FLTS 0
#endif

#define fp s0

    .text
    .globl  ffi_call_asm
    .type   ffi_call_asm, @function
    .hidden ffi_call_asm
/*
  struct call_context {
      floatreg fa[8];
      intreg a[8];
      intreg save_fp, save_ra;
  }
  void ffi_call_asm(void *stackargs, struct call_context *regargs,
      void (*fn)(void));
*/
ffi_call_asm:
    .cfi_startproc

    /*
      We are NOT going to set up an ordinary stack frame.  In order to pass
      the stacked args to the called function, we adjust our stack pointer to
      a0, which is in the _caller's_ alloca area.  We establish our own stack
      frame at the end of the call_context.

      This necessarily frees the alloca in the process, indeed gdb unwinding
      will consider the alloca freed as soon as this function is entered,
      since the CFA is considered to be the saved stack pointer.
    */

    .cfi_def_cfa 11, 8*FLTS + 10*PTRS # interim CFA based on a1
    SARG    fp, 8*FLTS + 8*PTRS(a1)
    .cfi_offset 8, -2*PTRS
    SARG    ra, 8*FLTS + 9*PTRS(a1)
    .cfi_offset 1, -1*PTRS

    addi    fp, a1, 8*FLTS + 10*PTRS
    mv      sp, a0
    .cfi_def_cfa 8, 0 # our frame is fully set up

    # Load arguments
    mv      t1, a2

#if FLTS
    FLARG   fa0, -8*FLTS-10*PTRS(fp)
    FLARG   fa1, -7*FLTS-10*PTRS(fp)
    FLARG   fa2, -6*FLTS-10*PTRS(fp)
    FLARG   fa3, -5*FLTS-10*PTRS(fp)
    FLARG   fa4, -4*FLTS-10*PTRS(fp)
    FLARG   fa5, -3*FLTS-10*PTRS(fp)
    FLARG   fa6, -2*FLTS-10*PTRS(fp)
    FLARG   fa7, -1*FLTS-10*PTRS(fp)
#endif

    LARG    a0, -10*PTRS(fp)
    LARG    a1, -9*PTRS(fp)
    LARG    a2, -8*PTRS(fp)
    LARG    a3, -7*PTRS(fp)
    LARG    a4, -6*PTRS(fp)
    LARG    a5, -5*PTRS(fp)
    LARG    a6, -4*PTRS(fp)
    LARG    a7, -3*PTRS(fp)

    /* Call */
    jalr    t1

    /* Save return values - only a0/a1 (fa0/fa1) are used */
#if FLTS
    FSARG   fa0, -8*FLTS-10*PTRS(fp)
    FSARG   fa1, -7*FLTS-10*PTRS(fp)
#endif

    SARG    a0, -10*PTRS(fp)
    SARG    a1, -9*PTRS(fp)

    /* Restore and return */
    addi    sp, fp, -16
    .cfi_def_cfa 2, 16
    LARG    ra, -1*PTRS(fp)
    .cfi_restore 1
    LARG    fp, -2*PTRS(fp)
    .cfi_restore 8
    addi    sp, sp, 16
    .cfi_def_cfa_offset 0
    ret
    .cfi_endproc
    .size   ffi_call_asm, .-ffi_call_asm


/*
  ffi_closure_asm. Expects address of the passed-in ffi_closure in t1.
  void ffi_call_asm(void *stackargs, struct call_context *regargs,
      void (*fn)(void));
*/

#define CLOS_FRAME ((8*FLTS+10*PTRS+15)&~15)
    .globl ffi_closure_asm
    .hidden ffi_closure_asm
    .type ffi_closure_asm, @function
ffi_closure_asm:
    .cfi_startproc

    addi    sp,  sp, -CLOS_FRAME
    .cfi_def_cfa_offset CLOS_FRAME

    /* save RA */
    SARG    ra, CLOS_FRAME-1*PTRS(sp)
    .cfi_offset 1, -1*PTRS

    /* save arguments */
#if FLTS
    FSARG   fa0, CLOS_FRAME-8*FLTS-10*PTRS(sp)
    FSARG   fa1, CLOS_FRAME-7*FLTS-10*PTRS(sp)
    FSARG   fa2, CLOS_FRAME-6*FLTS-10*PTRS(sp)
    FSARG   fa3, CLOS_FRAME-5*FLTS-10*PTRS(sp)
    FSARG   fa4, CLOS_FRAME-4*FLTS-10*PTRS(sp)
    FSARG   fa5, CLOS_FRAME-3*FLTS-10*PTRS(sp)
    FSARG   fa6, CLOS_FRAME-2*FLTS-10*PTRS(sp)
    FSARG   fa7, CLOS_FRAME-1*FLTS-10*PTRS(sp)
#endif

    SARG    a0, CLOS_FRAME-10*PTRS(sp)
    SARG    a1, CLOS_FRAME-9*PTRS(sp)
    SARG    a2, CLOS_FRAME-8*PTRS(sp)
    SARG    a3, CLOS_FRAME-7*PTRS(sp)
    SARG    a4, CLOS_FRAME-6*PTRS(sp)
    SARG    a5, CLOS_FRAME-5*PTRS(sp)
    SARG    a6, CLOS_FRAME-4*PTRS(sp)
    SARG    a7, CLOS_FRAME-3*PTRS(sp)

    /* enter C */
    addi    a0, sp, CLOS_FRAME
    addi    a1, sp, CLOS_FRAME-8*FLTS-10*PTRS
    mv      a2, t1

    call    ffi_closure_inner

    /* return values */
#if FLTS
    FLARG   fa0, CLOS_FRAME-8*FLTS-10*PTRS(sp)
    FLARG   fa1, CLOS_FRAME-7*FLTS-10*PTRS(sp)
#endif

    LARG    a0, CLOS_FRAME-10*PTRS(sp)
    LARG    a1, CLOS_FRAME-9*PTRS(sp)

    /* restore and return */
    LARG    ra, CLOS_FRAME-1*PTRS(sp)
    .cfi_restore 1
    addi    sp, sp, CLOS_FRAME
    .cfi_def_cfa_offset 0
    ret
    .cfi_endproc
    .size ffi_closure_asm, .-ffi_closure_asm
