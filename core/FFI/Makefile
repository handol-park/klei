# Makefile for Klei socket FFI library

CC = gcc
CFLAGS = -Wall -Wextra -Werror -fPIC -O2 -I$(LEAN_INCLUDE)
LDFLAGS = -shared

# Get Lean include path
LEAN_INCLUDE ?= $(shell lean --print-prefix)/include

# Library name
LIB = libklei_socket.so

# Source and object files
SRC = socket.c lean_glue.c
OBJ = $(SRC:.c=.o)

# Test program
TEST_SRC = test_socket.c
TEST_BIN = test_socket

.PHONY: all clean test

all: $(LIB)

$(LIB): $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c socket.h
	$(CC) $(CFLAGS) -c $< -o $@

test: $(TEST_BIN)
	@echo "Run './$(TEST_BIN)' to test the socket library"
	@echo "Note: Requires a UDS server running at /tmp/test.sock"

$(TEST_BIN): $(TEST_SRC) socket.o
	$(CC) $(CFLAGS) -o $@ $(TEST_SRC) socket.o

clean:
	rm -f $(OBJ) $(LIB) $(TEST_BIN)

.PHONY: help
help:
	@echo "Klei Socket FFI Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all (default) - Build the shared library"
	@echo "  test          - Build the test program"
	@echo "  clean         - Remove build artifacts"
	@echo "  help          - Show this help message"
