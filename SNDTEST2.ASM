;
; NES sound testing program
; Written by SnowBro
;
; The joypad buttons do the following:
;
;   Select: Select channel
;   Up/Down:    Select register of current channel
;   Right/Left: Select bit of current register
;   A:  Toggle current bit
;   Start:  Play channel
;
; Modify the code as you wish.

;
; Kent Hansen 01/01/99
;


; rewritten, 9/24/2019 by Doug Fraker
; borrowing from neslib (by Shiru)
; assembles with NESASM3
; works on real NES


; NOTE, the most significant bit of the frequency of
; Pulse channels (channels 0 and 1)
; FREQ HI 0000 0100 (this bit)
; won't work unless you also set THIS bit in the
; SWEEP 0000 1000
; or just set all but the first bit of the 
; SWEEP 0111 1111
; ...to play the lowest octave of notes


  .inesprg 1   ; 1x 16KB PRG code
  .ineschr 1   ; 1x  8KB CHR data
  .inesmap 0   ; mapper 0 = NROM, no bank swapping
  .inesmir 1   ; background mirroring
  
  
  .BANK 0
  .ORG $c000  

;------------------------------[ Define stuff ]-------------------------------

PPU_CTRL	EQU $2000
PPU_MASK	EQU $2001
PPU_STATUS	EQU $2002
PPU_OAM_ADDR EQU $2003
PPU_OAM_DATA EQU $2004
PPU_SCROLL	EQU $2005
PPU_ADDR	EQU $2006
PPU_DATA	EQU $2007
PPU_OAM_DMA	EQU $4014
PPU_FRAMECNT EQU $4017
DMC_FREQ	EQU $4010
CTRL_PORT1	EQU $4016
CTRL_PORT2	EQU $4017

OAM_BUF		EQU $0200

RIGHT_BUTTON    EQU %00000001
LEFT_BUTTON EQU %00000010
DOWN_BUTTON EQU %00000100
UP_BUTTON   EQU %00001000
START_BUTTON    EQU %00010000
SELECT_BUTTON   EQU %00100000
B_BUTTON    EQU %01000000
A_BUTTON    EQU %10000000

; Zero page addresses for where to store data

SND_REGS    EQU $00 ; data for 4 channels, 4 bytes each
CUR_CHN     EQU $10 ; current channel (0...3)
CUR_REG     EQU $11 ; current register of channel (0...3)
CUR_BIT     EQU $12 ; current bit of register
frame_count EQU $13
PPU_CTRL_VAR EQU $14
PPU_MASK_VAR EQU $15
SCROLL_X	EQU $16
SCROLL_Y	EQU $17
new_channel_flag EQU $18
pointer		EQU $19
; and address $1a

JOY_STAT    EQU $FC ; byte containing status of joypad
OLD_STAT    EQU $FD ; joypad status from previous refresh
ADDR_LO     EQU $FE
ADDR_HI     EQU $FF


chn_text:
  .db $03,$08,$01,$0e,$0e,$05,$0c,$2a,$00,$20
  .db $ff ; channel: 0 Pulse 1
  


palette:    
; background palette
  .db $0f,$0f,$0f,$30 ; $0f is black, $30 is white
  .db $0f,$0f,$0f,$30
  .db $0f,$0f,$0f,$30
  .db $0f,$0f,$0f,$30

; sprite palette
  .db $0f,$0f,$0f,$11 ; $11 is blue
  .db $0f,$0f,$0f,$30
  .db $0f,$0f,$0f,$30
  .db $0f,$0f,$0f,$30
  
  

;---------------------------------[ Code ]------------------------------------

reset:
	sei
	cld
	ldx #$40
	stx CTRL_PORT2
    ldx #$ff
    txs
    inx ; x is zero
    stx PPU_MASK
    stx DMC_FREQ
    stx PPU_CTRL	
	
initPPU:
    bit PPU_STATUS
.1:
    bit PPU_STATUS
    bpl .1
.2:
    bit PPU_STATUS
    bpl .2

clearPalette:
	lda #$3f
	sta PPU_ADDR
	stx PPU_ADDR ; PPU ADDRESS $3f00
	lda #$0f ; black
	ldx #$20 ; loop 32 times
.1:
	sta PPU_DATA
	dex
	bne .1

clearVRAM:
	txa ; a,x are zero
	ldy #$20
	sty PPU_ADDR
	sta PPU_ADDR ; PPU ADDRESS $2000
	ldy #$10 ; loop 16 * 256 times
