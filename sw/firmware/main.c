#include <stdint.h>

// TPU register map (mirrors rtl/tpu_accel/tpu_regs.v).
#define TPU_BASE     0x40000000u
#define TPU_CTRL     (TPU_BASE + 0x0008)
#define TPU_STATUS   (TPU_BASE + 0x000C)
#define TPU_A_BASE   (TPU_BASE + 0x0100)
#define TPU_B_BASE   (TPU_BASE + 0x0200)
#define TPU_C_BASE   (TPU_BASE + 0x0300)

#define N 4
#define MAT_ELEMS (N * N)

static volatile uint32_t *const tpu_ctrl   = (uint32_t *)TPU_CTRL;
static volatile uint32_t *const tpu_status = (uint32_t *)TPU_STATUS;
static volatile uint8_t  *const tpu_a      = (uint8_t *)TPU_A_BASE;
static volatile uint8_t  *const tpu_b      = (uint8_t *)TPU_B_BASE;
static volatile uint32_t *const tpu_c      = (uint32_t *)TPU_C_BASE;

// Signature block stored in a dedicated linker section (.sig) at 0x0200.
struct sig_block {
    volatile uint32_t code;
    volatile uint32_t observed;
    volatile uint32_t golden;
};
__attribute__((section(".sig"))) struct sig_block sig = {0, 0, 0};

// Software multiply helper to avoid pulling in libgcc (__mulsi3).
uint32_t __mulsi3(uint32_t a, uint32_t b) {
    uint32_t res = 0;
    while (b) {
        if (b & 1u) res += a;
        a <<= 1;
        b >>= 1;
    }
    return res;
}

// Simple 4x4 test matrices (small values to avoid overflow).
static const uint8_t A[N][N] = {
    {1, 2, 3, 4},
    {5, 6, 7, 8},
    {9, 10, 11, 12},
    {13, 14, 15, 16},
};

static const uint8_t B[N][N] = {
    {2, 1, 0, 3},
    {1, 0, 2, 1},
    {3, 1, 1, 0},
    {0, 2, 1, 1},
};

static void load_matrices(void) {
    for (int r = 0; r < N; r++) {
        for (int c = 0; c < N; c++) {
            int idx = r * N + c;
            tpu_a[idx] = A[r][c];
            tpu_b[idx] = B[r][c];
        }
    }
}

static void compute_golden(uint32_t golden[MAT_ELEMS]) {
    for (int i = 0; i < MAT_ELEMS; i++) golden[i] = 0;
    for (int r = 0; r < N; r++) {
        for (int c = 0; c < N; c++) {
            uint32_t acc = 0;
            for (int k = 0; k < N; k++) {
                acc += __mulsi3((uint32_t)A[r][k], (uint32_t)B[k][c]);
            }
            golden[r * N + c] = acc;
        }
    }
}

int main(void) {
    uint32_t golden[MAT_ELEMS];
    compute_golden(golden);
    load_matrices();

    // Clear done then start.
    *tpu_ctrl = 0x2;
    *tpu_ctrl = 0x1;

    // Wait for busy to drop then done to assert.
    while (*tpu_status & 0x1)
        ;
    while (((*tpu_status >> 1) & 0x1) == 0)
        ;

    uint32_t first_obs = 0;
    uint32_t first_gold = 0;
    int mismatches = 0;
    uint32_t checksum_obs = 0;
    uint32_t checksum_gold = 0;

    for (int i = 0; i < MAT_ELEMS; i++) {
        uint32_t obs = tpu_c[i];
        checksum_obs += obs;
        checksum_gold += golden[i];
        if (obs != golden[i]) {
            if (mismatches == 0) {
                first_obs = obs;
                first_gold = golden[i];
            }
            mismatches++;
        }
    }

    if (mismatches == 0) {
        sig.code = 0xBEEF0000u;
        sig.observed = checksum_obs;
        sig.golden   = checksum_gold;
    } else {
        sig.code = 0xBAD00000u | (uint32_t)(mismatches & 0xFFFFu);
        sig.observed = checksum_obs;
        sig.golden   = checksum_gold;
    }

    return 0;
}
