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
    sei                         ; habilitar interrupciones globales

;-------------------------------------------------------------------
; LOOP PRINCIPAL
;-------------------------------------------------------------------
loop:
    ;--- [1] Esperar flag_1ms (bit0 GPIOR0) -------------------------
    sbis    GPIOR0, BIT_1MS
    rjmp    loop
    cbi     GPIOR0, BIT_1MS     ; consumir flag
 
    ;--- [2] Leer botones y detectar flancos -------------------------
    in      newbtn, PIND
    andi    newbtn, (1<<SW1)|(1<<SW2)|(1<<SW3)|(1<<SW4)
 
    ; flancos descendentes (botón recién presionado)
    mov     w, newbtn
    com     w
    and     w, oldbtn
 
    ; flancos ascendentes (botón recién soltado)
    mov     w1, oldbtn
    com     w1
    and     w1, newbtn          ; w1 = flancos ascendentes
 
    ;--- [3] Manejar SW3 (lógica especial: corto vs largo) -----------
    ; Si SW3 está presionado ahora ? incrementar cnt_sw3
    mov     r24, newbtn
    com     r24
    andi    r24, (1<<SW3)
    breq    sw3_not_held        ; SW3 no está presionado
 
    ; SW3 presionado: incrementar cnt_sw3 (saturar en SW3_LONG)
    lds     r26, cnt_sw3
    lds     r27, cnt_sw3+1
    ldi     r24, low(SW3_LIMIT)
    ldi     r25, high(SW3_LIMIT)
    cp      r26, r24
    cpc     r27, r25
    breq    sw3_not_held        ; ya llegó al límite, no incrementar más
    ldi     r24, 1
    add     r26, r24
    clr     r24
    adc     r27, r24
    sts     cnt_sw3,   r26
    sts     cnt_sw3+1, r27
    rjmp    sw3_not_held
 
sw3_not_held:
    ; Flanco ascendente en SW3 ? evaluar duración
    sbrs    w1, SW3
    rjmp    skip_sw3            ; no hubo flanco ascendente
 
    lds     r26, cnt_sw3
    lds     r27, cnt_sw3+1
 
    ; Resetear cnt_sw3
    clr     r24
    sts     cnt_sw3,   r24
    sts     cnt_sw3+1, r24
 
    ; ¿Fue pulsación larga? (? 2000ms)
    ldi     r24, low(SW3_LIMIT)
    ldi     r25, high(SW3_LIMIT)
    cp      r26, r24
    cpc     r27, r25
    brlo    sw3_short           ; fue corto
 
sw3_long:
    ; Toggle modo COUNTER
    cpi     sysstate, STATE_COUNTER
    breq    sw3_exit_counter
    ; Entrar a modo COUNTER
    ldi     sysstate, STATE_COUNTER
    clr     w
    sts     ctr_val,    w
    sts     ctr_pulse,  w
    sts     cnt_pulse,  w
    sts     cnt_pulse+1,w
    call    update_leds         ; apagar LEDs de secuencia
    rjmp    skip_sw3
sw3_exit_counter:
    ; Salir de modo COUNTER ? IDLE
    ldi     sysstate, STATE_IDLE
    clr     pos
    call    update_leds
    rjmp    skip_sw3
 
sw3_short:
    ; Pulsación corta: STOP (solo si no está en modo COUNTER)
    cpi     sysstate, STATE_COUNTER
    breq    skip_sw3
    ldi     sysstate, STATE_IDLE
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    call    update_leds
 
skip_sw3:
 
    ;--- [4] SW1 ? depende del modo ---------------------------------
    sbrs    w, SW1
    rjmp    skip_sw1
 
    cpi     sysstate, STATE_COUNTER
    breq    sw1_counter
 
    ; Modo normal: iniciar secuencia ascendente
    ldi     sysstate, STATE_UP
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    rjmp    skip_sw1
 
sw1_counter:
    ; Modo contador: incrementar ctr_val (0?5?0)
    lds     w, ctr_val
    inc     w
    cpi     w, 6
    brlo    sw1_ctr_store
    clr     w
sw1_ctr_store:
    sts     ctr_val, w
    ; Reiniciar visualización
    clr     w
    sts     ctr_pulse,  w
    sts     cnt_pulse,  w
    sts     cnt_pulse+1,w
 
