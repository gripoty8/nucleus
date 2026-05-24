[bits 32]
[org 0x1000]


start:
    call init_affichage     ; 1. Driver vidéo : Effacer l'écran
    call init_idt           ; 2. Driver IDT & PIC & Clavier
    call fat_init           ; 3. Initialiser le FileSystem (FAT) via ATA

    ; 3. Utilisation de la table d'interruption pour demander un affichage texte (EAX=2, EBX=adresse)
    mov eax, 2
    mov ebx, msg
    int 0x80

    ; --- VÉRIFICATION DE PREMIER DÉMARRAGE ---
    ; On lit le Root Directory pour voir s'il est déjà initialisé
    mov eax, [fat_root_dir_lba]
    mov edi, buffer_lecture
    call ata_read_sector
    
    cmp byte [buffer_lecture], 0    ; Le premier octet est 0 si le disque est vierge
    jne skip_init                   ; Si ce n'est pas 0, on conserve les données !

    ; 1. Création dynamique d'un fichier avec nos propres paramètres
    mov esi, nom_mon_fichier
    mov edi, contenu_mon_fichier
    mov ecx, taille_mon_fichier
    call fat_create_file
    
    ; 2. Création du dossier BIN et des programmes dans le FileSystem
    call fat_setup_bin_dir

skip_init:

shell_loop_start:
    mov esp, 0x90000        ; Réinitialisation ABSOLUE de la pile (évite tout crash ou fuite !)
    mov eax, 2
    mov ebx, prompt_msg
    int 0x80
    
    ; Vidage complet du buffer clavier pour éviter les restes d'arguments (Fantômes)
    mov edi, kbd_buffer
    mov ecx, 256
    mov al, 0
    rep stosb

    mov dword [kbd_buffer_idx], 0
    mov byte [kbd_enter_pressed], 0

shell_wait:
    cmp byte [kbd_enter_pressed], 1
    je process_cmd
    hlt
    jmp shell_wait
    
process_cmd:
    call search_and_execute
    jmp shell_loop_start


%include "idt.asm"
%include "clavier.asm"

%include "affichageTextuel.asm"
%include "ata.asm"
%include "fat.asm"

msg db "Systeme amorce !", 10, "Mode d'affichage VGA : OK", 10, "Pilote Clavier IRQ1 : OK", 10, "Pilote Disque ATA & FAT : OK", 10, "Tapez une touche...", 10, 0

nom_mon_fichier db "FICHIER TXT"  ; Nom (8 cars) + Espace + Extension (3 cars) = 11 pile !
contenu_mon_fichier db "Contenu du fichier cree dynamiquement avec la taille ajustee !", 10, 0
taille_mon_fichier equ $ - contenu_mon_fichier

prompt_msg db "NUCLEUS> ", 0
msg_not_found db "Commande introuvable", 10, 0
empty_string db 0
formatted_cmd times 11 db ' '
cmd_args_ptr dd 0
cmd_cd db "CD         "
msg_dir_not_found db "Dossier introuvable", 10, 0
msg_not_a_dir db "Ce n'est pas un dossier", 10, 0
arg_formatted times 11 db ' '

; Parse la commande saisie dans le buffer clavier
format_cmd_name:
    mov esi, kbd_buffer
    mov edi, formatted_cmd
    mov ecx, 11
    mov al, ' '
    rep stosb       ; Remplir de nom de commande avec des espaces
    
    mov esi, kbd_buffer
    mov edi, formatted_cmd
    mov ecx, 8      ; Max 8 caractères pour le nom du programme
.loop_nom:
    lodsb
    cmp al, 0
    je .no_args     ; S'il n'y a plus de lettres, on stoppe net ! Il n'y a aucun argument.
    cmp al, ' '
    je .done_name
    ; Majuscules
    cmp al, 'a'
    jl .store
    cmp al, 'z'
    jg .store
    sub al, 32
.store:
    stosb
    loop .loop_nom
.done_name:
    ; Recherche des arguments
.skip_spaces:
    mov al, [esi]
    cmp al, 0
    je .no_args
    cmp al, ' '
    jne .args_start
    inc esi
    jmp .skip_spaces
