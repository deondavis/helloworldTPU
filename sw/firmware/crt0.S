    .section .text.init
    .globl _start
_start:
    la  sp, _stack_top
    call main

1:  ebreak              # signal completion to the testbench (trap goes high)
    j   1b