.1:
	sta PPU_DATA
	inx
	bne .1
	dey
	bne .1

clearRAM:
    txa ; x = 0
.1:
    sta $000, x
    sta $100, x
    sta $200, x
    sta $300, x
    sta $400, x
    sta $500, x
    sta $600, x
    sta $700, x
    inx
    bne .1	; loop 256 times
	
	

	jsr set_palette
	jsr setup_screen ; writes some text info to the name table

	lda #%00011110 ; enable bg & sprites
	sta PPU_MASK_VAR ; will write to register at first nmi

	lda #%10000000 ; enable NMI, sprites and bg use tileset #0, use nametable #0
	sta PPU_CTRL_VAR
	sta PPU_CTRL   
	
	lda #$00
	sta SCROLL_X
	sta SCROLL_Y ; will write to register at first nmi
	
	
	

main_loop:
	lda frame_count
wait_frame:
	cmp frame_count
	beq wait_frame
	
	lda JOY_STAT
	sta OLD_STAT
	jsr read_joypad

	jsr print_regs  ; print the regs in binary format

	lda new_channel_flag
	beq skip_reprint
	jsr reprint_channel_num
skip_reprint:
	
	lda #0			; after all ppu writes, reset the scroll position
	sta PPU_ADDR
	sta PPU_ADDR
	lda <SCROLL_X
	sta PPU_SCROLL	; scroll register is write twice
	lda <SCROLL_Y
	sta PPU_SCROLL
	lda <PPU_CTRL_VAR
	sta PPU_CTRL
	lda <PPU_MASK_VAR
	sta PPU_MASK
	
	jsr set_cursors ; show the ChannelCursor and BitCursor
	
	

; button presses

	lda #RIGHT_BUTTON
	and JOY_STAT
	beq .1
	and OLD_STAT ; If this AND results in a non-zero result, it means
	bne .1    ; the button was pressed last refresh too, so do nothing.
	jsr button_right   ; Do appropriate action for this button
.1:   ; Repeat for the other 7 buttons...
	lda #LEFT_BUTTON
	and JOY_STAT
	beq .2
	and OLD_STAT
	bne .2
	jsr button_left
.2:
	lda #DOWN_BUTTON
	and JOY_STAT
	beq .3
	and OLD_STAT
	bne .3
	jsr button_down
.3:
	lda #UP_BUTTON
	and JOY_STAT
	beq .4
	and OLD_STAT
	bne .4
	jsr button_up
.4:
	lda #START_BUTTON
	and JOY_STAT
	beq .5
	and OLD_STAT
	bne .5
	jsr button_start
.5:
	lda #SELECT_BUTTON
	and JOY_STAT
	beq .6
	and OLD_STAT
	bne .6
	jsr button_select
.6:
	lda #A_BUTTON
	and JOY_STAT
	beq .7
	and OLD_STAT
	bne .7
	jsr button_a
.7:
	lda #B_BUTTON
	and JOY_STAT
	beq .8
	and OLD_STAT
	bne .8
	jsr button_b
.8:  
	jmp main_loop
	
	

;-----------------------------------------------------------------------------

button_right: ; shift cursor right
	dec CUR_BIT
	lda CUR_BIT
	and #$07 ; 0-7
	sta CUR_BIT
	rts

button_left: ; shift cursor left
	inc CUR_BIT
	lda CUR_BIT
	and #$07 ; 0-7
	sta CUR_BIT
	rts

button_down: ; shift cursor down
	inc CUR_REG
	lda CUR_REG
	and #$03 ; 0-3
	sta CUR_REG
	rts

button_up: ; shift cursor up
	dec CUR_REG
	lda CUR_REG
	and #$03 ; 0-3
	sta CUR_REG
	rts

button_start: ; play current sound channel
	lda #$01
	ldx CUR_CHN
	beq .2 ; if channel 0, skip, keep A = $01
.1:
	asl a ; else shift it left, A = 2,4, or 8
	dex
	bne .1
.2:
	; channels 000d nt21
	; d = dmc
	; n = noise
	; t = triangle
	; 2 = pulse 2
	; 1 = pulse 1
	sta $4015   ; only activate the current sound channel

	
; copy the sound registers from RAM to APU	
	ldy #$10 ; loop 16 times
	ldx #$00
