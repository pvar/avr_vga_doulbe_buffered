
; **************************************************
; fill active buffer with vertical color lines
; **************************************************

tst1:
        cbi PORTB, ramread      ; set SRAM WRITE mode
        occupy_dbus             ; take control of data bus

        out PORTA, zero
        out PORTC, zero
        out PORTD, zero

        ldi tmp2, 240
tst1_lp1:
        clr tmp1
tst1_lp2:
        out PORTC, tmp1
        out PORTD, tmp1
        dec tmp1
        brne tst1_lp2

        in tmp1, PORTA
        inc tmp1
        out PORTA, tmp1
        dec tmp2
        brne tst1_lp1

        release_dbus            ; release data bus
        sbi PORTB, ramread      ; set SRAM READ mode
ret



; **************************************************
; put color dots on "corners" of active buffer
; **************************************************

tst2:
        cbi PORTB, ramread      ; set SRAM WRITE mode
        occupy_dbus             ; take control of data bus

        ldi tmp1, 0b00000011    ; red
        out PORTA, zero
        out PORTC, zero
        out PORTD, tmp1

        ldi tmp1, 0b00001100    ; green
        ldi tmp2, 255
        out PORTA, zero
        out PORTC, tmp2
        out PORTD, tmp1

        ldi tmp1, 0b00110000    ; blue
        ldi tmp2, 239
        out PORTA, tmp2
        out PORTC, zero
        out PORTD, tmp1

        ldi tmp1, 0b11111111    ; white
        out PORTA, tmp2
        ldi tmp2, 255
        out PORTC, tmp2
        out PORTD, tmp1

        release_dbus            ; release data bus
        sbi PORTB, ramread      ; set SRAM READ mode
ret



; **************************************************
; clear active buffer
; **************************************************

clear:
        cbi PORTB, ramread      ; set SRAM WRITE mode
        occupy_dbus             ; take control of data bus

        out PORTA, zero
        out PORTC, zero
        out PORTD, zero

        ldi tmp2, 240
clr1:
        clr tmp1
clr2:
        out PORTC, tmp1
        dec tmp1
        brne clr2

        in tmp1, PORTA
        inc tmp1
        out PORTA, tmp1
        dec tmp2
        brne clr1

        release_dbus            ; release data bus
        sbi PORTB, ramread      ; set SRAM READ mode
ret



; **************************************************
; moves cursor to an arbitary location
; tmp1: line [0..23]
; tmp2: column [0..31]
; **************************************************

locate:
        mov cursorX, tmp2
        ldi tmp2, 8
        mul cursorX, tmp2
        mov cursorX, r0

        mov cursorY, tmp1
        ldi tmp1, 10
        mul cursorY, tmp1
        mov cursorY, r0
ret



; **************************************************
; moves cursor one position to the right
; **************************************************

right:
        ldi tmp2, 8
        add cursorX, tmp2
        brne next_end

        ldi tmp2, 10
        add cursorY, tmp2
        ldi tmp2, 240
        cp cursorY, tmp2
        brne next_end

        ldi tmp2, 230
        mov cursorY, tmp2
        ldi tmp2, 248
        mov cursorX, tmp2
next_end:
ret



; **************************************************
; moves cursor one position to the left
; **************************************************

left:
        ldi tmp2, 8
        sub cursorX, tmp2
        ldi tmp2, 248
        cp cursorX, tmp2
        brne prev_end

        ldi tmp2, 10
        sub cursorY, tmp2
        ldi tmp2, 231
        cp cursorY, tmp2
        brlo prev_end
        clr cursorY
        clr cursorX
prev_end:
ret



; **************************************************
; moves cursor one line up
; **************************************************

up:
        mov tmp1, cursorY
        tst tmp1
        breq up_end
        subi tmp1, 10
        mov cursorY, tmp1
up_end:
ret



; **************************************************
; moves cursor one line down
; **************************************************

down:
        mov tmp1, cursorY
        cpi tmp1, 230
        breq down_end
        subi tmp1, -10
        mov cursorY, tmp1
down_end:
ret



