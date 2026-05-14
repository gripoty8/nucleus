[bits 32]

dernier_caractere db 0

isr_clavier:
    pusha
    in al, 0x60             ; Lecture du port de données du clavier (0x60)
    
    test al, 0x80           ; Vérifie si c'est un "Break Code" (Touche relâchée)
    jnz .fin                ; Si oui, on l'ignore
    
    ; Conversion en caractère ASCII
    call scancode_vers_ascii
    mov [dernier_caractere], al
    
    ; Si le caractère est nul, on l'ignore (Shift, Ctrl, etc.)
    cmp al, 0
    je .fin
    
    ; On exploite notre Interruption Système pour demander l'affichage du caractère
    mov bl, al
    mov eax, 1              ; Fonction 1: Afficher un caractère (bl = char)
    int 0x80

.fin:
    mov al, 0x20            ; End Of Interrupt (EOI)
    out 0x20, al            ; Envoi au PIC
    popa
    iret

scancode_vers_ascii:
    and eax, 0xFF           ; Nettoyage du reste du registre EAX
    cmp eax, 0x39           ; Limite de la table
    ja .inconnu
    mov ebx, table_azerty
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