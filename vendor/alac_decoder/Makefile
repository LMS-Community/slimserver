CC=gcc
RM=rm -f
CFLAGS=-ggdb -O3 -W -Wall

C_SOURCES=alac.c \
          demux.c \
          main.c \
          stream.c \
          wavwriter.c

OBJECTS=$(C_SOURCES:.c=.o)

alac: $(OBJECTS)
	$(CC) -o alac $(OBJECTS)

%.o: %.c
	$(CC) -c $(CFLAGS) $< -o $@

clean:
	rm -f $(OBJECTS) *.*~ alac