; **************************************************
; prints a character at current cursor position
; tmp1: character to be printed
; **************************************************

print:
        ldi ZH, high(fontdata*2)
        ldi ZL, low(fontdata*2)

        subi tmp1, 32           ; font table misses first 32 characters

        ldi tmp2, 10            ;
        mul tmp1, tmp2          ; calculate pointer offset

        add ZL, r0              ;
        adc ZH, r1              ; add offset to pointer

        ldi tmp3, 10            ;
        out PORTA, cursorY      ;
        out PORTC, cursorX      ; set "target" address before enabling SRAM WRITE mode

        cbi PORTB, ramread      ; set SRAM WRITE mode
        occupy_dbus             ; take control of data bus

get_font_byte:
        lpm r0, Z+

        out PORTC, cursorX

        ldi tmp2, 8
parse_bits:
        clr tmp1
        sbrc r0, 7
        mov tmp1, color
        out PORTD, tmp1

        lsl r0

        dec tmp2
        breq print_next_line
        in r1, PORTC
        inc r1
        out PORTC, r1
        rjmp parse_bits

print_next_line:
        dec tmp3
        breq print_end
        in r1, PORTA
        inc r1
        out PORTA, r1
        rjmp get_font_byte

print_end:
        release_dbus            ; release data bus
        sbi PORTB, ramread      ; set SRAM READ mode
ret



; **************************************************
; roll frame buffer one text-line up
; **************************************************

roll:
        clr tmp1                ; frame buffer line to write
        ldi tmp2, 10            ; frame buffer line to read
        clr tmp3

rl_copy_lines:
        ldi YH, scratchH
        ldi YL, scratchL
        clr tmp4
rl_get_next:
        out PORTA, tmp2
rl_get_line:
        out PORTC, tmp3
        nop
        nop
        nop
        nop
        in r0, PIND
        st Y+, r0

        inc tmp3
        brne rl_get_line
        inc tmp2
        inc tmp4
        cpi tmp4, 10
        brne rl_get_next

        ldi YH, scratchH
        ldi YL, scratchL
        clr tmp4
rl_put_next:
        out PORTA, tmp1
rl_put_line:
        out PORTC, tmp3
        ser XL
        out DDRD, XL
        ld r0, Y+
        out PORTD, r0
        cbi PORTB, ramread      ; set SRAM WRITE mode
        nop
        nop
        nop
        nop
        sbi PORTB, ramread      ; set SRAM READ mode
        out DDRD, zero

        inc tmp3
        brne rl_put_line
        inc tmp1
        inc tmp4
        cpi tmp4, 10
        brne rl_put_next

        cpi tmp2, 240
        brne rl_copy_lines

        ser tmp3
        out DDRD, tmp3
        out PORTD, zero
        cbi PORTB, ramread      ; set SRAM WRITE mode
        ldi tmp1, 230
rl_clr_line:
        out PORTA, tmp1
        clr tmp2
rl_clr_pixel:
        out PORTC, tmp2
        nop
        inc tmp2
        brne rl_clr_pixel
        inc tmp1
        cpi tmp1, 240
        brne rl_clr_line
        sbi PORTB, ramread      ; set SRAM READ mode
ret



; **************************************************
; copy splash from program memory to frame buffer
; **************************************************

splash:
        ldi tmp1, 90
        ldi ZH, high(logo*2)
        ldi ZL, low(logo*2)
sp_put_line:
        out PORTA, tmp1
        ldi tmp2, 45
sp_put_pixel:
        out PORTC, tmp2

        ser XL
        out DDRD, XL
        lpm r0, Z+
        out PORTD, r0
        cbi PORTB, ramread      ; set SRAM WRITE mode
        nop
        sbi PORTB, ramread      ; set SRAM READ mode
        out DDRD, zero

        inc tmp2
        cpi tmp2, 211
        brne sp_put_pixel

        inc tmp1
        cpi tmp1, 130
        brne sp_put_line
ret



; **************************************************
; freeze program for about (100 * tmp1)ms
; **************************************************

delay:
        clr timer
wait_timer:
        nop
        cp timer, tmp1
        brne wait_timer
ret
