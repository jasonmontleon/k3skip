# Cross build on any machine with clang, lld, python3 and make.  The result, ./k3skip, is one static
# riscv64 binary with no dependencies: copy it to the target and run it.
CC      = clang --target=riscv64-linux-gnu
LD      = ld.lld
TEXT   ?= 0x200000		# address of the driver's code
CFLAGS  = -march=rv64gc -mabi=lp64d -mno-relax -O1 -ffreestanding -fno-pic -fno-stack-protector -Wall -Wextra
LDFLAGS = -nostdlib -static -fuse-ld=lld -Wl,--no-relax -Wl,-z,norelro -Wl,--build-id=none -Wl,-Ttext=$(TEXT)

k3skip: k3skip.c k3skip_asm.S build/pages.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ k3skip.c k3skip_asm.S

# window.S + data.S, assembled for their run addresses and packed as pages (build/pages.h, build/pages.bin)
build/pages.h: window.S data.S build-assets/layout.ld build-assets/mkpages.py
	python3 build-assets/mkpages.py "$(CC)" $(LD)

clean:
	rm -rf build k3skip
