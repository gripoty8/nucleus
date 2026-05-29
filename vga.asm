[bits 32]
[org 0x200000]

start:
    ; 1. Passer en mode VGA 320x200 256 couleurs (Syscall 9)
    mov eax, 9
    int 0x80

    ; 2. Configurer la palette : index 40 = Rouge Pur
    mov dx, 0x3C8
    mov al, 40
    out dx, al
    mov dx, 0x3C9
    mov al, 63   ; Rouge
    out dx, al
    mov al, 0    ; Vert
    out dx, al
    mov al, 0    ; Bleu
    out dx, al
    
    ; Synchronisation VGA pour éviter de bloquer le bus
    mov dx, 0x03DA
    in al, dx

    ; 3. Fond noir (Remplissage rapide)
    mov edi, 0xA0000
    mov ecx, 320 * 200 / 4
    xor eax, eax
    rep stosd

    ; 4. Dessiner le carré rouge (20x20)
    ; Dessiner le carré rouge (20x20)
    mov ebx, 0             ; ebx servira de compteur de ligne (0 à 19)
.draw_loop:
    push ebx               ; On sauvegarde le compteur de ligne

    ; --- Calcul : EDI = 0xA0000 + (Y * 320) + X ---
    mov eax, 90            ; Y de départ
    add eax, ebx           ; Ajoute le numéro de ligne actuelle
    mov ecx, 320
    mul ecx                ; EAX = (90 + ebx) * 320
    add eax, 150           ; Ajoute X (150)
    
    mov edi, 0xA0000
    add edi, eax           ; EDI est maintenant parfaitement positionné

    mov ecx, 20            ; Largeur de 20 pixels
    mov al, 40             ; Couleur
    rep stosb              ; On dessine la ligne
    
    pop ebx                ; On récupère le compteur
    inc ebx                ; Ligne suivante
    cmp ebx, 20            ; Est-ce qu'on a fait 20 lignes ?
    jne .draw_loop         ; Sinon, on recommence

    ; 5. Attendre une touche (Syscall 8)
    mov eax, 8
    int 0x80

    ; 6. Revenir en mode texte (Syscall 10)
    mov eax, 10
    int 0x80

    ; 7. Quitter le programme (Syscall 3)
    mov eax, 3
    int 0x80

times 512 - ($ - $$) db 0