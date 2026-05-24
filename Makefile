CC = nasm
EMU = qemu-system-i386

all: run

ls.bin: ls.asm
	$(CC) -f bin ls.asm -o ls.bin

rm.bin: rm.asm
	$(CC) -f bin rm.asm -o rm.bin

nano.bin: nano.asm
	$(CC) -f bin nano.asm -o nano.bin

boot.bin: boot.asm gdt.asm
	$(CC) -f bin boot.asm -o boot.bin

noyau.bin: ls.bin rm.bin nano.bin noyau.asm idt.asm clavier.asm affichageTextuel.asm ata.asm fat.asm
	$(CC) -f bin noyau.asm -o noyau.bin

os.img: boot.bin noyau.bin
	cat boot.bin noyau.bin > os.img

run: os.img
	$(EMU) -drive format=raw,file=os.img,index=0,media=disk,if=ide,cache=writethrough 

clean:
	rm -f *.bin *.img
