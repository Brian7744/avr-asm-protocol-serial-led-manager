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

; Protocolo 8 bytes ASCII: S CMD P1 P2 P3 CHK_H CHK_L W
.equ    PROTO_HEADER    = 'S'
.equ    PROTO_TAIL      = 'W'
.equ    PROTO_LEN       = 8

.equ    CMD_START_UP        = 'U'
.equ    CMD_START_DOWN      = 'D'
.equ    CMD_STOP            = 'S'
.equ    CMD_START_COUNTER   = 'C'
.equ    CMD_STOP_COUNTER    = 'X'
.equ    CMD_LED_ON          = 'L'
.equ    CMD_LED_OFF         = 'F'
.equ    CMD_ALL_OFF         = 'A'
.equ    CMD_SET_TIME        = 'T'

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

; Buffer protocolo 8 bytes ASCII
rx_buf:     .byte 8     ; S CMD P1 P2 P3 CHK_H CHK_L W
rx_idx:     .byte 1     ; índice del próximo byte (0-7)
rx_ready:   .byte 1     ; 1 = trama completa lista para procesar

;************************ segmento de Codigo **********************************
.cseg
.org    0x00
    jmp     start

.org    0x1A                     ; TIMER1_COMPA vector
    jmp     isr_timer1

.org    0x24                     ; USART_RX vector
    jmp     isr_uart_rx

.org    0x34

;-------------------------------------------------------------------
; ISR USART_RX — Ejecuta automáticamente al recibir un byte
;-------------------------------------------------------------------
isr_uart_rx:
    ; 1. Guardar contexto (¡Crítico en ASM!)
    push    r24
    in      r24, SREG
    push    r24
    push    r25
    push    r26
    push    r27
    push    r28

    ; 2. Leer dato del registro físico
    lds     r24, UDR0

    ; 3. Ignorar CR y LF
    cpi     r24, 0x0D
    breq    rx_isr_exit
    cpi     r24, 0x0A
    breq    rx_isr_exit

    ; 4. Si rx_ready=1 (hay trama sin procesar), descartamos byte para no corromper
    lds     r25, rx_ready
    tst     r25
    brne    rx_isr_exit

    ; 5. Lógica de guardado
    lds     r25, rx_idx

    ; Si es primer byte, validar que sea el Header 'S'
    tst     r25
    brne    rx_isr_store
    cpi     r24, PROTO_HEADER
    brne    rx_isr_exit         ; No es 'S' -> se descarta

rx_isr_store:
    ; Guardar byte en rx_buf[rx_idx]
    ldi     r26, low(rx_buf)
    ldi     r27, high(rx_buf)
    add     r26, r25
    clr     r28
    adc     r27, r28
    st      X, r24

    ; rx_idx++
    inc     r25
    sts     rx_idx, r25

    ; Verificar si completamos la trama
    cpi     r25, PROTO_LEN
    brlo    rx_isr_exit

    ; Trama lista -> setear bandera y reiniciar índice
    ldi     r25, 1
    sts     rx_ready, r25
    clr     r25
    sts     rx_idx, r25

rx_isr_exit:
    ; 6. Restaurar contexto
    pop     r28
    pop     r27
    pop     r26
    pop     r25
    pop     r24
    out     SREG, r24
    pop     r24
    reti

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
    brne    isr_exit_t1

    ldi     r28, 100
    sts     cnt_100ms, r28
    sbi     GPIOR0, BIT_100MS

isr_exit_t1:
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
; ini_USART0 — Habilitando RXCIE0 para Interrupciones
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
    ; ACA ACTIVAMOS LA INTERRUPCION DE RECEPCION (RXCIE0)
    ldi     w, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0)
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
    sts     rx_idx,     w
    sts     rx_ready,   w

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

    ;--- [8] Procesar protocolo (Los datos se cargan por Interrupción) ---
    lds     r25, rx_ready
    tst     r25
    brne    process_uart
    jmp     skip_uart
process_uart:

    ; --- Verificar TAIL (rx_buf[7]) ---
    ldi     r26, low(rx_buf+7)
    ldi     r27, high(rx_buf+7)
    ld      r25, X
    cpi     r25, PROTO_TAIL
    breq    tail_ok
    jmp     uart_discard
