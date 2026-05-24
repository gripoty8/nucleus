[bits 32]

cursor_pos dd 0 ; Position linéaire du curseur (0 à 1999)

; Initialise l'affichage textuel en effaçant l'écran
init_affichage:
    pusha
    mov edi, 0xb8000
    mov ecx, 2000
    mov ax, 0x0f20      ; 0x0f = fond noir / texte blanc, 0x20 = caractère espace (' ')
    rep stosw
    mov dword [cursor_pos], 0
    popa
    ret

; Affiche un caractère unique (prend le caractère dans AL)
afficher_caractere:
    pusha
    cmp al, 10          ; Code '\n' (Retour à la ligne)
    je .nouvelle_ligne
    cmp al, 8           ; Code '\b' (Backspace)
    je .backspace
    
    mov ebx, [cursor_pos]
    shl ebx, 1          ; Chaque caractère prend 2 octets (caractère + attributs)
    add ebx, 0xb8000
    mov ah, 0x0f        ; Attributs : texte blanc sur fond noir
    mov [ebx], ax

    inc dword [cursor_pos]
    jmp .fin

.nouvelle_ligne:
    mov eax, [cursor_pos]
    mov ebx, 80
    xor edx, edx
    div ebx             ; Calcule la ligne actuelle
    inc eax             ; Passe à la ligne suivante
    mul ebx             ; Calcule le nouvel offset (début de la nouvelle ligne)
    mov [cursor_pos], eax
    jmp .fin

.backspace:
    cmp dword [cursor_pos], 0
    je .fin
    dec dword [cursor_pos]
    mov ebx, [cursor_pos]
    shl ebx, 1
    add ebx, 0xb8000
    mov word [ebx], 0x0f20 ; Efface le caractère en le remplaçant par un espace

.fin:
    popa
    ret

; Affiche une chaîne terminée par '\0' (Adresse de la chaîne dans ESI)
afficher_chaine:
    pusha
.boucle:
    lodsb               ; Charge [ESI] dans AL et incrémente ESI
    test al, al         ; Fin de chaîne (0x00) ?
    jz .fin
    call afficher_caractere
    jmp .boucle
.fin:
    popa
    ret[bits 32]

; Lit 1 secteur (512 octets) depuis le disque en mode LBA28
; IN: EAX = Adresse LBA du secteur
;     EDI = Adresse mémoire de destination
ata_read_sector:
    pusha
    cld                     ; Force l'incrémentation de EDI (essentiel pour rep insw)

    mov ebx, eax            ; Sauvegarde LBA AVANT de modifier AL !

    ; Désactiver les interruptions IDE pour utiliser le polling sans crash
    mov dx, 0x3F6
    mov al, 0x02            ; Bit nIEN = 1
    out dx, al

    ; --- Sélection du disque avant lecture du statut ---
    mov dx, 0x1F6
    shr eax, 24
    and al, 0x0F
    or al, 0xE0             ; Disque Maître + LBA
    out dx, al

    ; Délai matériel de 400ns vital pour laisser l'IDE changer de contexte
    mov dx, 0x1F7
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    ; Attendre que le disque soit prêt
.wait_ready:
    in al, dx
    test al, 0x80           ; BSY (Busy) doit être à 0
    jnz .wait_ready
    test al, 1              ; En cas d'erreur fatale, on quitte sans figer
    jnz .error

    ; --- Configuration de la lecture ---
    mov dx, 0x1F2
    mov al, 1
    out dx, al              ; Nombre de secteurs à lire: 1

    ; Envoyer l'adresse LBA (28 bits)
    mov eax, ebx            ; Récupère LBA
    mov dx, 0x1F3
    out dx, al              ; LBA bits 0-7
    shr eax, 8
    mov dx, 0x1F4
    out dx, al              ; LBA bits 8-15
    shr eax, 8
    mov dx, 0x1F5
    out dx, al              ; LBA bits 16-23
    shr eax, 8
    mov dx, 0x1F6
    and al, 0x0F            ; Garde seulement les bits 24-27
    or al, 0xE0             ; Mode LBA + disque maître
    out dx, al

    ; Envoyer la commande de lecture
    mov dx, 0x1F7
    mov al, 0x20
    out dx, al              ; Commande: READ SECTOR(S)

    ; Délai de 400ns
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    ; Attendre que le disque ait des données prêtes (DRQ=1)
.wait_drq:
    in al, dx
    test al, 0x80           ; Le disque est-il occupé (BSY) à chercher les données ?
    jnz .wait_drq           ; Si oui, on attend avant de lire les autres bits !
    test al, 1              ; Vérifier le bit d'erreur
    jnz .error
    test al, 8              ; Attendre le bit DRQ
    jz .wait_drq

    ; Lire les données depuis le port
    mov dx, 0x1F0
    mov ecx, 256            ; 256 mots de 16-bit = 512 octets
    rep insw                ; Copie les données du port vers [EDI]

    popa
    clc                     ; CF = 0 (Succès de la lecture)
    ret

.error:
    popa
    stc                     ; CF = 1 (Erreur de lecture)
    ret

