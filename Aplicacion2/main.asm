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

.equ    STATE_IDLE      = 0
.equ    STATE_UP        = 1
.equ    STATE_DOWN      = 2
.equ    STATE_COUNTER   = 3

; Bits en GPIOR0
.equ    BIT_1MS         = 0
.equ    BIT_100MS       = 1

; Timer1
.equ    OCR1A_VAL       = 249

; Heartbeat
.equ    HB_PERIOD       = 30
.equ    SW3_LIMIT       = 2000

; UART — 115200 baud @ 16MHz con U2X0=1
.equ    UBRR_VAL        = 16

; Protocolo 2 bytes: CMD + PARAM
; Byte 1: letra de comando
; Byte 2: parámetro ('0'..'4')
; CR y LF se ignoran
.equ    CMD_START_UP        = 'U'   ; U0 ? secuencia ascendente
.equ    CMD_START_DOWN      = 'D'   ; D0 ? secuencia descendente
.equ    CMD_STOP            = 'S'   ; S0 ? detener
.equ    CMD_START_COUNTER   = 'C'   ; C0 ? modo contador
.equ    CMD_STOP_COUNTER    = 'X'   ; X0 ? salir del contador
.equ    CMD_LED_ON          = 'L'   ; L1..L4 ? encender LED
.equ    CMD_LED_OFF         = 'F'   ; F1..F4 ? apagar LED
.equ    CMD_ALL_OFF         = 'A'   ; A0 ? apagar todos
.equ    CMD_SET_TIME        = 'T'   ; T0..T3 ? cambiar tiempo

;****************** definiciones - nombres simbolicos *************************
.def    w           = r16
.def    w1          = r17
.def    ledstate    = r18
.def    sysstate    = r19
.def    pos         = r20
.def    timeidx     = r21
.def    oldbtn      = r22
.def    newbtn      = r23

;********************** segmento de Datos SRAM ********************************
.dseg
cnt_100ms:  .byte 1
cnt_hb:     .byte 2
cnt_seq:    .byte 2
cnt_sw3:    .byte 2
cnt_pulse:  .byte 2
ctr_val:    .byte 1
ctr_pulse:  .byte 1

; Buffer protocolo 2 bytes
rx_cmd:     .byte 1     ; byte de comando recibido
rx_param:   .byte 1     ; byte de parámetro recibido
rx_state:   .byte 1     ; 0=esperando CMD, 1=esperando PARAM, 2=listo

;************************ segmento de Codigo **********************************
.cseg
.org    0x00
    jmp     start

.org    0x1A                    ; TIMER1_COMPA vector
    jmp     isr_timer1

.org    0x34

;-------------------------------------------------------------------
; ISR Timer1 — ejecuta cada 1ms
;-------------------------------------------------------------------
isr_timer1:
    push    r28
    in      r28, SREG
    push    r28

    sbi     GPIOR0, BIT_1MS

    lds     r28, cnt_100ms
    dec     r28
    sts     cnt_100ms, r28
    brne    isr_exit

    ldi     r28, 100
    sts     cnt_100ms, r28
    sbi     GPIOR0, BIT_100MS

isr_exit:
    pop     r28
    out     SREG, r28
    pop     r28
    reti

;-------------------------------------------------------------------
; ini_ports
;-------------------------------------------------------------------
ini_ports:
    ldi     w, (1<<LEDBUILTIN)|(1<<LED1)|(1<<LED2)|(1<<LED3)|(1<<LED4)
    out     DDRB, w
    ldi     w, 0
    out     PORTB, w
    ldi     w, 0
    out     DDRD, w
    ldi     w, (1<<SW1)|(1<<SW2)|(1<<SW3)|(1<<SW4)
    out     PORTD, w
    ret

