# avr-asm-protocol-serial-led-manager

Un sistema embebido desarrollado íntegramente en lenguaje ensamblador para microcontroladores AVR de 8 bits (ATmega328P / Arduino Uno). El proyecto implementa una máquina de estados finitos para el control de secuencias de 4 LEDs, gestionada tanto localmente mediante hardware (pulsadores) como remotamente a través de un protocolo de comunicación serie UART de longitud fija.

## Características Principales:

    Recepción UART por Interrupciones (RXCIE0): Implementación de una ISR para el buffer de recepción serie a 115200 baudios, previniendo el estrangulamiento del bucle principal y el desbordamiento de datos (Data Overrun).

    Temporización por Hardware (Timer1): Generación de una base de tiempo estricta de 1 ms mediante interrupciones del temporizador 1. No se utilizan retardos por software (delays bloqueantes).  

    Máquina de Estados (FSM): Arquitectura no bloqueante que gestiona cuatro estados principales del sistema: Reposo (IDLE), Secuencia Ascendente (UP), Secuencia Descendente (DOWN) y Modo Contador (COUNTER).  

    Heartbeat del Sistema: Indicador visual de funcionamiento (Watchdog lógico) utilizando el LED integrado de la placa, con un período de 3 segundos gestionado por el Timer1.  

    Antirrebote (Debounce) Analítico: Detección de flancos y estado de pulsadores por polling no bloqueante.

    Cambio de modo: usando el pulsador de apagado con un pulso largo, es decir, mayor a 2 segundos.

## Protocolo de Comunicación:


El sistema recibe comandos desde una PC u otro dispositivo externo mediante un protocolo de 8 bytes de longitud fija. Para facilitar la interacción directa desde terminales serie (como Hercules), el protocolo está implementado en formato ASCII. La estructura de la trama es la siguiente:

    Byte 0	Byte 1	Byte 2	Byte 3	Byte 4	Byte 5	      Byte 6	      Byte 7
        S	  CMD	    P1	    P2	    P3	    CHK_H	        CHK_L        W
    Header Comando  Param 1 Param 2 Param 3 Checksum High	Checksum Low	Tail

 **Validación (Checksum):**

El sistema verifica la integridad calculando la suma aritmética de 8 bits del bloque de Payload (CMD + P1 + P2 + P3) y comparándola con los bytes de Checksum recibidos en formato ASCII

## Tabla de Comandos (Tramas Precalculadas)

A continuación, se listan las tramas exactas (ya con el checksum calculado) listas para ser enviadas por terminal

### **Control de Secuencia**
- SU000E5W : Inicia secuencia Ascendente.
- SD000D4W : Inicia secuencia Descendente.
- SS000E3W : Detiene la secuencia.

### **Modo Contador**

- SC000D3W : Entrar al Modo Contador (Muestra la cantidad de veces que se presionó SW1)
- SX000E8W : Salir del Modo Contador.

### **Control Individual de LEDs**

- SL100DDW / SF100D7W : Encender / Apagar LED 1.  

- SL200DEW / SF200D8W : Encender / Apagar LED 2.  

- SL300DFW / SF300D9W : Encender / Apagar LED 3.  

- SL400E0W / SF400DAW : Encender / Apagar LED 4.  

- SA000D1W : Apagar todos los LEDs simultáneamente.

### **Control de Velocidad**

- ST000E4W : Intervalo de 250 ms.  

- ST100E5W : Intervalo de 500 ms.  

- ST200E6W : Intervalo de 1000 ms.  

- ST300E7W : Intervalo de 2000 ms.

## Hardware Requerido

- Placa de desarrollo compatible con ATmega328P (ej. Arduino Uno).

- 4x LEDs indicadores conectados al Puerto B (PB0 - PB3).

- 4x Pulsadores momentáneos conectados al Puerto D (PD2 - PD5) con resistencias pull-up internas activas.
