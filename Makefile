CC = nasm
EMU = qemu-system-i386

all: run

boot.bin: boot.asm gdt.asm
	$(CC) -f bin boot.asm -o boot.bin

noyau.bin: noyau.asm idt.asm clavier.asm affichageTextuel.asm ata.asm fat.asm
	$(CC) -f bin noyau.asm -o noyau.bin

os.img: boot.bin noyau.bin
	cat boot.bin noyau.bin > os.img

run: os.img
	$(EMU) -drive format=raw,file=os.img,index=0,media=disk

clean:
	rm -f *.bin *.img
