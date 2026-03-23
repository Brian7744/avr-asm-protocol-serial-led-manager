;
; Aplicacion2.asm
;
; Created: 17/3/2026 11:30:35
; Author : brian
;
#include <m328pdef.inc>

;**************************** Igualdades **************************************
;.equ	BUFSIZETX = 32


; Etiquetas para los pines
.equ    LEDBUILTIN  = PB5
.equ    LED1        = PB0
.equ    LED2        = PB1
.equ    LED3        = PB2
.equ    LED4        = PB3
.equ    SW1         = PD2
.equ    SW2         = PD3
.equ    SW3         = PD4
.equ    SW4         = PD5

.equ    STATE_IDLE  = 0
.equ    STATE_UP    = 1
.equ    STATE_DOWN  = 2

; Etiqueta para la configuracion del timer1 
.equ    OCR1A_VAL   = 249       ; 16MHz / 64 / 1000 - 1 = 249 ? ISR cada 1ms

;****************** definiciones - nombres simbolicos *************************
.def	w			= r16
.def	w1			= r17
.def	ledstate	= r18
.def	sysstate	= r19
.def    pos         = r20
.def	timeidx		= r21
.def    oldbtn      = r22
.def    newbtn      = r23



;********************** segmento de Datos SRAM ********************************
.dseg
;statboot:	.BYTE	1
;addrrx:		.BYTE	2
;RXBUFTX:	.BYTE	BUFSIZETX
flag_1ms:   .byte 1     ; seteado por ISR cada 1ms, optimizable
flag_100ms: .byte 1     ; seteado por ISR cada 100ms
cnt_100ms:  .byte 1     ; cuenta regresiva 100?0 en ISR
cnt_hb:     .byte 2     ; contador heartbeat en x100ms (0?29 = 3s)
cnt_seq:    .byte 2     ; contador secuencia en ms

;************************ segmento de Codigo **********************************
.cseg
.org	0x00
	jmp	start
;interrupciones	
.org    0x1A                    ; TIMER1_COMPA vector
    jmp     isr_timer1
;.org	0x24
;	jmp	USART_RXC
.org    0x34                    ; fin de tabla de vectores. Pregunta: Es necesario



;Servicio de interrupciones
isr_timer1:
    push    r28
    in      r28, SREG
    push    r28

    ; --- setear flag_1ms ---
    ldi     r28, 1
    sts     flag_1ms, r28

    ; --- decrementar cnt_100ms ---
    lds     r28, cnt_100ms
    dec     r28
    sts     cnt_100ms, r28
    brne    isr_exit            ; si no llegó a 0, salir

    ; --- llegó a 0: recargar y setear flag_100ms ---
    ldi     r28, 100
    sts     cnt_100ms, r28
    ldi     r28, 1
    sts     flag_100ms, r28

isr_exit:
    pop     r28
    out     SREG, r28
    pop     r28
    reti



;**** Funciones ****

ini_ports:
    ; cpnfiguracion de las salidas
	ldi     w, (1<<LEDBUILTIN)|(1<<LED1)|(1<<LED2)|(1<<LED3)|(1<<LED4)
    out     DDRB, w	; el bit que tenga 1 indica que es una salida
    ldi     w, 0
    out     PORTB, w ; apaga todos los led asociados al puerto
    ; configuracion de las entradas
	ldi     w, 0
    out     DDRD, w
    ldi     w, (1<<SW1)|(1<<SW2)|(1<<SW3)|(1<<SW4)
    out     PORTD, w
    ret

