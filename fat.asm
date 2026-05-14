[bits 32]

; Structures en mémoire pour le système de fichiers
fat_bpb_buffer times 512 db 0

fat_root_dir_lba dd 0
fat_data_lba dd 0

; Initialise la FAT en lisant le secteur 0 (assumé comme Boot Sector / VBR non partitionné)
fat_init:
    pusha
    
    mov eax, 0                      ; Secteur LBA 0
    mov edi, fat_bpb_buffer
    call ata_read_sector            ; Appel au pilote matériel

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

; --- DONNEES DE TEST POUR LECTURE / ECRITURE ---
donnees_test db "SUCCESS: Lecture et Ecriture depuis le disque FAT via ATA !", 10, 0
times 512 - ($ - donnees_test) db 0 ; Remplissage pour faire 512 octets pile

buffer_lecture times 512 db 0

; Test : Écriture du secteur de test au début de la zone de données FAT
fat_test_write:
    pusha
    mov eax, [fat_data_lba]     ; LBA du début des données FAT
    mov esi, donnees_test       ; Adresse des données à écrire (ESI pour outsw)
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