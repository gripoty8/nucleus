gdt_start:
    dd 0x0, 0x0             ; Entrée nulle obligatoire

gdt_code:                   ; Segment de code
    dw 0xffff               ; Limite
    dw 0x0                  ; Base (0-15)
    db 0x0                  ; Base (16-23)
    db 10011010b            ; Flags d'accès
    db 11001111b            ; Drapeaux + Limite (16-19)
    db 0x0                  ; Base (24-31)

gdt_data:                   ; Segment de données
    dw 0xffff
    dw 0x0
    db 0x0
    db 10010010b
    db 11001111b
    db 0x0

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start