; Écrit 1 secteur (512 octets) sur le disque en mode LBA28
; IN: EAX = Adresse LBA du secteur
;     ESI = Adresse mémoire source
ata_write_sector:
    pusha
    cld                     ; Force l'incrémentation de ESI (essentiel pour rep outsw)

    mov ebx, eax            ; Sauvegarde LBA AVANT de modifier AL !

    ; Désactiver les interruptions IDE
    mov dx, 0x3F6
    mov al, 0x02
    out dx, al

    ; --- Sélection du disque avant lecture du statut ---
    mov dx, 0x1F6
    shr eax, 24
    and al, 0x0F
    or al, 0xE0             ; Disque Maître + LBA
    out dx, al

    ; Délai matériel de 400ns
    mov dx, 0x1F7
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    ; Attendre que le disque soit prêt
.wait_ready:
    in al, dx
    test al, 0x80           ; BSY (Busy) doit être à 0
    jnz .wait_ready
    test al, 1              ; En cas d'erreur fatale, on quitte sans figer
    jnz .error

    ; --- Configuration de l'écriture ---
    mov dx, 0x1F2
    mov al, 1
    out dx, al              ; Nombre de secteurs à écrire: 1

    ; Envoyer l'adresse LBA (28 bits)
    mov eax, ebx            ; Récupère LBA
    mov dx, 0x1F3
    out dx, al              ; LBA bits 0-7
    shr eax, 8
    mov dx, 0x1F4
    out dx, al              ; LBA bits 8-15
    shr eax, 8
    mov dx, 0x1F5
    out dx, al              ; LBA bits 16-23
    shr eax, 8
    mov dx, 0x1F6
    and al, 0x0F            ; Garde seulement les bits 24-27
    or al, 0xE0             ; Mode LBA + disque maître
    out dx, al

    ; Envoyer la commande d'écriture
    mov dx, 0x1F7
    mov al, 0x30
    out dx, al              ; Commande: WRITE SECTOR(S)

    ; Délai de 400ns
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    ; Attendre que le disque soit prêt à recevoir les données (DRQ=1)
.wait_drq:
    in al, dx
    test al, 0x80           ; Le disque est-il occupé (BSY) ?
    jnz .wait_drq
    test al, 1              ; Vérifier le bit d'erreur
    jnz .error
    test al, 8              ; Attendre le bit DRQ
    jz .wait_drq

    ; Écrire les données sur le port
    mov dx, 0x1F0
    mov ecx, 256            ; 256 mots de 16-bit = 512 octets
    rep outsw               ; Copie les données de [ESI] vers le port

    ; Attendre que le disque soit prêt avant de lancer le cache flush
    mov dx, 0x1F7
.wait_transfer_done:
    in al, dx
    test al, 0x80           ; BSY
    jnz .wait_transfer_done

    ; Forcer l'écriture physique depuis le cache du disque
    mov dx, 0x1F7
    mov al, 0xE7            ; Commande: FLUSH CACHE
    out dx, al

    ; Attendre la fin du flush (BSY=0)
.wait_flush:
    in al, dx
    test al, 0x80
    jnz .wait_flush

    popa
    clc                     ; CF = 0
    ret

.error:
    popa
    stc                     ; CF = 1
    ret[bits 16]
[org 0x7c00]

jmp short start
nop

; --- En-tête BPB (BIOS Parameter Block) FAT16 ---
OEMname             db "NUCLEUS "   ; 8 octets
bytesPerSector      dw 512          ; [11] 2 octets
sectPerCluster      db 1            ; [13] 1 octet
reservedSectors     dw 32           ; [14] 2 octets (Bootloader + Espace pour le Noyau)
numFAT              db 2            ; [16] 1 octet
numRootDirEntries   dw 512          ; [17] 2 octets
numSectors          dw 2880         ; [19] 2 octets
mediaType           db 0xf0         ; [21] 1 octet
numFATsectors       dw 9            ; [22] 2 octets
sectorsPerTrack     dw 18           ; [24] 2 octets
numHeads            dw 2            ; [26] 2 octets
numHiddenSectors    dd 0            ; [28] 4 octets
numSectorsHuge      dd 0            ; [32] 4 octets
driveNum            db 0            ; [36] 1 octet
reserved            db 0            ; [37] 1 octet
signature           db 0x29         ; [38] 1 octet
volumeID            dd 0x12345678   ; [39] 4 octets
volumeLabel         db "NUCLEUS OS " ; [43] 11 octets
fileSysType         db "FAT16   "   ; [54] 8 octets

start:
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
    mov dh, 30             ; Nombre de secteurs à lire (augmenté car le noyau grandit !)
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
[bits 32]

dernier_caractere db 0
kbd_buffer times 256 db 0     ; Buffer de 256 caractères maximum
kbd_buffer_idx dd 0
kbd_enter_pressed db 0
shift_pressed db 0            ; État de la touche Majuscule

isr_clavier:
    pusha
    in al, 0x60             ; Lecture du port de données du clavier (0x60)
    
    ; Gestion des touches Majuscules (Shift)
    cmp al, 0x2A            ; Shift gauche pressé
    je .shift_down
    cmp al, 0x36            ; Shift droit pressé
    je .shift_down
    cmp al, 0xAA            ; Shift gauche relâché
    je .shift_up
    cmp al, 0xB6            ; Shift droit relâché
    je .shift_up

    test al, 0x80           ; Vérifie si c'est un "Break Code" (Touche relâchée)
    jnz .fin                ; Si oui, on l'ignore
    
    ; Conversion en caractère ASCII
    call scancode_vers_ascii
    mov [dernier_caractere], al
    
    ; Si le caractère est nul, on l'ignore (Shift, Ctrl, etc.)
    cmp al, 0
    je .fin
    
    ; Écho du caractère à l'écran
    mov bl, al
    mov eax, 1              ; Fonction 1: Afficher un caractère (bl = char)
    int 0x80

    ; Gestion du buffer pour le shell de l'OS
    mov al, [dernier_caractere]
    cmp al, 10              ; Enter
    je .enter
    cmp al, 8               ; Backspace
    je .backspace
    
    mov ebx, [kbd_buffer_idx]
    cmp ebx, 255
    jge .fin
    mov [kbd_buffer + ebx], al
    inc dword [kbd_buffer_idx]
    jmp .fin

.backspace:
    cmp dword [kbd_buffer_idx], 0
    je .fin
    dec dword [kbd_buffer_idx]
    jmp .fin
    
.enter:
    mov ebx, [kbd_buffer_idx]
    mov byte [kbd_buffer + ebx], 0 ; Ajoute le '\0' de fin de chaîne
    mov byte [kbd_enter_pressed], 1
    jmp .fin

.shift_down:
    mov byte [shift_pressed], 1
    jmp .fin

.shift_up:
    mov byte [shift_pressed], 0
    jmp .fin

