;
; Aplicacion2.asm
;
; Created: 17/3/2026 11:30:35
; Author : brian
;
#include <m328pdef.inc>

;**************************** Igualdades **************************************
.equ	LEDBUILTIN = PB5
.equ	SW0 = PB4

.equ	BUFSIZETX = 32

;****************** definiciones - nombres simb?licos *************************
.def	w=r16
.def	w1=r17
.def	saux=r18
.def	flag1=r19
.def	newButton=r21


;************************ Segmento de EEPROM **********************************
.eseg
econfig:	.BYTE	1

;*********************** constantes en EEPROM *********************************
const2:		.DB 1, 2, 3

;********************** segmento de Datos SRAM ********************************
.dseg
statboot:	.BYTE	1
addrrx:		.BYTE	2
RXBUFTX:	.BYTE	BUFSIZETX

;************************ segmento de C?digo **********************************
.cseg
.org	0x00
	jmp	start
;interrupciones	
.org	0x1C
	jmp	TIM0_COMPA
.org	0x24
	jmp	USART_RXC

;constantes
version:	.DB "20250314_01b01",'\n','\0'
consts:		.DB 0, 255, 0b01010101, -128, 0xaa
varlist:	.DD 0, 0xfadebabe, -2147483648, 1 << 30

;Servicio de interrupciones
serv_rx0:
	reti

serv_cmp0:
	reti

;**** Funciones ****
ini_ports:
	ret

ini_serie0:
	ret

;Like a main in C
start:
	cli
	call	ini_ports
	call	ini_serie0
loop:
	jmp	loop