tail_ok:

    ; --- Calcular checksum (SUMA): CMD + P1 + P2 + P3 ---
    ldi     r26, low(rx_buf+1)
    ldi     r27, high(rx_buf+1)
    
    ld      r24, X+             ; CMD
    ld      r25, X+             
    add     r24, r25            ; + P1
    ld      r25, X+             
    add     r24, r25            ; + P2
    ld      r25, X+             
    add     r24, r25            ; + P3 = CHK calculado

    ; Convertir r24 a 2 hex ASCII
    mov     r25, r24
    swap    r25
    andi    r25, 0x0F
    cpi     r25, 10
    brlo    chk_h_digit
    subi    r25, -('A'-10)
    rjmp    chk_h_done
chk_h_digit:
    subi    r25, -'0'
chk_h_done:
    ldi     r26, low(rx_buf+5)
    ldi     r27, high(rx_buf+5)
    ld      r28, X
    cp      r25, r28
    breq    chk_h_ok
    jmp     uart_discard
chk_h_ok:

    mov     r25, r24
    andi    r25, 0x0F
    cpi     r25, 10
    brlo    chk_l_digit
    subi    r25, -('A'-10)
    rjmp    chk_l_done
chk_l_digit:
    subi    r25, -'0'
chk_l_done:
    ldi     r26, low(rx_buf+6)
    ldi     r27, high(rx_buf+6)
    ld      r28, X
    cp      r25, r28
    breq    chk_l_ok
    jmp     uart_discard
chk_l_ok:

    ; --- Checksum OK ? leer CMD y P1 ---
    ldi     r26, low(rx_buf+1)
    ldi     r27, high(rx_buf+1)
    ld      r24, X+             ; CMD
    ld      r25, X              ; P1
    subi    r25, '0'            ; Valor P1

    ; Limpiar buffer (Liberar la interrupción para la prox trama)
    clr     r28
    sts     rx_ready, r28
    sts     rx_idx,   r28

    ; --- Despachar comando ---
    cpi     r24, CMD_START_UP
    brne    ucmd_dn
    ldi     sysstate, STATE_UP
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    jmp     skip_uart

ucmd_dn:
    cpi     r24, CMD_START_DOWN
    brne    ucmd_stop
    ldi     sysstate, STATE_DOWN
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    jmp     skip_uart

ucmd_stop:
    cpi     r24, CMD_STOP
    brne    ucmd_cnt_on
    ldi     sysstate, STATE_IDLE
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    call    update_leds
    jmp     skip_uart

ucmd_cnt_on:
    cpi     r24, CMD_START_COUNTER
    brne    ucmd_cnt_off
    call    enter_counter
    jmp     skip_uart

ucmd_cnt_off:
    cpi     r24, CMD_STOP_COUNTER
    brne    ucmd_led_on
    call    exit_counter
    jmp     skip_uart

ucmd_led_on:
    cpi     r24, CMD_LED_ON
    brne    ucmd_led_off
    cpi     r25, 1
    breq    ulon_1
    cpi     r25, 2
    breq    ulon_2
    cpi     r25, 3
    breq    ulon_3
    cpi     r25, 4
    breq    ulon_4
    jmp     skip_uart
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
    jmp     skip_uart

ucmd_led_off:
    cpi     r24, CMD_LED_OFF
    brne    ucmd_all_off
    cpi     r25, 1
    breq    uloff_1
    cpi     r25, 2
    breq    uloff_2
    cpi     r25, 3
    breq    uloff_3
    cpi     r25, 4
    breq    uloff_4
    jmp     skip_uart
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
    jmp     skip_uart

ucmd_all_off:
    cpi     r24, CMD_ALL_OFF
    brne    ucmd_set_time
    ldi     sysstate, STATE_IDLE
    clr     pos
    clr     w
    sts     cnt_seq,   w
    sts     cnt_seq+1, w
    call    update_leds
    jmp     skip_uart

ucmd_set_time:
    cpi     r24, CMD_SET_TIME
    brne    uart_discard
    cpi     r25, 4
    brsh    skip_uart_jmp
    mov     timeidx, r25
skip_uart_jmp:
    jmp     skip_uart

uart_discard:
    clr     r28
    sts     rx_ready, r28
    sts     rx_idx,   r28

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