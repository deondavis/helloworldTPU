#include <stdint.h>
#include <stddef.h>

#define TPU_BASE     0x40000000u
#define ID_ADDR      (TPU_BASE + 0x0000)
#define VER_ADDR     (TPU_BASE + 0x0004)
#define CTRL_ADDR    (TPU_BASE + 0x0008)
#define STATUS_ADDR  (TPU_BASE + 0x000C)
#define A_BASE       (TPU_BASE + 0x0100)
#define B_BASE       (TPU_BASE + 0x0200)
#define C_BASE       (TPU_BASE + 0x0300)

// Signature location inside internal RAM (word-aligned, near top of RAM).
#define SIG_ADDR 0x00003F00u

static volatile uint32_t *const signature = (volatile uint32_t *)SIG_ADDR;

static inline void mmio_write32(uint32_t addr, uint32_t v) {
    *(volatile uint32_t *)addr = v;
}

static inline uint32_t mmio_read32(uint32_t addr) {
    return *(volatile uint32_t *)addr;
}

static inline void mmio_write8(uint32_t addr, uint8_t v) {
    *(volatile uint8_t *)addr = v;
}

int main(void) {
    *signature = 0x11110000u; // entry marker

    // Kick the accelerator without caring about contents.
    mmio_write32(CTRL_ADDR, 0x1);

    // Poll for done with a timeout.
    uint32_t status = 0;
    for (uint32_t i = 0; i < 2048; i++) {
        status = mmio_read32(STATUS_ADDR);
        if (status & 0x2) { // done bit
            *signature = 0x44440000u; // done seen
            break;
        }
    }
    if ((status & 0x2) == 0) {
        *signature = 0xBAD00001u;
        return 1;
    }

    // Success signature.
    *signature = 0xCAFE0001u;
    return 0;
}
