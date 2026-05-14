[bits 16]
[org 0x7c00]

KERNEL_OFFSET equ 0x1000 ; Adresse mémoire où on va charger le noyau

mov [BOOT_DRIVE], dl    ; Le BIOS stocke le numéro du disque de boot dans DL

; Configuration de la pile
mov bp, 0x9000
mov sp, bp

mov si, mss_sl
call afficher

mov si, mss_chr_noyau
call afficher

call load_kernel        ; 1. Charger le noyau du disque à la RAM
call switch_to_pm       ; 2. Passer en Mode Protégé (32 bits)

jmp $                   ; Sécurité

%include "gdt.asm"      ; On inclut la table des descripteurs de segments

load_kernel:
    mov bx, KERNEL_OFFSET ; Destination en mémoire
    mov dh, 10             ; Nombre de secteurs à lire (notre mini-noyau)
    mov dl, [BOOT_DRIVE]
    
    mov ah, 0x02          ; BIOS read sector function
    mov al, dh
    mov ch, 0x00          ; Cylindre 0
    mov dh, 0x00          ; Tête 0
    mov cl, 0x02          ; Secteur 2 (le secteur 1 est le bootloader)
    int 0x13              ; Appel interruption BIOS
    ret

switch_to_pm:
    cli                     ; Désactiver les interruptions
    lgdt [gdt_descriptor]   ; Charger la GDT
    mov eax, cr0
    or eax, 0x1             ; Activer le bit PE (Protection Enable) de CR0
    mov cr0, eax
    jmp CODE_SEG:init_pm    ; Far jump pour vider le pipeline d'instructions
    
afficher:
    push ax                 ; Sauvegarde les registres utilisés
    push bx
    mov ah, 0x0e            ; Fonction BIOS "Teletype output"
    mov bh, 0x00            ; Page vidéo 0

.boucle:
    lodsb                   ; Charge l'octet pointé par SI dans AL, puis SI = SI + 1
    or al, al               ; Vérifie si AL est égal à 0 (fin de chaîne)
    jz .fin                 ; Si AL == 0, on sort de la boucle
    int 0x10                ; Appel l'interruption BIOS pour afficher le caractère
    jmp .boucle             ; Répète pour le caractère suivant

.fin:
    pop bx                  ; Restauration des registres
    pop ax
    ret

[bits 32]
init_pm:
    mov ax, DATA_SEG        ; Mettre à jour les segments de données
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov ebp, 0x90000        ; Mettre à jour la pile pour l'espace 32 bits
    mov esp, ebp

    call KERNEL_OFFSET      ; Sauter vers le noyau chargé !
    jmp $

BOOT_DRIVE db 0

; Remplissage pour atteindre 510 octets + signature de boot
mss_chr_noyau db "Chargement du noyau...", 13, 10, 0
mss_sl db 13, 10, 0
times 510-($-$$) db 0
dw 0xaa55