;-------------------------------------------------------------------
; ini_timer1
;-------------------------------------------------------------------
ini_timer1:
    clr     w
    sts     TCCR1B, w
    clr     w
    sts     TCCR1A, w
    ldi     w, high(OCR1A_VAL)
    sts     OCR1AH, w
    ldi     w, low(OCR1A_VAL)
    sts     OCR1AL, w
    clr     w
    sts     TCNT1H, w
    sts     TCNT1L, w
    ldi     w, (1<<OCIE1A)
    sts     TIMSK1, w
    ldi     w, (1<<WGM12)|(1<<CS11)|(1<<CS10)
    sts     TCCR1B, w
    ret

;-------------------------------------------------------------------
; ini_USART0 — 115200 baud, 8N1, polling
;-------------------------------------------------------------------
ini_USART0:
    ldi     w, UBRR_VAL
    sts     UBRR0L, w
    clr     w
    sts     UBRR0H, w
    ldi     w, (1<<U2X0)
    sts     UCSR0A, w
    ldi     w, 0x06
    sts     UCSR0C, w
    ldi     w, (1<<RXEN0)|(1<<TXEN0)
    sts     UCSR0B, w
    ret

;-------------------------------------------------------------------
; update_leds
;-------------------------------------------------------------------
update_leds:
    mov     w, ledstate
    andi    w, (1<<LEDBUILTIN)

    cpi     sysstate, STATE_IDLE
    breq    ul_mask_00
    cpi     sysstate, STATE_COUNTER
    breq    ul_mask_00
    cpi     sysstate, STATE_UP
    breq    ul_up

    ; STATE_DOWN
    cpi     pos, 0
    breq    ul_mask_00
    cpi     pos, 1
    breq    ul_mask_08
    cpi     pos, 2
    breq    ul_mask_04
    cpi     pos, 3
    breq    ul_mask_02
    rjmp    ul_mask_01

ul_up:
    cpi     pos, 0
    breq    ul_mask_00
    cpi     pos, 1
    breq    ul_mask_01
    cpi     pos, 2
    breq    ul_mask_02
    cpi     pos, 3
    breq    ul_mask_04
    rjmp    ul_mask_08

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
; get_delay
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
; enter_counter
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
; exit_counter
;-------------------------------------------------------------------
exit_counter:
    ldi     sysstate, STATE_IDLE
    clr     pos
    call    update_leds
    ret

;-------------------------------------------------------------------
; start
;-------------------------------------------------------------------
start:
    cli
    ldi     w, low(RAMEND)
    out     SPL, w
    ldi     w, high(RAMEND)
    out     SPH, w

    call    ini_ports

    out     GPIOR0, r1

    ldi     w, 100
    sts     cnt_100ms, w
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
    sts     rx_cmd,     w
    sts     rx_param,   w
    sts     rx_state,   w       ; 0 = esperando CMD

    clr     ledstate
    ldi     sysstate, STATE_IDLE
    clr     pos
    ldi     timeidx, 1

    in      oldbtn, PIND
    andi    oldbtn, (1<<SW1)|(1<<SW2)|(1<<SW3)|(1<<SW4)

    call    ini_timer1
    call    ini_USART0
    sei

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
    and     w, oldbtn

    mov     w1, oldbtn
    com     w1
    and     w1, newbtn

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

    ;--- [8] Procesar UART — protocolo 2 bytes -----------------------
    ; Verificar si hay byte disponible
    lds     r24, UCSR0A
    sbrs    r24, RXC0
    rjmp    skip_uart

    ; Leer byte
    lds     r24, UDR0

    ; Filtrar CR (0x0D) y LF (0x0A)
    cpi     r24, 0x0D
    brne    uart_not_cr
    rjmp    skip_uart
uart_not_cr:
    cpi     r24, 0x0A
    brne    uart_not_lf
    rjmp    skip_uart
uart_not_lf:

    ; ¿Estamos esperando CMD o PARAM?
    lds     r25, rx_state
    tst     r25
    brne    uart_got_param      ; rx_state=1 ? ya tenemos CMD, este es PARAM

    ; rx_state=0 ? este byte es el CMD
    sts     rx_cmd,   r24      ; guardar CMD
    ldi     r25, 1
    sts     rx_state, r25      ; pasar a esperar PARAM
    rjmp    skip_uart

