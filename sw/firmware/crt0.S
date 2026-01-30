    .section .text.init
    .globl _start
_start:
    la  sp, _stack_top
    # Forced early signature write to prove RAM writes land at 0x00000010.
    lui t0, 0x0
    addi t0, t0, 0x10
    li  t1, 0xdead0001
    sw  t1, 0(t0)

    call main

1:  ebreak              # signal completion to the testbench (trap goes high)
    j   1b
