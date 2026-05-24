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
    times 128 - ($ - table_azerty_shift) db 0