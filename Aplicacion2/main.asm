;
; Aplicacion2.asm
;
; Created: 17/3/2026 11:30:35
; Author : brian
;
#include <m328pdef.inc>

;**************************** Igualdades **************************************



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
.equ    STATE_COUNTER   = 3

; Bits en GPIOR0
.equ    BIT_1MS         = 0     ; bit0 = flag 1ms
.equ    BIT_100MS       = 1     ; bit1 = flag 100ms 

; Etiqueta para la configuracion del timer1 
.equ    OCR1A_VAL   = 249       ; 16MHz / 64 / 1000 - 1 = 249 ? ISR cada 1ms


; Tiempos heartbeat (en unidades de 100ms)
.equ    HB_PERIOD       = 30    ; 30 x 100ms = 3s período completo
.equ    HB_PULSE        = 1     ; 1 x 100ms = 100ms duración del flash
.equ    SW3_LIMIT        = 2000  ; 2000ms para considerar pulsación larga


; UART — 115200 baud @ 16MHz con U2X0=1
; UBRR = (16.000.000 / 8 / 115200) - 1 = 16
.equ    UBRR_VAL        = 16

; Comandos simples UART (provisorios, antes del protocolo)
.equ    CMD_START_COUNTER = 'y'
.equ    CMD_STOP_COUNTER  = 'n'

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

cnt_100ms:  .byte 1     ; cuenta regresiva 100?0 en ISR
cnt_hb:     .byte 2     ; contador heartbeat en x100ms (0?29 = 3s)
cnt_seq:    .byte 2     ; contador secuencia en ms
cnt_sw3:    .byte 2     ; contador de tiempo pulsado SW3 (ms)
cnt_pulse:  .byte 2     ; contador para pulsos del modo contador (ms)
ctr_val:    .byte 1     ; valor del contador (0-5) en modo COUNTER
ctr_pulse:  .byte 1     ; pulso actual mostrando en modo COUNTER

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

;-------------------------------------------------------------------
; ISR Timer1 — ejecuta cada 1ms
;-------------------------------------------------------------------
isr_timer1:
    push    r28
    in      r28, SREG
    push    r28

    ; --- setear flag_1ms ---
    sbi     GPIOR0, BIT_1MS

    ; --- decrementar cnt_100ms ---
    lds     r28, cnt_100ms
    dec     r28
    sts     cnt_100ms, r28
    brne    isr_exit            ; si no llegó a 0, salir

    ; --- llegó a 0: recargar y setear flag_100ms ---
    ldi     r28, 100
    sts     cnt_100ms, r28
    sbi     GPIOR0, BIT_100MS

isr_exit:
    pop     r28
    out     SREG, r28
    pop     r28
    reti



;**** Funciones ****
;-------------------------------------------------------------------
; ini_ports
;-------------------------------------------------------------------
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
; ini_USART0 — 115200 baud, 8N1, polling
; Orden de configuración: UBRR0L ? UBRR0H ? UCSR0A ? UCSR0C ? UCSR0B
; U2X0=1 (doble velocidad): UBRR = 16MHz / 8 / 115200 - 1 = 16
;-------------------------------------------------------------------
ini_USART0:
    ldi     w, UBRR_VAL
    sts     UBRR0L, w           ; baud rate low
    clr     w
    sts     UBRR0H, w           ; baud rate high = 0
    ldi     w, (1<<U2X0)        ; doble velocidad
    sts     UCSR0A, w
    ldi     w, 0x06             ; 8N1: UCSZ01=1, UCSZ00=1
    sts     UCSR0C, w
    ldi     w, (1<<RXEN0)|(1<<TXEN0)  ; habilitar RX y TX, sin ISR
    sts     UCSR0B, w
    ret
;-------------------------------------------------------------------
; update_leds 
; Preserva LEDBUILTIN. Interpreta sysstate y pos.
; En STATE_COUNTER apaga los LEDs de secuencia (los pulsos
; los maneja el loop principal directamente).
;-------------------------------------------------------------------
update_leds:
    mov     w, ledstate
    andi    w, (1<<LEDBUILTIN)
 
    cpi     sysstate, STATE_IDLE
    breq    ul_mask_00
    cpi     sysstate, STATE_COUNTER
    breq    ul_mask_00          ; en modo contador los LEDs los maneja el loop
    cpi     sysstate, STATE_UP
    breq    ul_up
 
    ; STATE_DOWN
    cpi     pos, 0
    breq    ul_mask_00		;				= 0000
    cpi     pos, 1
    breq    ul_mask_08		;               = 1000
    cpi     pos, 2
    breq    ul_mask_04		; 0x0C -> 0x04	= 0100
    cpi     pos, 3
    breq    ul_mask_02		; 0x0E -> 0x02  = 0010
    rjmp    ul_mask_01		; 0x0F -> 0x01	= 0001
 