uart_got_param:
    ; Tenemos CMD y PARAM — ejecutar
    sts     rx_param, r24      ; guardar PARAM
    clr     r25
    sts     rx_state, r25      ; resetear para próximo comando

    ; Convertir PARAM de ASCII a número
    subi    r24, '0'            ; r24 = valor numérico del parámetro
    lds     r25, rx_cmd         ; r25 = código de comando

    ; Despachar
    cpi     r25, CMD_START_UP
    brne    uart_dn
    ldi     sysstate, STATE_UP
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    rjmp    skip_uart

uart_dn:
    cpi     r25, CMD_START_DOWN
    brne    uart_stop
    ldi     sysstate, STATE_DOWN
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    rjmp    skip_uart

uart_stop:
    cpi     r25, CMD_STOP
    brne    uart_cnt_on
    ldi     sysstate, STATE_IDLE
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    call    update_leds
    rjmp    skip_uart

uart_cnt_on:
    cpi     r25, CMD_START_COUNTER
    brne    uart_cnt_off
    call    enter_counter
    rjmp    skip_uart

uart_cnt_off:
    cpi     r25, CMD_STOP_COUNTER
    brne    uart_led_on
    call    exit_counter
    rjmp    skip_uart

uart_led_on:
    cpi     r25, CMD_LED_ON
    brne    uart_led_off
    ; r24 = número de LED (1-4)
    cpi     r24, 1
    breq    ulon_1
    cpi     r24, 2
    breq    ulon_2
    cpi     r24, 3
    breq    ulon_3
    cpi     r24, 4
    breq    ulon_4
    rjmp    skip_uart
ulon_1: ldi w, (1<<LED1)
    rjmp    ulon_apply
ulon_2: ldi w, (1<<LED2)
    rjmp    ulon_apply
ulon_3: ldi w, (1<<LED3)
    rjmp    ulon_apply
ulon_4: ldi w, (1<<LED4)
ulon_apply:
    or      ledstate, w
    out     PORTB, ledstate
    rjmp    skip_uart

uart_led_off:
    cpi     r25, CMD_LED_OFF
    brne    uart_all_off
    cpi     r24, 1
    breq    uloff_1
    cpi     r24, 2
    breq    uloff_2
    cpi     r24, 3
    breq    uloff_3
    cpi     r24, 4
    breq    uloff_4
    rjmp    skip_uart
uloff_1: ldi w, ~(1<<LED1)
    rjmp    uloff_apply
uloff_2: ldi w, ~(1<<LED2)
    rjmp    uloff_apply
uloff_3: ldi w, ~(1<<LED3)
    rjmp    uloff_apply
uloff_4: ldi w, ~(1<<LED4)
uloff_apply:
    and     ledstate, w
    out     PORTB, ledstate
    rjmp    skip_uart

uart_all_off:
    cpi     r25, CMD_ALL_OFF
    brne    uart_set_time
    ldi     sysstate, STATE_IDLE
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    call    update_leds
    rjmp    skip_uart

uart_set_time:
    cpi     r25, CMD_SET_TIME
    brne    skip_uart
    ; r24 = timeidx (0-3)
    cpi     r24, 4
    brsh    skip_uart           ; fuera de rango ? ignorar
    mov     timeidx, r24

skip_uart:

    ;--- [9] Lógica según estado del sistema -------------------------
    cpi     sysstate, STATE_COUNTER
    breq    do_counter
    cpi     sysstate, STATE_IDLE
    brne    no_idle
    rjmp    check_heartbeat
no_idle:

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

    ldi     r24, low(900)
    ldi     r25, high(900)
    cp      r26, r24
    cpc     r27, r25
    brsh    no_ctr_wait
    rjmp    check_heartbeat
no_ctr_wait:
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

    ;--- [10] Heartbeat ----------------------------------------------
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