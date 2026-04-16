#ifndef __SM83_H__
#define __SM83_H__
extern uint8_t mem_read8(uint16_t addr);
extern uint8_t mem_read8_debug(uint16_t addr);
extern void mem_write8(uint16_t addr, uint8_t val);
extern void sm83_halted(void);

extern void sm83_execute(void);
extern void sm83_reset(void);
extern void sm83_trace(unsigned debug);

#endif