.args_start:
    mov [cmd_args_ptr], esi
    ret
.no_args:
    mov dword [cmd_args_ptr], empty_string
    ret

search_and_execute:
    call format_cmd_name
    
    ; Vérifie si la commande est vide
    cmp byte [formatted_cmd], ' '
    je .end
    
    ; Commande interne : CD
    pusha
    mov esi, formatted_cmd
    mov edi, cmd_cd
    mov ecx, 11
    repe cmpsb
    popa
    jne .not_cd
    call builtin_cd
    ret
.not_cd:

    ; Lire le dossier BIN (Cluster 3 = LBA fat_data_lba + 1)
    mov eax, [fat_data_lba]
    inc eax
    mov edi, buffer_lecture
    call ata_read_sector
    
    mov esi, buffer_lecture
    mov edx, 16
.search_loop:
    cmp byte [esi], 0
    je .not_found
    
    pusha
    mov edi, formatted_cmd
    mov ecx, 11
    repe cmpsb
    popa
    je .found
    
    add esi, 32
    dec edx
    jnz .search_loop
    
.not_found:
    mov eax, 2
    mov ebx, msg_not_found
    int 0x80
.end:
    ret
    
.found:
    movzx ebx, word [esi + 26] ; Récupère le cluster du fichier (Devrait être 4)
    
    ; Calcule le LBA (fat_data_lba + (cluster - 2))
    mov eax, [fat_data_lba]
    add eax, ebx
    sub eax, 2
    
    ; Charge l'exécutable à l'adresse 0x200000 (2 Mo)
    mov edi, 0x200000
    call ata_read_sector
    jc .not_found           ; Si la lecture échoue, on n'exécute pas le vide !
    
    ; Exécute le programme chargé !
    mov edx, [cmd_args_ptr] ; Le registre EDX pointe sur les arguments (jusqu'à 256 char)
    call 0x200000           ; Saut vers l'exécutable
    ret

builtin_cd:
    mov esi, [cmd_args_ptr]
    cmp byte [esi], 0
    je .goto_root
    
    ; Format argument
    mov edi, arg_formatted
    mov ecx, 11
    mov al, ' '
    rep stosb
    
    mov esi, [cmd_args_ptr]
    mov edi, arg_formatted
    mov ecx, 11
.format_arg_loop:
    lodsb
    cmp al, 0
    je .search_dir
    cmp al, ' '
    je .search_dir
    cmp al, 'a'
    jl .store_arg
    cmp al, 'z'
    jg .store_arg
    sub al, 32
.store_arg:
    stosb
    loop .format_arg_loop
    
.search_dir:
    mov eax, [current_dir_lba]
    mov edi, buffer_lecture
    call ata_read_sector
    
    mov esi, buffer_lecture
    mov edx, 16
.search_loop:
    cmp byte [esi], 0
    je .not_found
    
    pusha
    mov edi, arg_formatted
    mov ecx, 11
    repe cmpsb
    popa
    je .found
    
    add esi, 32
    dec edx
    jnz .search_loop
    
.not_found:
    mov eax, 2
    mov ebx, msg_dir_not_found
    int 0x80
    ret
    
.found:
    test byte [esi+11], 0x10
    jz .not_a_dir
    
    movzx ebx, word [esi+26]
    cmp ebx, 0
    je .goto_root
    
    mov eax, [fat_data_lba]
    add eax, ebx
    sub eax, 2
    mov [current_dir_lba], eax
    mov [current_dir_cluster], ebx
    ret
    
.goto_root:
    mov eax, [fat_root_dir_lba]
    mov [current_dir_lba], eax
    mov dword [current_dir_cluster], 0
    ret
    
.not_a_dir:
    mov eax, 2
    mov ebx, msg_not_a_dir
    int 0x80
    ret

; On remplit l'image pour atteindre exactement 1.44 Mo (2880 secteurs au total, dont 1 secteur de boot)
; Cela évite que QEMU lève une erreur si on écrit au-delà de la fin réelle du fichier os.img !
times (2879 * 512) - ($ - $$) db 0