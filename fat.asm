[bits 32]

; Structures en mémoire pour le système de fichiers
fat_bpb_buffer times 512 db 0

fat_root_dir_lba dd 0
fat_data_lba dd 0
fat_fat1_lba dd 0
fat_fat2_lba dd 0

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