.fin:
    mov al, 0x20            ; End Of Interrupt (EOI)
    out 0x20, al            ; Envoi au PIC
    popa
    iret

scancode_vers_ascii:
    and eax, 0xFF           ; Nettoyage du reste du registre EAX
    cmp eax, 0x39           ; Limite de la table
    ja .inconnu
    
    cmp byte [shift_pressed], 1
    je .use_shift
    
    mov ebx, table_azerty
    jmp .do_lookup

.use_shift:
    mov ebx, table_azerty_shift

.do_lookup:
    add ebx, eax
    mov al, [ebx]
    ret
.inconnu:
    mov al, 0
    ret

; Table de mapping pour layout AZERTY (Set 1) simplifiée (Table de caractères ASCII standard)
table_azerty:
    db 0, 27, '&', 130, '"', "'", '(', '-', 138, '_', 135, 133, ')', '=', 8
    db 9, 'a', 'z', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '^', '$', 10, 0
    db 'q', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'm', 151, '*', 0, '\'
    db 'w', 'x', 'c', 'v', 'b', 'n', ',', ';', ':', '!', 0, '*', 0, ' '
    times 128 - ($ - table_azerty) db 0

table_azerty_shift:
    db 0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 176, '+', 8
    db 9, 'A', 'Z', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '^', '$', 10, 0
    db 'Q', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'M', '%', '*', 0, '\'
    db 'W', 'X', 'C', 'V', 'B', 'N', '?', '.', '/', 167, 0, '*', 0, ' '
    times 128 - ($ - table_azerty_shift) db 0[bits 32]

; Structures en mémoire pour le système de fichiers
fat_bpb_buffer times 512 db 0

fat_root_dir_lba dd 0
fat_data_lba dd 0
fat_fat1_lba dd 0
fat_fat2_lba dd 0
current_dir_lba dd 0
current_dir_cluster dd 0