;-------------------------------------------------------------------
; ini_timer1 — CTC, prescaler 64, OCR1A = 249 ? ISR cada 1ms
;-------------------------------------------------------------------
ini_timer1:
    ; Asegurarse que Timer1 está detenido antes de configurar
    clr     w
    sts     TCCR1B, w

    ; TCCR1A = 0 (modo CTC no usa OC1A/OC1B)
    clr     w
    sts     TCCR1A, w

    ; OCR1A = 249
    ldi     w, high(OCR1A_VAL)
    sts     OCR1AH, w
    ldi     w, low(OCR1A_VAL)
    sts     OCR1AL, w

    ; Limpiar contador Timer1
    clr     w
    sts     TCNT1H, w
    sts     TCNT1L, w

    ; Habilitar interrupción por comparación A (OCIE1A)
    ldi     w, (1<<OCIE1A)
    sts     TIMSK1, w

    ; TCCR1B: modo CTC (WGM12=1) + prescaler 64 (CS11=1, CS10=1)
    ldi     w, (1<<WGM12)|(1<<CS11)|(1<<CS10)
    sts     TCCR1B, w
    ret

;-------------------------------------------------------------------
; update_leds — igual que el ejercicio 2
;-------------------------------------------------------------------
update_leds:
    mov     w, ledstate
    andi    w, (1<<LEDBUILTIN)

    cpi     sysstate, STATE_IDLE
    breq    ul_idle
    cpi     sysstate, STATE_UP
    breq    ul_up

    ; STATE_DOWN
    cpi     pos, 0
    breq    ul_mask_00
    cpi     pos, 1
    breq    ul_mask_08
    cpi     pos, 2
    breq    ul_mask_0C
    cpi     pos, 3
    breq    ul_mask_0E
    rjmp    ul_mask_0F

ul_up:
    cpi     pos, 0
    breq    ul_mask_00
    cpi     pos, 1
    breq    ul_mask_01
    cpi     pos, 2
    breq    ul_mask_03
    cpi     pos, 3
    breq    ul_mask_07
    rjmp    ul_mask_0F

ul_idle:
ul_mask_00: ldi w1, 0x00
    rjmp    ul_apply
ul_mask_01: ldi w1, 0x01
    rjmp    ul_apply
ul_mask_03: ldi w1, 0x03
    rjmp    ul_apply
ul_mask_07: ldi w1, 0x07
    rjmp    ul_apply
ul_mask_08: ldi w1, 0x08
    rjmp    ul_apply
ul_mask_0C: ldi w1, 0x0C
    rjmp    ul_apply
ul_mask_0E: ldi w1, 0x0E
    rjmp    ul_apply
ul_mask_0F: ldi w1, 0x0F

ul_apply:
    or      w, w1
    mov     ledstate, w
    out     PORTB, ledstate
    ret

;-------------------------------------------------------------------
; get_delay — devuelve límite en r24:r25 según timeidx
;   0 ? 250ms  1 ? 500ms  2 ? 1000ms  3 ? 2000ms
;-------------------------------------------------------------------
get_delay:
    cpi     timeidx, 0
    breq    gd_250
    cpi     timeidx, 1
    breq    gd_500
    cpi     timeidx, 2
    breq    gd_1000
    ldi     r24, low(2000)
    ldi     r25, high(2000)
    ret
gd_250:
    ldi     r24, low(250)
    ldi     r25, high(250)
    ret
gd_500:
    ldi     r24, low(500)
    ldi     r25, high(500)
    ret
gd_1000:
    ldi     r24, low(1000)
    ldi     r25, high(1000)
    ret

;Like a main in C
start:
    cli
    ldi     w, low(RAMEND)
    out     SPL, w
    ldi     w, high(RAMEND)
    out     SPH, w

    call    ini_ports

    ; Inicializar variables en SRAM
    clr     w
    sts     flag_1ms,   w
    sts     flag_100ms, w
    sts     cnt_seq,    w       ; cnt_seq low
    sts     cnt_seq+1,  w       ; cnt_seq high
    sts     cnt_hb,     w       ; cnt_hb low
    sts     cnt_hb+1,   w       ; cnt_hb high
    ldi     w, 100
    sts     cnt_100ms,  w       ; cnt_100ms arranca en 100

    ; Inicializar registros
    clr     ledstate
    ldi     sysstate, STATE_IDLE
    clr     pos
    ldi     timeidx, 1          ; tiempo inicial = 500ms

    ; Leer estado inicial de botones
    in      oldbtn, PIND
    andi    oldbtn, (1<<SW1)|(1<<SW2)|(1<<SW3)|(1<<SW4)

    call    ini_timer1
    sei                         ; habilitar interrupciones globales