ul_up:
    cpi     pos, 0
    breq    ul_mask_00		;				= 0000
    cpi     pos, 1
    breq    ul_mask_01		;				= 0001
    cpi     pos, 2
    breq    ul_mask_02		; 0x03 -> 0x02  = 0010
    cpi     pos, 3
    breq    ul_mask_04		; 0x07 -> 0x04	= 0100
    rjmp    ul_mask_08		; 0x0F -> 0x08  = 1000
 
ul_mask_00: ldi w1, 0x00
    rjmp    ul_apply
ul_mask_01: ldi w1, 0x01
    rjmp    ul_apply
ul_mask_08: ldi w1, 0x08
    rjmp    ul_apply
ul_mask_04: ldi w1, 0x04
    rjmp    ul_apply
ul_mask_02: ldi w1, 0x02
    rjmp    ul_apply

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

;-------------------------------------------------------------------
; enter_counter — lógica de entrada a modo COUNTER
; (usada tanto desde SW3 largo como desde UART)
;-------------------------------------------------------------------
enter_counter:
    ldi     sysstate, STATE_COUNTER
    clr     w
    sts     ctr_val,    w
    sts     ctr_pulse,  w
    sts     cnt_pulse,  w
    sts     cnt_pulse+1,w
    call    update_leds
    ret

;-------------------------------------------------------------------
; exit_counter — lógica de salida de modo COUNTER ? IDLE
;-------------------------------------------------------------------
exit_counter:
    ldi     sysstate, STATE_IDLE
    clr     pos
    call    update_leds
    ret

;Like a main in C
start:
    cli
    ldi     w, low(RAMEND)
    out     SPL, w
    ldi     w, high(RAMEND)
    out     SPH, w

    call    ini_ports

	; Limpiar GPIOR0 (flags)
    out     GPIOR0, r1          ; r1 = 0 siempre en AVR por convenio
    
	; Inicializar variables en SRAM
    
	ldi     w, 100
    sts     cnt_100ms, w       ; cnt_100ms arranca en 100
    clr     w
    sts     cnt_hb,     w
    sts     cnt_hb+1,   w
    sts     cnt_seq,    w
    sts     cnt_seq+1,  w
    sts     cnt_sw3,    w
    sts     cnt_sw3+1,  w
    sts     cnt_pulse,  w
    sts     cnt_pulse+1,w
    sts     ctr_val,    w
    sts     ctr_pulse,  w

    ; Inicializar registros
    clr     ledstate
    ldi     sysstate, STATE_IDLE
    clr     pos
    ldi     timeidx, 1          ; tiempo inicial = 500ms

    ; Leer estado inicial de botones
    in      oldbtn, PIND
    andi    oldbtn, (1<<SW1)|(1<<SW2)|(1<<SW3)|(1<<SW4)

    call    ini_timer1
    call    ini_USART0
    sei                         ; habilitar interrupciones globales

;-------------------------------------------------------------------
; LOOP PRINCIPAL
;-------------------------------------------------------------------
loop:
    ;--- [1] Esperar flag_1ms ----------------------------------------
    sbis    GPIOR0, BIT_1MS
    rjmp    loop
    cbi     GPIOR0, BIT_1MS

    ;--- [2] Leer botones y detectar flancos -------------------------
    in      newbtn, PIND
    andi    newbtn, (1<<SW1)|(1<<SW2)|(1<<SW3)|(1<<SW4)

    mov     w, newbtn
    com     w
    and     w, oldbtn           ; w  = flancos descendentes

    mov     w1, oldbtn
    com     w1
    and     w1, newbtn          ; w1 = flancos ascendentes

    ;--- [3] SW3: corto vs largo -------------------------------------
    mov     r24, newbtn
    com     r24
    andi    r24, (1<<SW3)
    breq    sw3_not_held

    lds     r26, cnt_sw3
    lds     r27, cnt_sw3+1
    ldi     r24, low(SW3_LIMIT)
    ldi     r25, high(SW3_LIMIT)
    cp      r26, r24
    cpc     r27, r25
    breq    sw3_not_held
    ldi     r24, 1
    add     r26, r24
    clr     r24
    adc     r27, r24
    sts     cnt_sw3,   r26
    sts     cnt_sw3+1, r27

