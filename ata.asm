[bits 32]

; Lit 1 secteur (512 octets) depuis le disque
; EAX = Adresse LBA (Logical Block Address) du secteur
; EDI = Adresse en mémoire où stocker les données lues
ata_read_sector:
    pusha
    mov ebx, eax
    mov dx, 0x1F7
.wait1:
    in al, dx
    test al, 0x80           ; Attend que le bit BSY (Busy) soit à 0
    jnz .wait1

    mov dx, 0x1F2
    mov al, 1
    out dx, al              ; Nombre de secteurs = 1

    ; Envoi de l'adresse LBA (28 bits) sur les différents ports
    mov dx, 0x1F3
    mov eax, ebx
    out dx, al              ; LBA low
    mov dx, 0x1F4
    mov al, ah
    out dx, al              ; LBA mid
    mov dx, 0x1F5
    shr eax, 16
    out dx, al              ; LBA high
    mov dx, 0x1F6
    shr eax, 8
    and al, 0x0F
    or al, 0xE0             ; Mode LBA (0x40) + Drive Master (0xA0) -> 0xE0
    out dx, al              ; LBA highest nibble + drive

    mov dx, 0x1F7
    mov al, 0x20
    out dx, al              ; Commande : Lecture de secteur(s)

.wait2:
    in al, dx
    test al, 8              ; Attend que le bit DRQ (Data Request) soit à 1
    jz .wait2

    mov dx, 0x1F0
    mov ecx, 256            ; 256 mots de 16 bits = 512 octets
    rep insw                ; Lecture des données vers [EDI]

    popa
    ret

; Écrit 1 secteur (512 octets) sur le disque
; EAX = Adresse LBA (Logical Block Address) du secteur
; ESI = Adresse en mémoire d'où lire les données à écrire
ata_write_sector:
    ; L'implémentation d'écriture suit la même logique matérielle que la lecture
    ; (Non implémentée entièrement ici pour garder le code concis, 
    ; mais utilise la commande 0x30 sur 0x1F7 et l'instruction 'rep outsw' vers 0x1F0)
    ret