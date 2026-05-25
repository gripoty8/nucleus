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
    jmp .exit

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
    mov [fat1_lba], ecx       ; Nouveau : LBA de la table FAT1

    ; Lire le secteur du répertoire en mémoire (Buffer à 0x211000)
    mov ebx, [dir_lba]
    mov ecx, 0x211000
    mov eax, 4        ; Syscall 4: Read Sector
    int 0x80
    
    cld
    mov dword [free_entry], 0
    mov esi, 0x211000
    mov edx, 16       ; Le répertoire prend 1 secteur (512 octets / 32 = 16 entrées max)

.scan_loop:
    mov al, [esi]
    cmp al, 0         ; 0x00 = Entrée jamais utilisée
    je .is_free
    cmp al, 0xE5      ; 0xE5 = Fichier supprimé
    je .is_free
    
    ; C'est un fichier valide : on vérifie s'il porte déjà le même nom (Doublon)
    pusha
    mov edi, arg_formatted
    mov ecx, 11
    repe cmpsb
    popa
    je .duplicate_found
    
    jmp .next_entry
    
.is_free:
    ; Si c'est la première entrée libre qu'on croise, on sauvegarde son adresse
    cmp dword [free_entry], 0
    jne .next_entry
    mov [free_entry], esi
    
.next_entry:
    add esi, 32
    dec edx
    jnz .scan_loop
    
    ; Vérifier si on a bien trouvé une entrée libre
    cmp dword [free_entry], 0
    jne .find_free_cluster
    
    mov eax, 2
    mov ebx, msg_full
    int 0x80
    jmp .exit
    
.duplicate_found:
    mov eax, 2
    mov ebx, msg_dup
    int 0x80
    jmp .exit

.find_free_cluster:
    ; Lire la table FAT1 pour trouver le premier cluster reellement libre.
    ; L'ancienne methode (max cluster du repertoire courant) ignorait les
    ; fichiers dans les sous-dossiers (ex: LS/RM/NANO/CF dans /BIN) et
    ; ecrasait leurs donnees sur disque.
    mov ebx, [fat1_lba]
    mov ecx, 0x212000
    mov eax, 4        ; Syscall 4: Read Sector
    int 0x80
    
    ; Chaque entree FAT16 fait 2 octets. Les clusters 0 et 1 sont reserves.
    ; On commence donc a l'offset 4 (cluster 2).
    mov esi, 0x212000 + 4
    mov ecx, 2        ; Index du cluster courant (commence a 2)
.fat_scan:
    mov ax, [esi]
    cmp ax, 0         ; 0x0000 = cluster libre
    je .cluster_found
    add esi, 2
    inc ecx
    cmp ecx, 256      ; Securite : 256 clusters max par secteur FAT16
    jl .fat_scan
    
    ; Aucun cluster libre trouve dans ce secteur FAT
    mov eax, 2
    mov ebx, msg_full
    int 0x80
    jmp .exit

.cluster_found:
    mov [new_cluster], ecx

.create_entry:
    
    ; Remplir l'entrée de répertoire
    mov edi, [free_entry]
    
    push edi
    mov ecx, 32
    mov al, 0
    rep stosb         ; On initialise proprement les 32 octets à 0
    pop edi
    
    mov esi, arg_formatted
    push edi
    mov ecx, 11
    rep movsb         ; Nom du fichier (11 octets)
    pop edi
    
    mov byte [edi + 11], 0x20       ; Attribut: 0x20 (Fichier Archive)
    
    mov eax, [new_cluster]
    mov word [edi + 26], ax         ; Cluster (2 octets)
    mov dword [edi + 28], 0         ; Taille du fichier = 0 octet
    
    ; Sauvegarder le répertoire mis à jour sur le disque
    mov ebx, [dir_lba]
    mov ecx, 0x211000
    mov eax, 6        ; Syscall 6: Write Sector
    int 0x80
    
    ; Formater le secteur du fichier avec des zéros
    mov eax, [new_cluster]
    mov ebx, [fat_data_lba]
    add ebx, eax
    sub ebx, 2
    mov [file_lba], ebx
    
    mov edi, 0x212000
    mov ecx, 512
    mov al, 0
    rep stosb
    
    mov ebx, [file_lba]
    mov ecx, 0x212000
    mov eax, 6        ; Syscall 6: Write Sector
    int 0x80
    
    ; Message de succès
    mov eax, 2
    mov ebx, msg_success
    int 0x80
    
.exit:
    mov eax, 3        ; Syscall 3: Exit (Retour au Shell)
    int 0x80

; --- Section de Données ---
msg_usage     db "Utilisation: CF <nom_fichier>", 10, 0
msg_full      db "Erreur: Le repertoire est plein.", 10, 0
msg_dup       db "Erreur: Un fichier porte deja ce nom.", 10, 0
msg_success   db "Fichier cree avec succes.", 10, 0

dir_lba       dd 0
fat_data_lba  dd 0
fat1_lba      dd 0
file_lba      dd 0
free_entry    dd 0
new_cluster   dd 0
arg_formatted times 11 db ' '

; On s'assure que l'exécutable occupe exactement 2 secteurs de 512 octets
times 1024 - ($ - $$) db 0
