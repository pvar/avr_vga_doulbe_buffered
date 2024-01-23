; *********************************************************************************************************************************
; programming  : pvar (spir@l evolut10n)
; started      : 20-11-2013
; completed    : 11-12-2013
;
; *************************************************************************************************
;
; NOTES:
; X: buffer pointer for string manipulation (outside ISR)
; Y: buffer pointer for rendering (inside ISR)
; Z: message pointer for copying (outside ISR)  /  scanline-data & font-data pointer (inside ISR)
;
; r3..r12: temporary storage for pointers and SREG (CPU-stack access is very slow)
;
; *************************************************************************************************



; **************************************************
; * fundamental assembler directives
; **************************************************

; macros ------------------------------------------------------------------------------------------

.include "outputbf.asm"

.macro release_dbus             ; release data-bus [2 cycles]
        out DDRD, zero          ; (1)
        out PORTD, zero         ; (1)
.endmacro

.macro occupy_dbus              ; occupy data bus [3 cycles]
        out PORTD, zero         ; (1)
        ser tmp4                ; (1)
        out DDRD, tmp4          ; (1)
.endmacro

; constants ---------------------------------------------------------------------------------------

.include "m644Pdef.inc"

.equ bfsel = 0                  ; PINB0
.equ vsync = 1                  ; PINB1
.equ hsync = 2                  ; PINB2
.equ disout = 3                 ; PINB3
.equ ramread = 4                ; PINB4
.equ ramenable = 5              ; PINB5

; variables ---------------------------------------------------------------------------------------

.equ var1 = 0x1E                ; General Purpose IO register
.equ var2 = 0x2A                ; General Purpose IO register
.equ var3 = 0x2B                ; General Purpose IO register

.def cursorX = r13              ; buffer address low byte for given text location
.def cursorY = r14              ; buffer address high byte for given text location

.def zero = r15                 ; always equal to zero

.def isrtmp1 = r16              ; temporary values (used inside ISR)
.def isrtmp2 = r17              ; temporary values (used inside ISR)
.def tmp1 = r21                 ; temporary values (outside ISR)
.def tmp2 = r20                 ; temporary values (outside ISR)
.def tmp3 = r19                 ; temporary values (outside ISR)
.def tmp4 = r18                 ; temporary values (outside ISR)

.def frames = r22               ; frames counter
.def timer = r23                ; time counter (time unit: 100ms)

.def color = r24                ; text color

.equ cmdH = 0x01                ; storage of incomming commands (size: 128b)
.equ cmdL = 0x00                ;

.equ prmH = 0x01                ; storage of commands' parameters (size: 128b)
.equ prmL = 0xF0                ;

.equ scratchH = 0x02            ; temporary storage of data from frame buffers (max safe size: 3072b)
.equ scratchL = 0x00            ;



; **************************************************
; * code segment initialization
; **************************************************

.cseg
.org 0
        rjmp mcu_init           ; Reset Handler
.org OC1Aaddr
        rjmp scanline           ; Timer1 CompareA Handler



; **************************************************
; * microcontroller initialization
; **************************************************

mcu_init:
        ldi tmp1, $10           ; set Stack Pointer high-byte
        out SPH, tmp1           ;
        ldi tmp1, $FF           ; set Stack Pointer low-byte
        out SPL, tmp1           ;

        lds tmp1, ADCSRA        ; turn off ADC
        cbr tmp1, 128           ; set ADEN bit to 0
        sts ADCSRA, tmp1        ;

        lds tmp1, ACSR          ; turn off and disconnect analog comp from internal v-ref
        sbr tmp1, 128           ; set ACD bit to 1
        cbr tmp1, 64            ; set ACBG bit to 1
        sts ACSR, tmp1          ;

        lds tmp1, WDTCSR        ; stop WDT
        andi tmp1, 0b10110111   ; clear WDIE and WDE
        sts WDTCSR, tmp1        ;

        ldi tmp1, 0b1000111     ; shutdown ADC, TWI, SPI and USART0
        sts PRR0, tmp1          ; set PRADC, PRTWI, PRSPI and PRUSART0 to 1

; PORT configuration
        ser tmp1                ;
        out DDRA, tmp1          ; set all pins as outputs (address high byte)
        out DDRC, tmp1          ; set all pins as outputs (address low byte)
        out DDRB, tmp1          ; set all pins as outputs (control signals)

; TIMER1 configuration
        clr tmp1                ;
        sts TCCR1A, tmp1        ; enable CTC mode
        ldi tmp1, 0b00001001    ; no prescalling
        sts TCCR1B, tmp1        ;

        ldi tmp1, 0b00000010    ; load 635 in OCR1A
        sts OCR1AH, tmp1                ;
        ldi tmp1, 0b01111011    ; (interrupt for scan-lines)
        sts OCR1AL, tmp1        ;

        ldi tmp1, 2             ;
        sts TIMSK1, tmp1        ; enable interrupt on match A

; always equals to zero!
        clr zero

; linedata pointer init and save
        ldi ZH, high(linedata*2)
        ldi ZL, low(linedata*2)
        movw r4, ZL

; enable interrupts!
        sei



; **************************************************
; * main program
; **************************************************