.3:
	lda SND_REGS, x
	sta $4000, x
	inx
	dey
	bne .3
	rts

button_select: ; change sound channel
	inc CUR_CHN
	lda CUR_CHN
	and #$03 ; 0-3
	sta CUR_CHN
	
	lda #1
	sta new_channel_flag ; set flag to draw channel # next frame
	rts
	
reprint_channel_num:
	lda #$20
	sta PPU_ADDR
	lda #$6b
	sta PPU_ADDR ; PPU ADDRESS $206b
	lda CUR_CHN ; print the current channel # at top
	ora #$20
	sta PPU_DATA
	
	lda #0
	sta new_channel_flag
	
;	jsr write_channel_name
;	rts
; a jsr immediately followed by rts can be replaced with jmp
	jmp write_channel_name 

	

button_a: ; flip current bit
	lda #$01
	ldx CUR_BIT
	beq .2
	clc
.1:
	asl a
	dex
	bne .1
.2:
	pha
	lda CUR_CHN
	asl a
	asl a
	clc
	adc CUR_REG
	tax
	pla
	eor SND_REGS, x ; flip that bit
	sta SND_REGS, x
	rts

button_b:
	rts
	
	
	

;-----------------------------------------------------------------------------

print_regs:
	lda #$20
	sta ADDR_HI
	lda #$ca
	sta ADDR_LO

	lda CUR_CHN
	asl a
	asl a
	tax

print_one_reg:
	lda ADDR_HI
	sta PPU_ADDR
	lda ADDR_LO
	sta PPU_ADDR ; PPU ADDRESS $20ca
	lda SND_REGS, x
	ldy #$08 ; inner loop 8 times
.1:
	asl a
	pha
	lda #$00
	rol a
	ora #$20
	sta PPU_DATA
	pla
	dey
	bne .1
	
	lda ADDR_LO
	clc
	adc #$40
	sta ADDR_LO
	bcc .2
	inc ADDR_HI
.2:
	inx
	txa
	and #$03
	bne print_one_reg ; outer loop 4 times
	rts
	

; sprites, put them in a buffer, to be copied to OAM during v-blank (nmi)
set_cursors:
	lda CUR_REG
	asl a
	asl a
	asl a
	asl a
	clc
	adc #$2f ; y position 30
	sta OAM_BUF
	lda #$30 ; tile #
	sta OAM_BUF+1
	lda #$00 ; attributes / palette
	sta OAM_BUF+2
	lda #$46 	; x position
	sta OAM_BUF+3

	lda CUR_REG
	asl a
	asl a
	asl a
	asl a
	clc
	adc #$37 ; y position 38
	sta OAM_BUF+4
	lda #$31 ; tile #
	sta OAM_BUF+5
	lda #$00 ; attributes / palette
	sta OAM_BUF+6
	lda CUR_BIT
	eor #$07
	asl a
	asl a
	asl a
	clc
	adc #$4f	; x position
	sta OAM_BUF+7 
	rts

	
setup_screen:
	lda #$20
	sta PPU_ADDR
	lda #$62
	sta PPU_ADDR ; PPU ADDRESS $2062
	ldx #$00
.1:
	lda chn_text, x ; write "channel: 0"
	cmp #$FF ; end loop when see $ff tag
	beq end_text
	sta PPU_DATA
	inx
	bne .1
end_text:

	lda #$20
	sta ADDR_HI
	lda #$C2
	sta ADDR_LO
	ldy #$20
.1:
	lda ADDR_HI
	sta PPU_ADDR
	lda ADDR_LO
	sta PPU_ADDR ; PPU ADDRESS $20c2
	lda #$12    ; "R"
	sta PPU_DATA
	lda #$05    ; "E"
	sta PPU_DATA
	lda #$07    ; "G"
	sta PPU_DATA
	lda #$00    ; " "
	sta PPU_DATA
	sty PPU_DATA
	lda #$2A    ; ":"
	sta PPU_DATA
	lda ADDR_LO
	clc
	adc #$40
	sta ADDR_LO
	bcc .2
	inc ADDR_HI
.2:
	iny
	cpy #$24 ; loop 4 times
	bne .1
	

; more setup, write some words to the screen
	lda $2002
	lda #$20
	sta PPU_ADDR
	lda #$d4
	sta PPU_ADDR ; PPU ADDRESS $20d4
	ldx #0
	ldy #6 ; loop 6 times
