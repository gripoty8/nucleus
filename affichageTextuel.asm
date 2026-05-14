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
    ret