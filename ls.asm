[bits 32]
[org 0x200000] ; L'OS chargera toujours les programmes à 2 Mo en RAM

start:
    ; 1. Afficher les arguments si présents (EDX pointe sur la chaine d'arguments)
    mov al, [edx]
    cmp al, 0
    je .no_args
    
    mov eax, 2
    mov ebx, msg_args
    int 0x80
    mov eax, 2
    mov ebx, edx
    int 0x80
    mov bl, 10
    mov eax, 1
    int 0x80
.no_args:

    ; 2. Demander à l'OS le LBA du Root Directory
    mov eax, 5        ; Syscall 5: Get Root Dir
    int 0x80
    mov ebx, eax      ; On place le LBA pour la lecture
    
    ; 3. Demander à l'OS de lire le secteur en mémoire (à 0x210000)
    mov ecx, 0x210000
    mov eax, 4        ; Syscall 4: Read Sector
    int 0x80
    
    ; 4. Parcourir et afficher le contenu
    mov esi, 0x210000
    mov edx, 16       ; 16 entrées maximum dans le secteur
.loop:
    mov al, [esi]
    cmp al, 0         ; Fin du répertoire
    je .done
    cmp al, 0xE5      ; Fichier supprimé
    je .next
    
    ; Ignorer les LFN (0x0F) et le Volume Label (0x08)
    mov al, [esi + 11]
    cmp al, 0x0F
    je .next
    test al, 0x08
    jnz .next
    
    ; Afficher le nom du fichier (8 caractères maximum)
    pusha
    mov ecx, 8
    mov edi, esi
.print_name:
    mov bl, [edi]
    cmp bl, ' '
    je .check_ext
    mov eax, 1
    int 0x80
    inc edi
    loop .print_name
    
.check_ext:
    ; Ajouter l'extension s'il y en a une
    mov bl, [esi + 8]
    cmp bl, ' '
    je .check_dir
    
    mov bl, '.'
    mov eax, 1
    int 0x80
    
    mov ecx, 3
    mov edi, esi
    add edi, 8
.print_ext:
    mov bl, [edi]
    cmp bl, ' '
    je .check_dir
    mov eax, 1
    int 0x80
    inc edi
    loop .print_ext

.check_dir:
    ; Ajouter un slash si l'entrée est un répertoire
    mov al, [esi + 11]
    test al, 0x10
    jz .end_print
    
    mov bl, '/'
    mov eax, 1
    int 0x80

.end_print:
    ; Retour à la ligne
    mov bl, 10
    mov eax, 1
    int 0x80
    popa
    
.next:
    add esi, 32
    dec edx
    jnz .loop
    
.done:
    mov eax, 3        ; Syscall 3: Exit (Retourne au Shell de l'OS)
    int 0x80

msg_args db "Arguments passes : ", 0

; On s'assure que l'exécutable occupe exactement 1 secteur de 512 octets
times 512 - ($ - $$) db 0