skip_sw1:
 
    ;--- [5] SW2 ? secuencia descendente (solo modo normal) ---------
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
 
    ;--- [6] SW4 ? modificar tiempo (solo modo normal) --------------
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
 
    ;--- [8] Lógica según estado del sistema -------------------------
    cpi     sysstate, STATE_COUNTER
    breq    do_counter
    cpi     sysstate, STATE_IDLE
    brne    no_idle
    rjmp    check_heartbeat
no_idle:
 
    ; ?? SEQ_UP o SEQ_DOWN ??
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
 
    ; ?? MODO CONTADOR ??
    ; Visualización: N pulsos de 200ms ON / 200ms OFF
    ; Entre grupos: 500ms de pausa
    ; Si ctr_val == 0 ? todos apagados
do_counter:
    lds     w, ctr_val
    tst     w
    breq    check_heartbeat     ; valor 0 ? LEDs apagados, no hacer nada
 
    ; Incrementar cnt_pulse
    lds     r26, cnt_pulse
    lds     r27, cnt_pulse+1
    ldi     w, 1
    add     r26, w
    clr     w
    adc     r27, w
    sts     cnt_pulse,   r26
    sts     cnt_pulse+1, r27
 
    ; Fase ON: 0..199ms ? LEDs encendidos
    ldi     r24, low(200)
    ldi     r25, high(200)
    cp      r26, r24
    cpc     r27, r25
    brsh    ctr_check_off
    ; Encender todos los LEDs (preservar HB)
    mov     w, ledstate
    andi    w, (1<<LEDBUILTIN)
    ori     w, (1<<LED1)|(1<<LED2)|(1<<LED3)|(1<<LED4)
    mov     ledstate, w
    out     PORTB, ledstate
    rjmp    check_heartbeat
 
ctr_check_off:
    ; Fase OFF: 200..399ms ? LEDs apagados
    ldi     r24, low(400)
    ldi     r25, high(400)
    cp      r26, r24
    cpc     r27, r25
    brsh    ctr_next_pulse
    ; Apagar LEDs de secuencia (preservar HB)
    mov     w, ledstate
    andi    w, (1<<LEDBUILTIN)
    mov     ledstate, w
    out     PORTB, ledstate
    rjmp    check_heartbeat
 
ctr_next_pulse:
    ; Terminó un ciclo ON/OFF de 400ms ? ver si hay más pulsos
    lds     w, ctr_pulse
    inc     w
    sts     ctr_pulse, w
    lds     r24, ctr_val
    cp      w, r24
    brlo    ctr_restart_pulse   ; todavía quedan pulsos
 
    ; Terminaron todos los pulsos ? pausa de 500ms adicionales
    ; cnt_pulse sigue corriendo hasta 400+500=900ms
    ldi     r24, low(900)
    ldi     r25, high(900)
    cp      r26, r24
    cpc     r27, r25
    brlo    check_heartbeat     ; en pausa
 
    ; Fin de pausa ? reiniciar secuencia de pulsos
    clr     w
    sts     ctr_pulse,   w
    sts     cnt_pulse,   w
    sts     cnt_pulse+1, w
    rjmp    check_heartbeat
 
ctr_restart_pulse:
    ; Reiniciar cnt_pulse para el siguiente pulso
    clr     w
    sts     cnt_pulse,   w
    sts     cnt_pulse+1, w
    rjmp    check_heartbeat
 
    ;--- [9] Heartbeat (flag_100ms) ----------------------------------
    ; Modo normal:  1 flash de 100ms cada 3s
    ; Modo counter: 2 flashes rápidos cada 3s
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
 
    ; ?? Heartbeat modo normal: 1 flash en t=0, apagar en t=1 ??
    cpi     r26, 1
    brne    hb_check_off_normal
    ; Encender LEDBUILTIN
    ldi     w, (1<<LEDBUILTIN)
    or      ledstate, w
    out     PORTB, ledstate
    rjmp    hb_check_reset
 
hb_check_off_normal:
    cpi     r26, 2
    brne    hb_check_reset
    ; Apagar LEDBUILTIN
    mov     w, ledstate
    andi    w, ~(1<<LEDBUILTIN)
    mov     ledstate, w
    out     PORTB, ledstate
    rjmp    hb_check_reset
 
    ; ?? Heartbeat modo counter: 2 flashes (t=0 ON, t=1 OFF, t=2 ON, t=3 OFF) ??
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
    ; Resetear cnt_hb cada 30 x 100ms = 3s
    cpi     r26, HB_PERIOD
    brsh    no_hb_reset
    rjmp    loop
no_hb_reset:
    clr     w
    sts     cnt_hb,   w
    sts     cnt_hb+1, w
 
    rjmp    loop