;-------------------------------------------------------------------
; LOOP PRINCIPAL
;-------------------------------------------------------------------
loop:

    ;--- [1] Esperar flag_1ms ----------------------------------------
    lds     w, flag_1ms
    tst     w
    breq    loop                ; si flag_1ms == 0, seguir esperando
    clr     w
    sts     flag_1ms, w         ; consumir flag

    ;--- [2] Pulsadores: leer y detectar flancos ---------------------
    in      newbtn, PIND
    andi    newbtn, (1<<SW1)|(1<<SW2)|(1<<SW3)|(1<<SW4)
    mov     w, newbtn
    com     w
    and     w, oldbtn           ; w = flancos descendentes

    ;--- [3] SW1 ? secuencia ascendente ------------------------------
    sbrs    w, SW1
    rjmp    skip_sw1
    ldi     sysstate, STATE_UP
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
skip_sw1:

    ;--- [4] SW2 ? secuencia descendente -----------------------------
    sbrs    w, SW2
    rjmp    skip_sw2
    ldi     sysstate, STATE_DOWN
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
skip_sw2:

    ;--- [5] SW3 ? detener -------------------------------------------
    sbrs    w, SW3
    rjmp    skip_sw3
    ldi     sysstate, STATE_IDLE
    clr     pos
    call    update_leds
skip_sw3:

    ;--- [6] SW4 ? modificar tiempo ----------------------------------
    sbrs    w, SW4
    rjmp    skip_sw4
    inc     timeidx
    cpi     timeidx, 4
    brlo    skip_sw4
    clr     timeidx
skip_sw4:

    ;--- [7] Guardar estado botones ----------------------------------
    mov     oldbtn, newbtn

    ;--- [8] Avanzar secuencia si no está en IDLE --------------------
    cpi     sysstate, STATE_IDLE
    breq    check_heartbeat

    ; Incrementar cnt_seq en 1ms
    lds     r26, cnt_seq
    lds     r27, cnt_seq+1
    ldi     w, 1
    add     r26, w
    clr     w
    adc     r27, w
    sts     cnt_seq,   r26
    sts     cnt_seq+1, r27

    ; Comparar cnt_seq con límite de get_delay
    call    get_delay           ; límite en r24:r25
    cp      r26, r24
    cpc     r27, r25
    brlo    check_heartbeat     ; todavía no llegó al límite

    ; Resetear cnt_seq
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w

    ; Avanzar pos (igual en UP y DOWN, update_leds interpreta)
    inc     pos
    cpi     pos, 5
    brlo    seq_update
    ldi     pos, 1
seq_update:
    call    update_leds

    ;--- [9] Heartbeat cada 100ms (usa flag_100ms) -------------------
check_heartbeat:
    lds     w, flag_100ms
    tst     w
    breq    loop                ; flag no seteado, volver
    clr     w
    sts     flag_100ms, w       ; consumir flag

    ; Incrementar cnt_hb
    lds     r26, cnt_hb
    lds     r27, cnt_hb+1
    ldi     w, 1
    add     r26, w
    clr     w
    adc     r27, w
    sts     cnt_hb,   r26
    sts     cnt_hb+1, r27

    ; Comparar cnt_hb con 30 (30 x 100ms = 3000ms = 3s)
    cpi     r26, 30
    ldi     w, 0
    cpc     r27, w
    brlo    loop                ; todavía no llegó a 3s

    ; Resetear cnt_hb y toggle LEDBUILTIN
    clr     w
    sts     cnt_hb,   w
    sts     cnt_hb+1, w
    ldi     w, (1<<LEDBUILTIN)
    eor     ledstate, w
    out     PORTB, ledstate

    rjmp    loop