sw3_not_held:
    sbrs    w1, SW3
    rjmp    skip_sw3

    lds     r26, cnt_sw3
    lds     r27, cnt_sw3+1
    clr     r24
    sts     cnt_sw3,   r24
    sts     cnt_sw3+1, r24

    ldi     r24, low(SW3_LIMIT)
    ldi     r25, high(SW3_LIMIT)
    cp      r26, r24
    cpc     r27, r25
    brlo    sw3_short

sw3_long:
    cpi     sysstate, STATE_COUNTER
    breq    sw3_do_exit
    call    enter_counter
    rjmp    skip_sw3
sw3_do_exit:
    call    exit_counter
    rjmp    skip_sw3

sw3_short:
    cpi     sysstate, STATE_COUNTER
    breq    skip_sw3
    ldi     sysstate, STATE_IDLE
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    call    update_leds

skip_sw3:

    ;--- [4] SW1 -----------------------------------------------------
    sbrs    w, SW1
    rjmp    skip_sw1

    cpi     sysstate, STATE_COUNTER
    breq    sw1_counter

    ldi     sysstate, STATE_UP
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    rjmp    skip_sw1

sw1_counter:
    lds     w, ctr_val
    inc     w
    cpi     w, 6
    brlo    sw1_ctr_store
    clr     w
sw1_ctr_store:
    sts     ctr_val, w
    clr     w
    sts     ctr_pulse,  w
    sts     cnt_pulse,  w
    sts     cnt_pulse+1,w

skip_sw1:

    ;--- [5] SW2 -----------------------------------------------------
    sbrs    w, SW2
    rjmp    skip_sw2
    cpi     sysstate, STATE_COUNTER
    breq    skip_sw2
    ldi     sysstate, STATE_DOWN
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
skip_sw2:

    ;--- [6] SW4 -----------------------------------------------------
    sbrs    w, SW4
    rjmp    skip_sw4
    cpi     sysstate, STATE_COUNTER
    breq    skip_sw4
    inc     timeidx
    cpi     timeidx, 4
    brlo    skip_sw4
    clr     timeidx
skip_sw4:

    ;--- [7] Guardar estado botones ----------------------------------
    mov     oldbtn, newbtn

    ;--- [8] Procesar UART ------------------------------------------
    ; Chequear RXC0 (bit 7 de UCSR0A) — hay byte disponible?
    lds     r24, UCSR0A
    sbrs    r24, RXC0
    rjmp    skip_uart           ; no hay dato

    ; Leer byte recibido
    lds     r24, UDR0

    ; ¿Es 'y'? ? entrar a modo contador
    cpi     r24, CMD_START_COUNTER
    brne    uart_check_n
    cpi     sysstate, STATE_COUNTER
    breq    skip_uart           ; ya está en modo contador, ignorar
    call    enter_counter
    rjmp    skip_uart

uart_check_n:
    ; ¿Es 'n'? ? salir de modo contador
    cpi     r24, CMD_STOP_COUNTER
    brne    skip_uart
    cpi     sysstate, STATE_COUNTER
    brne    skip_uart           ; no está en modo contador, ignorar
    call    exit_counter

skip_uart:

    ;--- [9] Lógica según estado del sistema -------------------------
    cpi     sysstate, STATE_COUNTER
    breq    do_counter
    cpi     sysstate, STATE_IDLE
    brne    no_idle
    rjmp    check_heartbeat
no_idle:

    ; SEQ_UP o SEQ_DOWN
    lds     r26, cnt_seq
    lds     r27, cnt_seq+1
    ldi     w, 1
    add     r26, w
    clr     w
    adc     r27, w
    sts     cnt_seq,   r26
    sts     cnt_seq+1, r27

    call    get_delay
    cp      r26, r24
    cpc     r27, r25
    brsh    no_seq_wait
    rjmp    check_heartbeat