main:
        cbi PORTB, bfsel        ; select frame buffer 1
        sbi PORTB, ramenable    ; enable SRAM
        sbi PORTB, disout       ; disable video output

        call clear              ; clear screen :-)

        ldi tmp1, 18
        ldi tmp2, 10
        call locate
        ldi color, 3
        ldi tmp1, 'B'
        call print
        call right
        ldi tmp1, 'y'
        call print
        call right
        ldi tmp1, ' '
        call print
        call right
        ldi tmp1, 'S'
        call print
        call right
        ldi tmp1, 'p'
        call print
        call right
        ldi tmp1, 'i'
        call print
        call right
        ldi tmp1, 'r'
        call print
        call right
        ldi tmp1, '@'
        call print
        call right
        ldi tmp1, 'l'
        call print
        call right
        ldi tmp1, ' '
        call print
        call right
        ldi tmp1, 'E'
        call print
        call right
        ldi tmp1, '.'
        call print

        call splash

loop:
        nop
        nop
        nop
        rjmp loop



; **************************************************
; horizontal ---------------------
; sync pulse    76  cycles
; back porch    37  cycles
; visible       512 cycles
; front porch   11  cycles
;
; vertical -----------------------
; sync pulse    2   lines
; back porch    33  lines
; visible       480 lines
; front porch   10  lines
; **************************************************

scanline:
; compensate for variable interrupt latency
; add a delay of 4 or 5 cycles depending on timer-counter-value
        lds isrtmp1, TCNT1L     ; (2)
        sbrc isrtmp1, 0         ; (1~2)
        sbi DDRA, 0             ; (2) (no effect -- already configured as output)

; -------------------------------------------------------------------------------------------------
; sync pulse (76 cycles) [working version: 68 cycles]
; -------------------------------------------------------------------------------------------------

; start horizontal sync pulse
        cbi PORTB, hsync        ; (2)

; save control signals
        in isrtmp1, PORTB       ; (1)
        sbr isrtmp1, (1<<hsync) ; (1) restore initial hsync state
        mov r3, isrtmp1         ; (1)

; save SREG
        in r10, SREG            ; (1)
; save Z pointer
        movw r6, ZL             ; (1)
; restore linedata pointer
        movw ZL, r4             ; (1)

; get first byte for current line
        lpm isrtmp2, Z+         ; (3)

; check for end of frame
        cpi isrtmp2, 255        ; (1)
        breq frame_end          ; (1~2)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        rjmp vertical_sync      ; (2)

; if end of frame -> reset scanline pointer
frame_end:
        ldi ZH, high(linedata*2); (1)
        ldi ZL, low(linedata*2) ; (1)
        lpm isrtmp2, Z+         ; (3)   must remain unchanged until check for VIDEO BLANKING period
        inc frames              ; (1)

; start / stop vertical sync pulse
vertical_sync:
        sbrc isrtmp2, 7         ; (1~2)
        cbi PORTB, vsync        ; (2)
        sbrs isrtmp2, 7         ; (1~2)
        sbi PORTB, vsync        ; (2)

; get address high byte
        lpm isrtmp1, Z+         ; (3)   must remain unchanged until PORTA is updated!

; save linedata pointer
        movw r4, ZL             ; (1)
; restore Z pointer
        movw ZL, r6             ; (1)

; timer update
        cpi frames, 6           ; (1)
        brne not_yet            ; (1~2)
        inc timer               ; (1)
        clr frames              ; (1)
        rjmp timer_done         ; (2)
not_yet:
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
timer_done:

; 30 spare cycles
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)

; stop horizontal sync pulse
        sbi PORTB, hsync        ; (2)

; -------------------------------------------------------------------------------------------------
; back porch (37 cycles) [working version: 31 cycles]
; -------------------------------------------------------------------------------------------------

; if set -> video blanking / exit ISR
        sbrc isrtmp2, 6         ; (1~2)
        reti                    ; (4)

active_line:
; save address-bus high byte
        in r11, PORTA           ; (1)
; save address-bus low byte
        in r12, PORTC           ; (1)
; save data-bus data
        in r8, PORTD            ; (1)
; save data-bus direction
        in r9, DDRD             ; (1)

; set SRAM READ mode
        sbi PORTB, ramread      ; (2)
; release data-bus
        release_dbus            ; (2)
; init address-bus high byte
        out PORTA, isrtmp1      ; (1)
; init address-bus low byte
        out PORTC, zero         ; (1)

; 17 spare cycles
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)

        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)
        nop                     ; (1)

        nop                     ; (1)

; enable video output
        cbi PORTB, disout       ; (2)

; -------------------------------------------------------------------------------------------------
; active video (512 cycles) [working version: 512 cycles]
; -------------------------------------------------------------------------------------------------

        output_buffer_data      ; (510)

; -------------------------------------------------------------------------------------------------
; front porch (11 cycles) [working version: 10 cycles]
; -------------------------------------------------------------------------------------------------

; restore data-bus data
        out PORTD, r8           ; (1)
; restore data-bus direction
        out DDRD, r9            ; (1)
; restore address-bus high byte
        out PORTA, r11          ; (1)
; restore address-bus low byte
        out PORTC, r12          ; (1)
; restore control signals
        out PORTB, r3           ; (1)
; restore SREG
        out SREG, r10           ; (1)
reti                            ; (4)



.include "linedata.asm"
.include "fontdata.asm"
.include "logo.asm"
.include "functions.asm"
