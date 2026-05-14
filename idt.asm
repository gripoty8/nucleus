[bits 32]

; Structure de la table IDT (256 entrées)
idt_start:
    times 256 dq 0
idt_end:

idt_descriptor:
    dw idt_end - idt_start - 1 ; Limite / Taille
    dd idt_start               ; Base (Adresse mémoire)

; Macro simplifiée pour inscrire un handler dans la table IDT
; %1 = Numéro de l'interruption, %2 = Fonction du handler
%macro set_idt_entry 2
    mov eax, %2
    mov ebx, %1
    shl ebx, 3               ; * 8 car chaque entrée fait 8 octets
    add ebx, idt_start
    mov word [ebx], ax       ; Bits 0-15 de l'offset
    mov word [ebx+2], 0x08   ; Sélecteur de code GDT (CODE_SEG)
    mov word [ebx+4], 0x8E00 ; Flags : Present, Ring 0, Interrupt Gate 32b
    shr eax, 16
    mov word [ebx+6], ax     ; Bits 16-31 de l'offset
%endmacro

init_idt:
    ; Initialisation et Remappage du PIC maître et esclave
    ; Les IRQ matériels (0-15) sont décalés vers 32-47 (0x20-0x2F)
    mov al, 0x11
    out 0x20, al        ; PIC Master - init
    out 0xA0, al        ; PIC Slave - init
    
    mov al, 0x20
    out 0x21, al        ; Offset du Master : 0x20 (32)
    mov al, 0x28
    out 0xA1, al        ; Offset du Slave : 0x28 (40)
    
    mov al, 0x04
    out 0x21, al        ; Cascade sur IRQ2
    mov al, 0x02
    out 0xA1, al
    
    mov al, 0x01
    out 0x21, al        ; Mode 8086
    out 0xA1, al
    
    ; On active l'IRQ1 (clavier) et on masque tout le reste pour l'instant
    mov al, 0xFD        ; 1111 1101 (masque clavier libre)
    out 0x21, al
    mov al, 0xFF        ; Tout bloquer sur le slave
    out 0xA1, al

    ; Renseignement des interruptions
    set_idt_entry 0x21, isr_clavier ; IRQ1 -> Int 0x21
    set_idt_entry 0x80, isr_systeme ; Int Système personnalisée
    
    ; Activation
    lidt [idt_descriptor]
    sti                 ; Activation des interruptions CPU
    ret

; Notre appel système - int 0x80
; EAX = Fonction désirée : 1 = Afficher char (dans BL), 2 = Afficher chaîne (dans EBX)
isr_systeme:
    pusha
    cmp eax, 1
    je .fonction_char
    cmp eax, 2
    je .fonction_chaine
    jmp .fin

.fonction_char:
    mov al, bl
    call afficher_caractere
    jmp .fin
.fonction_chaine:
    mov esi, ebx
    call afficher_chaine
.fin:
    popa
    iret