OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text*)
    } > RAM

    .rodata : {
        *(.rodata*)
    } > RAM

    .data : {
        *(.data*)
    } > RAM

    /* Fixed signature block placed away from code/data. */
    .sig 0x00000C00 : {
        KEEP(*(.sig*))
    } > RAM

    .bss (NOLOAD) : {
        *(.bss*)
        *(COMMON)
    } > RAM

    .stack (NOLOAD) : {
        . = ALIGN(4);
        _stack_top = ORIGIN(RAM) + LENGTH(RAM);
    } > RAM
}
