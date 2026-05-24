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
lisezmoi_size equ $ - lisezmoi_data