[bits 32]
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
times 1024 - ($ - $$) db 0