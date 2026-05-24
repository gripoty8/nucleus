[bits 32]

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

; --- STRUCTURES FAT POUR VISIBILITÉ DEPUIS LINUX ---
fat_table_buffer:
    dw 0xFFF0       ; Cluster 0 : Type de média
    dw 0xFFFF       ; Cluster 1 : Réservé
    dw 0xFFFF       ; Cluster 2 : Marqueur de Fin de Fichier (EOF) pour notre test
    times 512 - ($ - fat_table_buffer) db 0

root_dir_buffer:
    times 11 db 0x20    ; Nom du fichier (11 caractères, initialisé à des espaces)
    db 0x20             ; Attribut: Archive
    times 10 db 0       ; Réservé
    dw 0                ; Heure de dernière modification
    dw 0                ; Date de dernière modification
    dw 2                ; Premier cluster (Cluster 2 = début des données)
    dd 0                ; Taille du fichier en octets (sera remplie dynamiquement)
    times 512 - ($ - root_dir_buffer) db 0

; Crée un fichier dans le répertoire racine
; IN: ESI = Pointeur vers le nom (11 caractères FAT)
;     EDI = Pointeur vers les données (max 512 octets pour l'instant)
;     ECX = Taille réelle du fichier en octets
fat_create_file:
    pusha
    
    ; 1. Inscrire dynamiquement le Nom et la Taille dans le buffer du répertoire
    push edi                ; On sauvegarde notre pointeur de données
    push esi                ; On sauvegarde notre pointeur de nom
    mov edi, root_dir_buffer
    push ecx
    mov ecx, 11
    rep movsb               ; Copie de la chaîne pointée par ESI vers EDI
    pop ecx
    mov [root_dir_buffer + 28], ecx  ; On enregistre la taille réelle à l'offset 28
    pop esi
    pop edi

    ; 2. Écrire le contenu des données physiquement sur le disque
    mov eax, [fat_data_lba]     ; LBA du début des données FAT
    mov esi, edi                ; Le pilote ATA lit ESI, on lui donne donc notre pointeur EDI
    call ata_write_sector
    
    ; 3. Mettre à jour la Table d'Allocation 1 et 2
    mov eax, [fat_fat1_lba]
    mov esi, fat_table_buffer
    call ata_write_sector
    mov eax, [fat_fat2_lba]
    call ata_write_sector
    
    ; 4. Créer le Fichier officiel dans le Répertoire Racine
    mov eax, [fat_root_dir_lba]
    mov esi, root_dir_buffer
    call ata_write_sector
    
    popa
    ret

; Test : Lecture de ce même secteur vers notre buffer vide
fat_test_read:
    pusha
    mov eax, [fat_data_lba]     ; LBA du début des données FAT
    mov edi, buffer_lecture     ; Adresse de destination (EDI pour insw)
    call ata_read_sector
    popa
    ret

; Crée le dossier BIN et ajoute l'exécutable LS
fat_setup_bin_dir:
    pusha
    ; 1. Mise à jour de la table FAT (Clusters 0, 1, 2(FICHIER), 3(BIN), 4(LS), 5(RM))
    mov word [fat_table_buffer], 0xFFF0
    mov word [fat_table_buffer+2], 0xFFFF
    mov word [fat_table_buffer+4], 0xFFFF
    mov word [fat_table_buffer+6], 0xFFFF
    mov word [fat_table_buffer+8], 0xFFFF
    mov word [fat_table_buffer+10], 0xFFFF
    
    mov eax, [fat_fat1_lba]
    mov esi, fat_table_buffer
    call ata_write_sector
    mov eax, [fat_fat2_lba]
    call ata_write_sector
    
    ; 2. Création de l'entrée BIN dans le Root Dir
    mov eax, [fat_root_dir_lba]
    mov edi, buffer_lecture
    call ata_read_sector
    
    mov esi, buffer_lecture
    mov ecx, 16
.find_empty_root:
    cmp byte [esi], 0
    je .found_empty_root
    add esi, 32
    loop .find_empty_root
.found_empty_root:
    mov dword [esi], 'BIN '
    mov dword [esi+4], '    '
    mov dword [esi+8], '   '
    mov byte [esi+11], 0x10 ; Attribut Dossier (Sub-Directory)
    mov word [esi+26], 3    ; Cluster 3
    mov dword [esi+28], 0   ; Taille 0 pour un dossier
    
    mov eax, [fat_root_dir_lba]
    mov esi, buffer_lecture
    call ata_write_sector
    
    ; 3. Initialisation du contenu du dossier BIN (Cluster 3) avec l'entrée LS
    mov edi, buffer_lecture
    mov ecx, 512
    xor al, al
    rep stosb           ; Vider le secteur
    
    mov edi, buffer_lecture
    ; Entrée 1 : "."
    mov dword [edi], '.   '
    mov dword [edi+4], '    '
    mov dword [edi+8], '   '
    mov byte [edi+11], 0x10 ; Attribut Dossier (Sub-Directory)
    mov word [edi+26], 3    ; Cluster 3 (BIN)
    mov dword [edi+28], 0
    
    ; Entrée 2 : ".."
    add edi, 32
    mov dword [edi], '..  '
    mov dword [edi+4], '    '
    mov dword [edi+8], '   '
    mov byte [edi+11], 0x10 ; Attribut Dossier
    mov word [edi+26], 0    ; Cluster 0 (Root)
    mov dword [edi+28], 0
    
    ; Entrée 3 : "LS"
    add edi, 32
    mov dword [edi], 'LS  '
    mov dword [edi+4], '    '
    mov dword [edi+8], '   '
    mov byte [edi+11], 0x20
    mov word [edi+26], 4    ; Cluster 4
    mov eax, ls_program_size
    mov dword [edi+28], eax
    
    ; Entrée 4 : "RM"
    add edi, 32
    mov dword [edi], 'RM  '
    mov dword [edi+4], '    '
    mov dword [edi+8], '   '
    mov byte [edi+11], 0x20
    mov word [edi+26], 5    ; Cluster 5
    mov eax, rm_program_size
    mov dword [edi+28], eax
    
    mov eax, [fat_data_lba]
    inc eax                 ; LBA du Cluster 3 (fat_data_lba + 1)
    mov esi, buffer_lecture
    call ata_write_sector
    
    ; 4. Écriture physique de l'exécutable LS (Cluster 4)
    mov eax, [fat_data_lba]
    add eax, 2              ; LBA du Cluster 4 (fat_data_lba + 2)
    mov esi, ls_program_data
    call ata_write_sector
    
    ; 5. Écriture physique de l'exécutable RM (Cluster 5)
    mov eax, [fat_data_lba]
    add eax, 3              ; LBA du Cluster 5 (fat_data_lba + 3)
    mov esi, rm_program_data
    call ata_write_sector
    
    popa
    ret

ls_program_data:
    incbin "ls.bin"
ls_program_size equ $ - ls_program_data

rm_program_data:
    incbin "rm.bin"
rm_program_size equ $ - rm_program_data