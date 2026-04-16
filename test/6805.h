/*
 *	6805 processor state
 */

struct m6805 {
    uint8_t a;
    uint8_t p;
    uint16_t s;		/* Only a few used on non HC08 */
    uint16_t s_mask;	/* Mask of bits used */
    uint16_t s_base;	/* Fixed bits */
    uint8_t x;
    uint8_t h;
    uint16_t pc;	/* Will be under 64K but we mask on mem access */

    /* Internal state */
    int state;
#define MODE_RUN	0
#define MODE_STOP	1
#define MODE_WAIT	2
    int type;
#define CPU_6805	0
#define CPU_146805	1
#define	CPU_68HC08	2
    uint32_t irq;
    uint8_t mode;
    int debug;

    /* I/O and memory */
    unsigned intio;
};

#define P_C		1
#define P_Z		4
#define P_N		8
#define P_I		16
#define P_H		32
#define P_V		64	/* Check */

struct m6805_instruction {
    const char *op;
    uint8_t clocks[3];	/* 055, C05, HC08 */
};

extern uint8_t m6805_read(struct m6805 *cpu, uint16_t addr);
extern uint8_t m6805_debug_read(struct m6805 *cpu, uint16_t addr);
extern void m6805_write(struct m6805 *cpu, uint16_t addr, uint8_t data);

/* Provided by the 6805 emulator */
extern void m6805_reset(struct m6805 *cpu, int type, int mode, int io);
extern int m6805_execute(struct m6805 *cpu);
extern void m6805_clear_interrupt(struct m6805 *cpu, int irq);
extern void m6805_raise_interrupt(struct m6805 *cpu, int irq);

/* These are more internal but useful for debug/trace */
extern void m6805_do_write(struct m6805 *cpu, uint16_t addr, uint8_t val);
extern uint8_t m6805_do_read(struct m6805 *cpu, uint16_t addr);
extern uint8_t m6805_do_debug_read(struct m6805 *cpu, uint16_t addr);
