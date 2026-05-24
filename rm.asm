[bits 32]
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