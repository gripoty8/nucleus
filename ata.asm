[bits 32]

; Lit 1 secteur (512 octets) depuis le disque en mode LBA28
; IN: EAX = Adresse LBA du secteur
;     EDI = Adresse mémoire de destination
ata_read_sector:
    pusha
    mov ebx, eax            ; Sauvegarde LBA

    ; Attendre que le disque soit prêt (BSY=0 et DRDY=1)
    mov dx, 0x1F7
.wait_ready:
    in al, dx
    and al, 0xC0
    cmp al, 0x40
    jne .wait_ready

    ; --- Configuration de la lecture ---
    mov dx, 0x1F2
    mov al, 1
    out dx, al              ; Nombre de secteurs à lire: 1

    ; Envoyer l'adresse LBA (28 bits)
    mov eax, ebx            ; Récupère LBA
    mov dx, 0x1F3
    out dx, al              ; LBA bits 0-7
    shr eax, 8
    mov dx, 0x1F4
    out dx, al              ; LBA bits 8-15
    shr eax, 8
    mov dx, 0x1F5
    out dx, al              ; LBA bits 16-23
    shr eax, 8
    mov dx, 0x1F6
    and al, 0x0F            ; Garde seulement les bits 24-27
    or al, 0xE0             ; Mode LBA + disque maître
    out dx, al

    ; Envoyer la commande de lecture
    mov dx, 0x1F7
    mov al, 0x20
    out dx, al              ; Commande: READ SECTOR(S)

    ; Attendre que le disque ait des données prêtes (DRQ=1)
.wait_drq:
    in al, dx
    test al, 1              ; Vérifier le bit d'erreur
    jnz .error
    test al, 8              ; Attendre le bit DRQ
    jz .wait_drq

    ; Lire les données depuis le port
    mov dx, 0x1F0
    mov ecx, 256            ; 256 mots de 16-bit = 512 octets
    rep insw                ; Copie les données du port vers [EDI]

.error:
    popa
    ret

; Écrit 1 secteur (512 octets) sur le disque en mode LBA28
; IN: EAX = Adresse LBA du secteur
;     ESI = Adresse mémoire source
ata_write_sector:
    pusha
    mov ebx, eax            ; Sauvegarde LBA

    ; Attendre que le disque soit prêt (BSY=0 et DRDY=1)
    mov dx, 0x1F7
.wait_ready:
    in al, dx
    and al, 0xC0
    cmp al, 0x40
    jne .wait_ready

    ; --- Configuration de l'écriture ---
    mov dx, 0x1F2
    mov al, 1
    out dx, al              ; Nombre de secteurs à écrire: 1

    ; Envoyer l'adresse LBA (28 bits)
    mov eax, ebx            ; Récupère LBA
    mov dx, 0x1F3
    out dx, al              ; LBA bits 0-7
    shr eax, 8
    mov dx, 0x1F4
    out dx, al              ; LBA bits 8-15
    shr eax, 8
    mov dx, 0x1F5
    out dx, al              ; LBA bits 16-23
    shr eax, 8
    mov dx, 0x1F6
    and al, 0x0F            ; Garde seulement les bits 24-27
    or al, 0xE0             ; Mode LBA + disque maître
    out dx, al

    ; Envoyer la commande d'écriture
    mov dx, 0x1F7
    mov al, 0x30
    out dx, al              ; Commande: WRITE SECTOR(S)

    ; Attendre que le disque soit prêt à recevoir les données (DRQ=1)
.wait_drq:
    in al, dx
    test al, 1              ; Vérifier le bit d'erreur
    jnz .error
    test al, 8              ; Attendre le bit DRQ
    jz .wait_drq

    ; Écrire les données sur le port
    mov dx, 0x1F0
    mov ecx, 256            ; 256 mots de 16-bit = 512 octets
    rep outsw               ; Copie les données de [ESI] vers le port

    ; Forcer l'écriture physique depuis le cache du disque
    mov dx, 0x1F7
    mov al, 0xE7            ; Commande: FLUSH CACHE
    out dx, al

    ; Attendre la fin du flush (BSY=0)
.wait_flush:
    in al, dx
    test al, 0x80
    jnz .wait_flush

    ; Succès de l'écriture : on sort de la fonction sans exécuter l'erreur
    popa
    ret

.error:
    mov eax, 2
    mov ebx, msgErreur
    int 0x80
    popa
    ret

msgErreur db "Erreur materielle",0