.3:
	lda vol_text, x
	sta PPU_DATA
	inx
	dey
	bne .3
	
	lda #$21
	sta PPU_ADDR
	lda #$14
	sta PPU_ADDR ; PPU ADDRESS $2114
	ldx #0
	ldy #5 ; loop 5 times
.4:
	lda sweep_text, x
	sta PPU_DATA
	inx
	dey
	bne .4
	
	lda #$21
	sta PPU_ADDR
	lda #$54
	sta PPU_ADDR ; PPU ADDRESS $2154
	ldx #0
	ldy #7 ; loop 7 times
.5:
	lda freq_text, x
	sta PPU_DATA
	inx
	dey
	bne .5
	
	lda #$21
	sta PPU_ADDR
	lda #$94
	sta PPU_ADDR ; PPU ADDRESS $2194
	ldx #0
	ldy #7 ; loop 7 times
.6:
	lda freq2_text, x
	sta PPU_DATA
	inx
	dey
	bne .6
	
;	jsr write_channel_name
;	rts
; a jsr immediately followed by rts can be replaced with jmp
	jmp write_channel_name 


	
vol_text:
  .db $16, $0f, $0c, $15, $0d, $05
  ; VOLUME
	
sweep_text:
  .db $13, $17, $05, $05, $10
  ; SWEEP
  
freq_text:
  .db $06, $12, $05, $11, $00, $0c, $0f
  ; FREQ LO
  
freq2_text:
  .db $06, $12, $05, $11, $00, $08, $09
  ; FREQ HI	
	

	
write_channel_name:
; write the name of the channel at the top
	lda #$20
	sta PPU_ADDR
	lda #$6e
	sta PPU_ADDR ; PPU ADDRESS $206e
	ldx CUR_CHN ; 0-3
	lda table_lo, x
	sta pointer
	lda table_hi, x
	sta pointer+1
	ldx #8 ; loop 8 times
	ldy #0
.1:
	lda [pointer], y
	sta PPU_DATA
	iny
	dex
	bne .1
	rts
	
	
text_pulse1:
  .db $10,$15,$0c,$13,$05,$00,$21,$00
  ; PULSE 1
  
text_pulse2:
  .db $10,$15,$0c,$13,$05,$00,$22,$00
  ; PULSE 2
  
text_triangle:
  .db $14,$12,$09,$01,$0e,$07,$0c,$05
  ; TRIANGLE
  
text_noise:
  .db $0e,$0f,$09,$13,$05,$00,$00,$00
  ; NOISE
  
table_lo:
  .db LOW(text_pulse1), LOW(text_pulse2), LOW(text_triangle), LOW(text_noise)
  
table_hi:
  .db HIGH(text_pulse1), HIGH(text_pulse2), HIGH(text_triangle), HIGH(text_noise)	
	
	

	

;wait_vblank:
;	lda PPU_STATUS
;	bpl wait_vblank
;	rts



; Read joypad
; ===========
; Returns: JOY_STAT = status of all buttons

read_joypad:
	ldy #$01
	sty $4016   ; reset strobe
	dey
	sty $4016   ; clear strobe
	sty JOY_STAT ; JOY_STAT = 0 (clear all button bits)
	ldy #$08    ; loop 8 times, for 8 buttons
read_button:
	lda $4016   ; load button status
	and #$01    ; only keep lowest bit
	lsr a   ; transfer to carry flag
	rol JOY_STAT
	dey
	bne read_button
	rts



; Set palette
; ===========

set_palette:
	lda #$3F
	sta PPU_ADDR
	lda #$00
	sta PPU_ADDR	; PPU ADDRESS $3f00
	ldx #$00
	ldy #$20 ; loop 32 times
.1:
	lda palette, x
	sta PPU_DATA
	inx
	dey
	bne .1
	rts
	
	
; do every frame, during v-blank	

nmi:
	pha     ; push A on stack

	lda #HIGH(OAM_BUF)	; push all sprites to OAM
	sta PPU_OAM_DMA		; from buffer at $200
	
	inc frame_count
	
	pla     ; restore A
irq:
	rti

; nesasm banks are $2000 in size
; we need at least 2 PRG banks of this size	
  .bank 1
  .org $fffa

  .dw nmi, reset, irq
 

 
  .bank 2
  .org $0000

; include the graphics file  
  .incbin "SNDTEST2.CHR"
  
  


