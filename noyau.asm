[bits 32]
[org 0x1000]


start:
    call init_affichage     ; 1. Driver vidéo : Effacer l'écran
    call init_idt           ; 2. Driver IDT & PIC & Clavier
    call fat_init           ; 3. Initialiser le FileSystem (FAT) via ATA

    ; 3. Utilisation de la table d'interruption pour demander un affichage texte (EAX=2, EBX=adresse)
    mov eax, 2
    mov ebx, msg
    int 0x80

    ; --- TEST FAT / ATA ---
    ; 1. On écrit nos données de test physiquement sur le disque
    call fat_test_write
    
    ; 2. On lit le disque pour remplir le 'buffer_lecture'
    call fat_test_read

    ; 3. On affiche le contenu du 'buffer_lecture' avec notre interruption système
    mov eax, 2
    mov ebx, buffer_lecture
    int 0x80

idle:
    hlt                     ; Arrête le processeur
    jmp idle


%include "idt.asm"
%include "clavier.asm"

%include "affichageTextuel.asm"
%include "ata.asm"
%include "fat.asm"

msg db "Systeme amorce !", 10, "Mode d'affichage VGA : OK", 10, "Pilote Clavier IRQ1 : OK", 10, "Pilote Disque ATA & FAT : OK", 10, "Tapez une touche...", 10, 0

; On s'assure que le noyau occupe au moins un secteur complet
times 5120-($-$$) db 0
times 51200-($-$$) db 0