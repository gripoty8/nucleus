[bits 32]

; Lit 1 secteur (512 octets) depuis le disque en mode LBA28
; IN: EAX = Adresse LBA du secteur
;     EDI = Adresse mémoire de destination
ata_read_sector:
    pusha
    cld                     ; Force l'incrémentation de EDI (essentiel pour rep insw)

    mov ebx, eax            ; Sauvegarde LBA AVANT de modifier AL !

    ; Désactiver les interruptions IDE pour utiliser le polling sans crash
    mov dx, 0x3F6
    mov al, 0x02            ; Bit nIEN = 1
    out dx, al

    ; --- Sélection du disque avant lecture du statut ---
    mov dx, 0x1F6
    shr eax, 24
    and al, 0x0F
    or al, 0xE0             ; Disque Maître + LBA
    out dx, al

    ; Délai matériel de 400ns vital pour laisser l'IDE changer de contexte
    mov dx, 0x1F7
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    ; Attendre que le disque soit prêt
.wait_ready:
    in al, dx
    test al, 0x80           ; BSY (Busy) doit être à 0
    jnz .wait_ready
    test al, 1              ; En cas d'erreur fatale, on quitte sans figer
    jnz .error

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

    ; Délai de 400ns
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    ; Attendre que le disque ait des données prêtes (DRQ=1)
.wait_drq:
    in al, dx
    test al, 0x80           ; Le disque est-il occupé (BSY) à chercher les données ?
    jnz .wait_drq           ; Si oui, on attend avant de lire les autres bits !
    test al, 1              ; Vérifier le bit d'erreur
    jnz .error
    test al, 8              ; Attendre le bit DRQ
    jz .wait_drq

    ; Lire les données depuis le port
    mov dx, 0x1F0
    mov ecx, 256            ; 256 mots de 16-bit = 512 octets
    rep insw                ; Copie les données du port vers [EDI]

    popa
    clc                     ; CF = 0 (Succès de la lecture)
    ret

.error:
    popa
    stc                     ; CF = 1 (Erreur de lecture)
    ret

; Écrit 1 secteur (512 octets) sur le disque en mode LBA28
; IN: EAX = Adresse LBA du secteur
;     ESI = Adresse mémoire source
ata_write_sector:
    pusha
    cld                     ; Force l'incrémentation de ESI (essentiel pour rep outsw)

    mov ebx, eax            ; Sauvegarde LBA AVANT de modifier AL !

    ; Désactiver les interruptions IDE
    mov dx, 0x3F6
    mov al, 0x02
    out dx, al

    ; --- Sélection du disque avant lecture du statut ---
    mov dx, 0x1F6
    shr eax, 24
    and al, 0x0F
    or al, 0xE0             ; Disque Maître + LBA
    out dx, al

    ; Délai matériel de 400ns
    mov dx, 0x1F7
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    ; Attendre que le disque soit prêt
.wait_ready:
    in al, dx
    test al, 0x80           ; BSY (Busy) doit être à 0
    jnz .wait_ready
    test al, 1              ; En cas d'erreur fatale, on quitte sans figer
    jnz .error

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

    ; Délai de 400ns
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    ; Attendre que le disque soit prêt à recevoir les données (DRQ=1)
.wait_drq:
    in al, dx
    test al, 0x80           ; Le disque est-il occupé (BSY) ?
    jnz .wait_drq
    test al, 1              ; Vérifier le bit d'erreur
    jnz .error
    test al, 8              ; Attendre le bit DRQ
    jz .wait_drq

    ; Écrire les données sur le port
    mov dx, 0x1F0
    mov ecx, 256            ; 256 mots de 16-bit = 512 octets
    rep outsw               ; Copie les données de [ESI] vers le port

    ; Attendre que le disque soit prêt avant de lancer le cache flush
    mov dx, 0x1F7
.wait_transfer_done:
    in al, dx
    test al, 0x80           ; BSY
    jnz .wait_transfer_done

    ; Forcer l'écriture physique depuis le cache du disque
    mov dx, 0x1F7
    mov al, 0xE7            ; Commande: FLUSH CACHE
    out dx, al

    ; Attendre la fin du flush (BSY=0)
.wait_flush:
    in al, dx
    test al, 0x80
    jnz .wait_flush

    popa
    clc                     ; CF = 0
    ret

.error:
    popa
    stc                     ; CF = 1
    ret