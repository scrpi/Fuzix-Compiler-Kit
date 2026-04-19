/*
 *	A simple SM83 emulator for code testing.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include "sm83.h"

static uint8_t ram[65536];

void sm83_halted(void)
{
    fprintf(stderr, "sm83: halt\n");
    exit(1);
}

uint8_t sm83_read_op(uint16_t addr, int debug)
{
    return ram[addr];
}

uint8_t mem_read8_debug(uint16_t addr)
{
	return sm83_read_op(addr, 1);
}

uint8_t mem_read8(uint16_t addr)
{
	return sm83_read_op(addr, 0);
}

static uint8_t fffcval=0;

void mem_write8(uint16_t addr, uint8_t val)
{
	int x;

	/* Writes to certain addresses act like system calls */
	/* 0xFEFF:  exit() with the val as the exit value */
	/* 0xFEFE:  putchar(val) */
	/* 0xFEFC/D: print out the 16-bit value as a decimal */

	switch(addr) {
	    case 0xFFFF:
		if (val == 0)
			exit(0);
		fprintf(stderr, "***FAIL %u\n", val);
		exit(1);
	    case 0xFFFE:
		putchar(val);
		break;
	    case 0xFFFD:
		/* Make the value signed */
		x=  fffcval | (val << 8);
		if (x >= 0x8000)
			x-= 0x10000;
		printf("%d\n", x);
		break;
	    case 0xFFFC:
		fffcval= val;	/* Save low byte for now */
		break;
	    default:
		ram[addr] = val;
	}
}

int main(int argc, char *argv[])
{
	int fd;
	unsigned debug = 0;

	if (argc == 4 && strcmp(argv[1], "-d") == 0) {
		debug = 1;
		argv++;
		argc--;
	}
	if (argc != 3) {
		fprintf(stderr, "sm83emu: test map.\n");
		exit(1);
	}
	fd = open(argv[1], O_RDONLY);
	if (fd == -1) {
		perror(argv[2]);
		exit(1);
	}
	/* 0000-0xFFFF */
	if (read(fd, ram, 0x10000) < 4) {
		fprintf(stderr, "sm83emu: bad test.\n");
		perror(argv[2]);
		exit(1);
	}
	close(fd);

	sm83_reset();
	sm83_trace(debug);
	while (1)
		sm83_execute();
}

