all: fmake

fmake: fmake.o
	$(CC) $(CFLAGS) $< -o $@

fmake.c: make.h
	$(CC) $(CFLAGS) -c $@

clean:
	rm -f fmake.o fmake
