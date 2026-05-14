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
    ; 1. Création dynamique d'un fichier avec nos propres paramètres
    mov esi, nom_mon_fichier
    mov edi, contenu_mon_fichier
    mov ecx, taille_mon_fichier
    call fat_create_file
    
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

nom_mon_fichier db "FICHIER TXT"  ; Nom (8 cars) + Espace + Extension (3 cars) = 11 pile !
contenu_mon_fichier db "Contenu du fichier cree dynamiquement avec la taille ajustee !", 10, 0
taille_mon_fichier equ $ - contenu_mon_fichier

; On remplit l'image pour atteindre exactement 1.44 Mo (2880 secteurs au total, dont 1 secteur de boot)
; Cela évite que QEMU lève une erreur si on écrit au-delà de la fin réelle du fichier os.img !
times (2879 * 512) - ($ - $$) db 0