; Initialise la FAT en lisant le secteur 0 (assumé comme Boot Sector / VBR non partitionné)
fat_init:
    pusha
    
    mov eax, 0                      ; Secteur LBA 0
    mov edi, fat_bpb_buffer
    call ata_read_sector            ; Appel au pilote matériel

    ; Calculer le LBA des deux tables d'allocation FAT
    movzx eax, word [fat_bpb_buffer + 14] ; ReservedSectors
    mov [fat_fat1_lba], eax
    movzx ebx, word [fat_bpb_buffer + 22] ; SectorsPerFAT (spécifique à FAT16)
    add eax, ebx
    mov [fat_fat2_lba], eax

    ; Calculer le LBA du Répertoire Racine (Root Directory)
    ; Formule : ReservedSectors + (NumberOfFATs * SectorsPerFAT)
    movzx eax, word [fat_bpb_buffer + 14] ; ReservedSectors
    movzx ebx, byte [fat_bpb_buffer + 16] ; NumberOfFATs
    movzx ecx, word [fat_bpb_buffer + 22] ; SectorsPerFAT (spécifique à FAT16)
    imul ebx, ecx
    add eax, ebx
    mov [fat_root_dir_lba], eax
    mov [current_dir_lba], eax
    mov dword [current_dir_cluster], 0

    ; Calculer le LBA du début de l'espace de données (Après le Root Dir)
    ; RootDirSectors = (RootDirEntries * 32) / 512
    movzx ebx, word [fat_bpb_buffer + 17] ; RootDirEntries
    shl ebx, 5                      ; * 32 (Taille d'une entrée FAT standard)
    add ebx, 511                    ; Arrondi supérieur
    shr ebx, 9                      ; / 512 (Taille d'un secteur)
    add eax, ebx
    mov [fat_data_lba], eax

    popa
    ret

buffer_lecture times 512 db 0

; Test : Lecture de ce même secteur vers notre buffer vide
fat_test_read:
    pusha
    mov eax, [fat_data_lba]     ; LBA du début des données FAT
    mov edi, buffer_lecture     ; Adresse de destination (EDI pour insw)
    call ata_read_sector
    popa
    ret

fat_table_buffer times 512 db 0

; Initialise l'intégralité du système de fichiers au premier démarrage.
fat_setup_bin_dir:
    pusha
    ; 1. Mise à jour de la table FAT pour tous les fichiers et dossiers initiaux
    ; Cluster 2: LISEZMOITXT, 3: BIN (Dir), 4: LS, 5: RM, 6: NANO
    mov word [fat_table_buffer], 0xFFF0
    mov word [fat_table_buffer+2], 0xFFFF
    mov word [fat_table_buffer+4], 0xFFFF
    mov word [fat_table_buffer+6], 0xFFFF
    mov word [fat_table_buffer+8], 0xFFFF
    mov word [fat_table_buffer+10], 0xFFFF
    mov word [fat_table_buffer+12], 0xFFFF
    
    mov eax, [fat_fat1_lba]
    mov esi, fat_table_buffer
    call ata_write_sector
    mov eax, [fat_fat2_lba]
    call ata_write_sector

    ; 2. Création des entrées dans le Répertoire Racine (Root Directory)
    mov edi, buffer_lecture
    mov ecx, 512
    xor al, al
    rep stosb           ; Vider le secteur

    mov esi, buffer_lecture

    ; Entrée 1: LISEZMOITXT
    mov dword [esi], 'LISE'
    mov dword [esi+4], 'ZMOI'
    mov dword [esi+8], 'TXT '
    mov byte [esi+11], 0x20 ; Attribut: Archive
    mov word [esi+26], 2    ; Cluster 2
    mov eax, lisezmoi_size
    mov dword [esi+28], eax

    ; Entrée 2: BIN (Dossier)
    add esi, 32
    mov dword [esi], 'BIN '
    mov dword [esi+4], '    '
    mov dword [esi+8], '    '
    mov byte [esi+11], 0x10 ; Attribut Dossier (Sub-Directory)
    mov word [esi+26], 3    ; Cluster 3
    mov dword [esi+28], 0   ; Taille 0 pour un dossier

    ; Écriture du secteur du Répertoire Racine sur le disque
    mov eax, [fat_root_dir_lba]
    mov esi, buffer_lecture
    call ata_write_sector
    
    ; 3. Initialisation du contenu du dossier BIN (Cluster 3)
    mov edi, buffer_lecture
    mov ecx, 512
    xor al, al
    rep stosb           ; Vider le secteur
    
    mov edi, buffer_lecture
    ; Entrée "." (pointe sur lui-même)
    mov dword [edi], '.   '
    mov dword [edi+4], '    '
    mov dword [edi+8], '    '
    mov byte [edi+11], 0x10 ; Attribut Dossier (Sub-Directory)
    mov word [edi+26], 3    ; Cluster 3 (BIN)
    mov dword [edi+28], 0

    ; Entrée ".." (pointe sur le parent, la racine)
    add edi, 32
    mov dword [edi], '..  '
    mov dword [edi+4], '    '
    mov dword [edi+8], '    '
    mov byte [edi+11], 0x10 ; Attribut Dossier
    mov word [edi+26], 0    ; Cluster 0 (Root)
    mov dword [edi+28], 0

    ; Entrée "LS"
    add edi, 32
    mov dword [edi], 'LS  '
    mov dword [edi+4], '    '
    mov dword [edi+8], '    '
    mov byte [edi+11], 0x20
    mov word [edi+26], 4    ; Cluster 4
    mov dword [edi+28], ls_program_size

    ; Entrée "RM"
    add edi, 32
    mov dword [edi], 'RM  '
    mov dword [edi+4], '    '
    mov dword [edi+8], '    '
    mov byte [edi+11], 0x20
    mov word [edi+26], 5    ; Cluster 5
    mov dword [edi+28], rm_program_size

    ; Entrée "NANO"
    add edi, 32
    mov dword [edi], 'NANO'
    mov dword [edi+4], '    '
    mov dword [edi+8], '    '
    mov byte [edi+11], 0x20 ; Attribut: Archive
    mov word [edi+26], 6    ; Cluster 6
    mov dword [edi+28], nano_program_size

    ; Écriture du secteur du dossier BIN sur le disque
    mov eax, [fat_data_lba]
    inc eax                 ; LBA du Cluster 3 (fat_data_lba + (3-2))
    mov esi, buffer_lecture
    call ata_write_sector
    
    ; 4. Écriture physique des données des fichiers sur le disque
    ; LISEZMOITXT (Cluster 2)
    mov eax, [fat_data_lba] ; LBA du Cluster 2 (fat_data_lba + (2-2))
    mov esi, lisezmoi_data
    call ata_write_sector

    ; LS (Cluster 4)
    mov eax, [fat_data_lba]
    add eax, 2              ; LBA du Cluster 4 (fat_data_lba + 2)
    mov esi, ls_program_data
    call ata_write_sector
    
    ; RM (Cluster 5)
    mov eax, [fat_data_lba]
    add eax, 3              ; LBA du Cluster 5 (fat_data_lba + 3)
    mov esi, rm_program_data
    call ata_write_sector
    
    ; NANO (Cluster 6)
    mov eax, [fat_data_lba]
    add eax, 4              ; LBA du Cluster 6 (fat_data_lba + 4)
    mov esi, nano_program_data
    call ata_write_sector

    popa
    ret

; --- Données des fichiers à inclure ---
ls_program_data:
    incbin "ls.bin"
ls_program_size equ $ - ls_program_data

rm_program_data:
    incbin "rm.bin"
rm_program_size equ $ - rm_program_data

nano_program_data:
    incbin "nano.bin"
nano_program_size equ $ - nano_program_data

lisezmoi_data:
    incbin "LISEZMOI.txt"
lisezmoi_size equ $ - lisezmoi_datagdt_start:
    dd 0x0, 0x0             ; Entrée nulle obligatoire

gdt_code:                   ; Segment de code
    dw 0xffff               ; Limite
    dw 0x0                  ; Base (0-15)
    db 0x0                  ; Base (16-23)
    db 10011010b            ; Flags d'accès
    db 11001111b            ; Drapeaux + Limite (16-19)
    db 0x0                  ; Base (24-31)

gdt_data:                   ; Segment de données
    dw 0xffff
    dw 0x0
    db 0x0
    db 10010010b
    db 11001111b
    db 0x0

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start
[bits 32]

; Structure de la table IDT (256 entrées)
idt_start:
    times 256 dq 0
idt_end:

idt_descriptor:
    dw idt_end - idt_start - 1 ; Limite / Taille
    dd idt_start               ; Base (Adresse mémoire)

; Macro simplifiée pour inscrire un handler dans la table IDT
; %1 = Numéro de l'interruption, %2 = Fonction du handler
%macro set_idt_entry 2
    mov eax, %2
    mov ebx, %1
    shl ebx, 3               ; * 8 car chaque entrée fait 8 octets
    add ebx, idt_start
    mov word [ebx], ax       ; Bits 0-15 de l'offset
    mov word [ebx+2], 0x08   ; Sélecteur de code GDT (CODE_SEG)
    mov word [ebx+4], 0x8E00 ; Flags : Present, Ring 0, Interrupt Gate 32b
    shr eax, 16
    mov word [ebx+6], ax     ; Bits 16-31 de l'offset
%endmacro

init_idt:
    ; Initialisation et Remappage du PIC maître et esclave
    ; Les IRQ matériels (0-15) sont décalés vers 32-47 (0x20-0x2F)
    mov al, 0x11
    out 0x20, al        ; PIC Master - init
    out 0xA0, al        ; PIC Slave - init
    
    mov al, 0x20
    out 0x21, al        ; Offset du Master : 0x20 (32)
    mov al, 0x28
    out 0xA1, al        ; Offset du Slave : 0x28 (40)
    
    mov al, 0x04
    out 0x21, al        ; Cascade sur IRQ2
    mov al, 0x02
    out 0xA1, al
    
    mov al, 0x01
    out 0x21, al        ; Mode 8086
    out 0xA1, al
    
    ; On active l'IRQ1 (clavier) et on masque tout le reste pour l'instant
    mov al, 0xFD        ; 1111 1101 (masque clavier libre)
    out 0x21, al
    mov al, 0xFF        ; Tout bloquer sur le slave
    out 0xA1, al

    ; Renseignement des interruptions
    set_idt_entry 0x21, isr_clavier ; IRQ1 -> Int 0x21
    set_idt_entry 0x80, isr_systeme ; Int Système personnalisée
    
    ; Activation
    lidt [idt_descriptor]
    sti                 ; Activation des interruptions CPU
    ret

; Notre appel système - int 0x80
; EAX = Fonction désirée
isr_systeme:
    cmp eax, 1
    je .sys_print_char
    cmp eax, 2
    je .sys_print_string
    cmp eax, 3
    je .sys_exit
    cmp eax, 4
    je .sys_read_sector
    cmp eax, 5
    je .sys_get_root
    cmp eax, 6
    je .sys_write_sector
    cmp eax, 7
    je .sys_clear_screen
    cmp eax, 8
    je .sys_get_char
    iret

.sys_print_char:
    pusha
    mov al, bl
    call afficher_caractere
    popa
    iret
.sys_print_string:
    pusha
    mov esi, ebx
    call afficher_chaine
    popa
    iret
.sys_exit:
    sti                  ; Réactive les interruptions matérielles
    jmp shell_loop_start ; Retour brutal mais infaillible au Shell
.sys_read_sector:
    pusha
    mov eax, ebx
    mov edi, ecx
    call ata_read_sector
    popa
    iret
.sys_write_sector:
    pusha
    mov eax, ebx
    mov esi, ecx
    call ata_write_sector
    popa
    iret
.sys_get_root:
    mov eax, [current_dir_lba] ; Renvoie le répertoire courant à l'utilisateur via EAX
    mov ebx, [fat_data_lba]    ; Renvoie la base des données FAT dans EBX
    iret

.sys_clear_screen:
    pusha
    call init_affichage
    popa
    iret

.sys_get_char:
    push ebx
    push ecx
    mov ebx, [kbd_buffer_idx]
    mov byte [kbd_enter_pressed], 0 ; Ignore la touche "Entrée" fantôme venant du Shell
.wait_char:
    sti
    hlt
    
    ; 1. Vérification matérielle de la touche ECHAP (Scancode 0x01)
    in al, 0x60
    cmp al, 0x01
    je .esc_pressed

    ; 2. Vérification de la touche Entrée
    cmp byte [kbd_enter_pressed], 1
    je .enter_pressed

    ; 3. Vérification d'un nouveau caractère dans le buffer
    mov ecx, [kbd_buffer_idx]
    cmp ebx, ecx
    je .wait_char
    jl .backspace_pressed
    
    ; Nouveau caractère ajouté !
    dec ecx
    mov al, [kbd_buffer + ecx]
    jmp .done_get_char

.backspace_pressed:
    mov al, 0x08
    jmp .done_get_char
.esc_pressed:
    mov al, 0x1B
    jmp .done_get_char
.enter_pressed:
    mov byte [kbd_enter_pressed], 0
    mov al, 0x0D
.done_get_char:
    pop ecx
    pop ebx
    iret[bits 32]
[org 0x200000] ; L'OS chargera toujours les programmes à 2 Mo en RAM

start:
    ; 1. Afficher les arguments si présents (EDX pointe sur la chaine d'arguments)
    mov al, [edx]
    cmp al, 0
    je .no_args
    
    mov eax, 2
    mov ebx, msg_args
    int 0x80
    mov eax, 2
    mov ebx, edx
    int 0x80
    mov bl, 10
    mov eax, 1
    int 0x80
.no_args:

    ; 2. Demander à l'OS le LBA du Root Directory
    mov eax, 5        ; Syscall 5: Get Root Dir
    int 0x80
    mov ebx, eax      ; On place le LBA pour la lecture
    
    ; 3. Demander à l'OS de lire le secteur en mémoire (à 0x210000)
    mov ecx, 0x210000
    mov eax, 4        ; Syscall 4: Read Sector
    int 0x80
    
    ; 4. Parcourir et afficher le contenu
    mov esi, 0x210000
    mov edx, 16       ; 16 entrées maximum dans le secteur
.loop:
    mov al, [esi]
    cmp al, 0         ; Fin du répertoire
    je .done
    cmp al, 0xE5      ; Fichier supprimé
    je .next
    
    ; Afficher le nom du fichier caractère par caractère (11 caractères)
    pusha
    mov ecx, 11
    mov edi, esi
.print_char:
    mov bl, [edi]
    mov eax, 1
    int 0x80
    inc edi
    loop .print_char
    
    ; Retour à la ligne
    mov bl, 10
    mov eax, 1
    int 0x80
    popa
    
.next:
    add esi, 32
    dec edx
    jnz .loop
    
.done:
    mov eax, 3        ; Syscall 3: Exit (Retourne au Shell de l'OS)
    int 0x80

msg_args db "Arguments passes : ", 0

; On s'assure que l'exécutable occupe exactement 1 secteur de 512 octets
times 512 - ($ - $$) db 0[bits 32]
[org 0x200000] ; Chargement du programme à 2 Mo

start:
    cld
    ; 1. Vérifier si un argument (nom de fichier) est passé
    mov al, [edx]
    cmp al, 0
    jne .format_arg

    ; Pas d'argument -> Afficher l'usage et quitter
    mov eax, 2          ; Syscall 2: Print String
    mov ebx, msg_usage
    int 0x80
    jmp .exit_no_clear

.format_arg:
    ; Formater l'argument (nom de fichier FAT de 11 char)
    mov esi, edx
    mov edi, arg_formatted
    mov ecx, 11
    mov al, ' '
    rep stosb

    mov esi, edx
    mov edi, arg_formatted
    mov ecx, 11
.format_loop:
    lodsb
    cmp al, 0
    je .do_search
    cmp al, 'a'
    jl .store
    cmp al, 'z'
    jg .store
    sub al, 32
.store:
    stosb
    loop .format_loop

.do_search:
    mov eax, 5        ; Syscall 5: Get Dir LBA
    int 0x80
    mov [dir_lba], eax
    mov [fat_data_lba], ebx
    
    ; Lire le secteur du répertoire en mémoire (Buffer à 0x211000)
    mov ebx, [dir_lba]
    mov ecx, 0x211000
    mov eax, 4        ; Syscall 4: Read Sector
    int 0x80
    
    mov esi, 0x211000
    mov edx, 16
.search_loop:
    cmp byte [esi], 0
    je .not_found
    cmp byte [esi], 0xE5
    je .next_entry
    
    pusha
    mov edi, arg_formatted
    mov ecx, 11
    repe cmpsb
    popa
    je .found
    
.next_entry:
    add esi, 32
    dec edx
    jnz .search_loop

.not_found:
    mov eax, 2
    mov ebx, msg_not_found
    int 0x80
    jmp .exit_no_clear

.found:
    movzx eax, word [esi + 26] ; Cluster
    mov ebx, [fat_data_lba]
    add ebx, eax
    sub ebx, 2
    mov [file_lba], ebx
    
    ; Récupérer la taille exacte
    mov eax, dword [esi + 28]
    cmp eax, 511
    jle .size_ok
    mov eax, 511 ; Limite de Nano
.size_ok:
    mov [cursor_pos], eax

    ; Lire le secteur du fichier en mémoire à 0x210000
    mov ecx, 0x210000
    mov ebx, [file_lba]
    mov eax, 4        ; Syscall 4: Read Sector
    int 0x80
    
    ; Remplir le reste du buffer avec des zéros
    mov edi, 0x210000
    add edi, [cursor_pos]
    mov ecx, 512
    sub ecx, [cursor_pos]
    mov al, 0
    rep stosb
    
    jmp .redraw_and_loop

.redraw_and_loop:
    ; 1. Effacer l'écran via le nouveau Syscall 7
    mov eax, 7
    int 0x80

    ; 2. Afficher le message de bienvenue en haut
    mov eax, 2
    mov ebx, msg_welcome
    int 0x80

    ; 3. Afficher le contenu actuel du fichier
    mov ebx, [cursor_pos]
    mov byte [0x210000 + ebx], 0 ; Terminateur nul temporaire pour l'affichage
    
    mov eax, 2
    mov ebx, 0x210000
    int 0x80

.edit_loop:
    ; 4. Attendre une touche clavier (Syscall 8 = Get Char -> AL)
    mov eax, 8
    int 0x80

    cmp al, 0x1B        ; Touche ECHAP (ASCII)
    je .save_and_exit
    cmp al, 0x01        ; Touche ECHAP (Scancode direct - sécurité)
    je .save_and_exit
    
    cmp al, 0x08        ; Touche Retour Arrière (ASCII)
    je .handle_backspace
    cmp al, 0x0E        ; Touche Retour Arrière (Scancode - sécurité)
    je .handle_backspace
    
    cmp al, 0x0D        ; Touche Entrée (ASCII CR)
    je .handle_enter
    cmp al, 0x0A        ; Touche Entrée (ASCII LF)
    je .handle_enter
    cmp al, 0x1C        ; Touche Entrée (Scancode - sécurité)
    je .handle_enter

    ; Filtrer les autres caractères non imprimables (en dessous de l'espace)
    cmp al, 0x20
    jl .edit_loop

.store_char:
    mov ebx, [cursor_pos]
    cmp ebx, 511
    jge .edit_loop      ; Si on atteint 511, on ignore la saisie

    mov byte [0x210000 + ebx], al
    inc dword [cursor_pos]
    jmp .redraw_and_loop

.handle_enter:
    mov al, 10          ; Convertir Entrée en saut de ligne (Line Feed '\n')
    jmp .store_char

.handle_backspace:
    mov ebx, [cursor_pos]
    cmp ebx, 0
    jle .edit_loop      ; Si le curseur est à 0, on ne peut pas effacer

    dec dword [cursor_pos]
    jmp .redraw_and_loop

.save_and_exit:
    ; Effacer l'écran
    mov eax, 7
    int 0x80
    
    ; Afficher le message de sauvegarde
    mov eax, 2
    mov ebx, msg_saving
    int 0x80

    ; Sauvegarder réellement sur le disque
    mov ebx, [file_lba]
    mov ecx, 0x210000
    mov eax, 6        ; Syscall 6: Write Sector
    int 0x80

    ; Mettre à jour la taille du fichier dans le répertoire
    mov ebx, [dir_lba]
    mov ecx, 0x211000
    mov eax, 4        ; Syscall 4: Read Sector
    int 0x80

    mov esi, 0x211000
    mov edx, 16
.update_search:
    pusha
    mov edi, arg_formatted
    mov ecx, 11
    repe cmpsb
    popa
    je .update_found
    add esi, 32
    dec edx
    jnz .update_search
    jmp .exit

.update_found:
    mov eax, [cursor_pos]
    mov dword [esi + 28], eax ; Met à jour la taille

    mov ebx, [dir_lba]
    mov ecx, 0x211000
    mov eax, 6        ; Syscall 6: Write Sector
    int 0x80
    
    jmp .exit

.exit:
    ; Effacer l'écran avant de revenir au Shell
    mov eax, 7
    int 0x80

.exit_no_clear:
    mov eax, 3          ; Syscall 3: Exit
    int 0x80

msg_usage     db "Utilisation: NANO <fichier>", 10, 0
msg_not_found db "Fichier introuvable. Creation non supportee.", 10, 0
msg_welcome   db "--- MINI NANO --- (Appuyez sur ECHAP pour quitter)", 10, 0
msg_saving    db "Sauvegarde et fermeture...", 10, 0
cursor_pos    dd 0
dir_lba       dd 0
fat_data_lba  dd 0
file_lba      dd 0
arg_formatted times 11 db ' '

; On s'assure que l'exécutable occupe exactement 1 secteur de 512 octets
times 1024 - ($ - $$) db 0[bits 32]
[org 0x1000]


start:
    call init_affichage     ; 1. Driver vidéo : Effacer l'écran
    call init_idt           ; 2. Driver IDT & PIC & Clavier
    call fat_init           ; 3. Initialiser le FileSystem (FAT) via ATA

    ; 3. Utilisation de la table d'interruption pour demander un affichage texte (EAX=2, EBX=adresse)
    mov eax, 2
    mov ebx, msg
    int 0x80

    ; --- VÉRIFICATION DE PREMIER DÉMARRAGE ---
    ; On lit le Root Directory pour voir s'il est déjà initialisé
    mov eax, [fat_root_dir_lba]
    mov edi, buffer_lecture
    call ata_read_sector
    
    cmp byte [buffer_lecture], 0    ; Le premier octet est 0 si le disque est vierge
    jne skip_init                   ; Si ce n'est pas 0, on conserve les données !

    ; Le disque est vierge, on procède à l'installation initiale du système de fichiers.
    ; Cette fonction crée LISEZMOITXT, NANO, le dossier BIN et les commandes LS/RM.
    call fat_setup_bin_dir

skip_init:

shell_loop_start:
    mov esp, 0x90000        ; Réinitialisation ABSOLUE de la pile (évite tout crash ou fuite !)
    mov eax, 2
    mov ebx, prompt_msg
    int 0x80
    
    ; Vidage complet du buffer clavier pour éviter les restes d'arguments (Fantômes)
    mov edi, kbd_buffer
    mov ecx, 256
    mov al, 0
    rep stosb

    mov dword [kbd_buffer_idx], 0
    mov byte [kbd_enter_pressed], 0

shell_wait:
    cmp byte [kbd_enter_pressed], 1
    je process_cmd
    hlt
    jmp shell_wait
    
process_cmd:
    call search_and_execute
    jmp shell_loop_start


%include "idt.asm"
%include "clavier.asm"

%include "affichageTextuel.asm"
%include "ata.asm"
%include "fat.asm"

msg db "Systeme amorce !", 10, "Mode d'affichage VGA : OK", 10, "Pilote Clavier IRQ1 : OK", 10, "Pilote Disque ATA & FAT : OK", 10, "Tapez une touche...", 10, 0

prompt_msg db "NUCLEUS> ", 0
msg_not_found db "Commande introuvable", 10, 0
empty_string db 0
formatted_cmd times 11 db ' '
cmd_args_ptr dd 0
cmd_cd db "CD         "
msg_dir_not_found db "Dossier introuvable", 10, 0
msg_not_a_dir db "Ce n'est pas un dossier", 10, 0
arg_formatted times 11 db ' '

; Parse la commande saisie dans le buffer clavier
format_cmd_name:
    mov esi, kbd_buffer
    mov edi, formatted_cmd
    mov ecx, 11
    mov al, ' '
    rep stosb       ; Remplir de nom de commande avec des espaces
    
    mov esi, kbd_buffer
    mov edi, formatted_cmd
    mov ecx, 8      ; Max 8 caractères pour le nom du programme
.loop_nom:
    lodsb
    cmp al, 0
    je .no_args     ; S'il n'y a plus de lettres, on stoppe net ! Il n'y a aucun argument.
    cmp al, ' '
    je .done_name
    ; Majuscules
    cmp al, 'a'
    jl .store
    cmp al, 'z'
    jg .store
    sub al, 32
.store:
    stosb
    loop .loop_nom
.done_name:
    ; Recherche des arguments
.skip_spaces:
    mov al, [esi]
    cmp al, 0
    je .no_args
    cmp al, ' '
    jne .args_start
    inc esi
    jmp .skip_spaces
.args_start:
    mov [cmd_args_ptr], esi
    ret
.no_args:
    mov dword [cmd_args_ptr], empty_string
    ret

search_and_execute:
    call format_cmd_name
    
    ; Vérifie si la commande est vide
    cmp byte [formatted_cmd], ' '
    je .end
    
    ; Commande interne : CD
    pusha
    mov esi, formatted_cmd
    mov edi, cmd_cd
    mov ecx, 11
    repe cmpsb
    popa
    jne .not_cd
    call builtin_cd
    ret
.not_cd:

    ; --- Recherche d'exécutable ---
    ; La logique est : 1. Chercher dans le dossier courant. 2. Si non trouvé, chercher dans /BIN.

    ; 1. Recherche dans le dossier courant
    cld                         ; Assurer que le Direction Flag est à 0 pour `repe cmpsb`
    mov eax, [current_dir_lba]
    mov edi, buffer_lecture
    call ata_read_sector
    
    mov esi, buffer_lecture
    mov edx, 16
.search_current_dir_loop:
    cmp byte [esi], 0
    je .search_in_bin           ; Fin du dossier, on passe à la recherche dans /BIN
    cmp byte [esi], 0xE5
    je .next_in_current         ; Entrée supprimée, on passe à la suivante
    
    pusha
    mov edi, formatted_cmd
    mov ecx, 11
    repe cmpsb
    popa
    je .found                   ; Trouvé !

.next_in_current:
    add esi, 32
    dec edx
    jnz .search_current_dir_loop

.search_in_bin:
    ; 2. Recherche dans /BIN (notre "PATH" système)
    mov eax, [fat_data_lba]
    inc eax                     ; LBA du cluster 3 (/BIN)
    mov edi, buffer_lecture
    call ata_read_sector
    
    mov esi, buffer_lecture
    mov edx, 16
.search_bin_loop:
    cmp byte [esi], 0
    je .not_found               ; Fin du dossier /BIN, commande non trouvée
    cmp byte [esi], 0xE5
    je .next_in_bin             ; Entrée supprimée
    
    pusha
    mov edi, formatted_cmd
    mov ecx, 11
    repe cmpsb
    popa
    je .found                   ; Trouvé !

.next_in_bin:
    add esi, 32
    dec edx
    jnz .search_bin_loop

.not_found:
    mov eax, 2
    mov ebx, msg_not_found
    int 0x80
.end:
    ret
    
.found:
    movzx ebx, word [esi + 26] ; Récupère le cluster du fichier (Devrait être 4)
    
    ; Calcule le LBA (fat_data_lba + (cluster - 2))
    mov eax, [fat_data_lba]
    add eax, ebx
    sub eax, 2
    
    ; Charge l'exécutable à l'adresse 0x200000 (2 Mo)
    mov edi, 0x200000
    call ata_read_sector
    jc .not_found           ; Si la lecture échoue, on n'exécute pas le vide !
    
    ; Exécute le programme chargé !
    mov edx, [cmd_args_ptr] ; Le registre EDX pointe sur les arguments (jusqu'à 256 char)
    call 0x200000           ; Saut vers l'exécutable
    ret

builtin_cd:
    mov esi, [cmd_args_ptr]
    cmp byte [esi], 0
    je .goto_root
    
    ; Format argument
    mov edi, arg_formatted
    mov ecx, 11
    mov al, ' '
    rep stosb
    
    mov esi, [cmd_args_ptr]
    mov edi, arg_formatted
    mov ecx, 11
.format_arg_loop:
    lodsb
    cmp al, 0
    je .search_dir
    cmp al, ' '
    je .search_dir
    cmp al, 'a'
    jl .store_arg
    cmp al, 'z'
    jg .store_arg
    sub al, 32
.store_arg:
    stosb
    loop .format_arg_loop
    
.search_dir:
    mov eax, [current_dir_lba]
    mov edi, buffer_lecture
    call ata_read_sector
    
    mov esi, buffer_lecture
    mov edx, 16
.search_loop:
    cmp byte [esi], 0
    je .not_found
    
    pusha
    mov edi, arg_formatted
    mov ecx, 11
    repe cmpsb
    popa
    je .found
    
    add esi, 32
    dec edx
    jnz .search_loop
    
.not_found:
    mov eax, 2
    mov ebx, msg_dir_not_found
    int 0x80
    ret
    
.found:
    test byte [esi+11], 0x10
    jz .not_a_dir
    
    movzx ebx, word [esi+26]
    cmp ebx, 0
    je .goto_root
    
    mov eax, [fat_data_lba]
    add eax, ebx
    sub eax, 2
    mov [current_dir_lba], eax
    mov [current_dir_cluster], ebx
    ret
    
.goto_root:
    mov eax, [fat_root_dir_lba]
    mov [current_dir_lba], eax
    mov dword [current_dir_cluster], 0
    ret
    
.not_a_dir:
    mov eax, 2
    mov ebx, msg_not_a_dir
    int 0x80
    ret

; On remplit l'image pour atteindre exactement 1.44 Mo (2880 secteurs au total, dont 1 secteur de boot)
; Cela évite que QEMU lève une erreur si on écrit au-delà de la fin réelle du fichier os.img !
times (2879 * 512) - ($ - $$) db 0[bits 32]
[org 0x200000] ; L'OS chargera toujours les programmes à 2 Mo en RAM

start:
    ; 1. Vérifier si un argument est passé
    mov al, [edx]
    cmp al, 0
    je .no_args

    ; 2. Formater l'argument (nom de fichier FAT de 11 char)
    mov esi, edx
    mov edi, arg_formatted
    mov ecx, 11
    mov al, ' '
    rep stosb           ; On remplit de 11 espaces

    mov esi, edx
    mov edi, arg_formatted
    mov ecx, 11
.format_loop:
    lodsb
    cmp al, 0
    je .do_search
    ; Majuscules
    cmp al, 'a'
    jl .store
    cmp al, 'z'
    jg .store
    sub al, 32
.store:
    stosb
    loop .format_loop

.do_search:
    ; 3. Obtenir le répertoire courant
    mov eax, 5        ; Syscall 5: Get Dir LBA
    int 0x80
    mov [dir_lba], eax
    
    ; 4. Lire le secteur du répertoire en mémoire (Buffer externe à 0x210000)
    mov ebx, eax
    mov ecx, 0x210000
    mov eax, 4        ; Syscall 4: Read Sector
    int 0x80
    
    ; 5. Chercher le fichier
    mov esi, 0x210000
    mov edx, 16       ; 16 entrées maximum par secteur
.search_loop:
    cmp byte [esi], 0
    je .not_found
    cmp byte [esi], 0xE5 ; Fichier déjà supprimé
    je .next_entry
    
    pusha
    mov edi, arg_formatted
    mov ecx, 11
    repe cmpsb
    popa
    je .found
    
.next_entry:
    add esi, 32
    dec edx
    jnz .search_loop

.not_found:
    mov eax, 2
    mov ebx, msg_not_found
    int 0x80
    jmp .exit

.found:
    ; 6. Marquer comme supprimé (Norme FAT : 1er caractère devient 0xE5)
    mov byte [esi], 0xE5
    
    ; 7. Sauvegarder le secteur modifié sur le disque
    mov ebx, [dir_lba]
    mov ecx, 0x210000
    mov eax, 6        ; Syscall 6: Write Sector
    int 0x80
    
    mov eax, 2
    mov ebx, msg_success
    int 0x80

.exit:
    mov eax, 3        ; Syscall 3: Exit
    int 0x80

.no_args:
    mov eax, 2
    mov ebx, msg_usage
    int 0x80
    jmp .exit

msg_usage db "Utilisation: RM <fichier/dossier>", 10, 0
msg_not_found db "Fichier ou dossier introuvable", 10, 0
msg_success db "Supprime avec succes !", 10, 0
dir_lba dd 0
arg_formatted times 11 db ' '

; On s'assure que l'exécutable occupe exactement 1 secteur de 512 octets
times 512 - ($ - $$) db 0