no_seq_wait:

    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    inc     pos
    cpi     pos, 5
    brlo    seq_ok
    ldi     pos, 1
seq_ok:
    call    update_leds
    rjmp    check_heartbeat

    ; MODO CONTADOR
do_counter:
    lds     w, ctr_val
    tst     w
    breq    check_heartbeat

    lds     r26, cnt_pulse
    lds     r27, cnt_pulse+1
    ldi     w, 1
    add     r26, w
    clr     w
    adc     r27, w
    sts     cnt_pulse,   r26
    sts     cnt_pulse+1, r27

    ; Fase ON: 0..199ms
    ldi     r24, low(200)
    ldi     r25, high(200)
    cp      r26, r24
    cpc     r27, r25
    brsh    ctr_check_off
    mov     w, ledstate
    andi    w, (1<<LEDBUILTIN)
    ori     w, (1<<LED1)|(1<<LED2)|(1<<LED3)|(1<<LED4)
    mov     ledstate, w
    out     PORTB, ledstate
    rjmp    check_heartbeat

ctr_check_off:
    ; Fase OFF: 200..399ms
    ldi     r24, low(400)
    ldi     r25, high(400)
    cp      r26, r24
    cpc     r27, r25
    brsh    ctr_next_pulse
    mov     w, ledstate
    andi    w, (1<<LEDBUILTIN)
    mov     ledstate, w
    out     PORTB, ledstate
    rjmp    check_heartbeat

ctr_next_pulse:
    lds     w, ctr_pulse
    inc     w
    sts     ctr_pulse, w
    lds     r24, ctr_val
    cp      w, r24
    brlo    ctr_restart_pulse

    ; Pausa: 400..899ms
    ldi     r24, low(900)
    ldi     r25, high(900)
    cp      r26, r24
    cpc     r27, r25
    brsh    no_hb_wait
    rjmp    check_heartbeat
no_hb_wait:
    clr     w
    sts     ctr_pulse,   w
    sts     cnt_pulse,   w
    sts     cnt_pulse+1, w
    rjmp    check_heartbeat

ctr_restart_pulse:
    clr     w
    sts     cnt_pulse,   w
    sts     cnt_pulse+1, w
    rjmp    check_heartbeat

    ;--- [10] Heartbeat (flag_100ms) ---------------------------------
check_heartbeat:
    sbis    GPIOR0, BIT_100MS
    rjmp    loop
    cbi     GPIOR0, BIT_100MS

    lds     r26, cnt_hb
    lds     r27, cnt_hb+1
    ldi     w, 1
    add     r26, w
    clr     w
    adc     r27, w
    sts     cnt_hb,   r26
    sts     cnt_hb+1, r27

    cpi     sysstate, STATE_COUNTER
    breq    hb_counter

    ; Modo normal: 1 flash en t=1, apagar en t=2
    cpi     r26, 1
    brne    hb_check_off_normal
    ldi     w, (1<<LEDBUILTIN)
    or      ledstate, w
    out     PORTB, ledstate
    rjmp    hb_check_reset

hb_check_off_normal:
    cpi     r26, 2
    brne    hb_check_reset
    mov     w, ledstate
    andi    w, ~(1<<LEDBUILTIN)
    mov     ledstate, w
    out     PORTB, ledstate
    rjmp    hb_check_reset

    ; Modo contador: 2 flashes (t=1 ON, t=2 OFF, t=3 ON, t=4 OFF)
hb_counter:
    cpi     r26, 1
    breq    hb_on
    cpi     r26, 3
    breq    hb_on
    cpi     r26, 2
    breq    hb_off
    cpi     r26, 4
    breq    hb_off
    rjmp    hb_check_reset

hb_on:
    ldi     w, (1<<LEDBUILTIN)
    or      ledstate, w
    out     PORTB, ledstate
    rjmp    hb_check_reset

hb_off:
    mov     w, ledstate
    andi    w, ~(1<<LEDBUILTIN)
    mov     ledstate, w
    out     PORTB, ledstate

hb_check_reset:
    cpi     r26, HB_PERIOD
    brsh    no_hb_reset
    rjmp    loop
no_hb_reset:
    clr     w
    sts     cnt_hb,   w
    sts     cnt_hb+1, w
    rjmp    loop