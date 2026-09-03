// ==============================================================================
// 6502fetch - A NeoFetch-like tool for the Commodore 64
// ==============================================================================

    BasicUpstart2(start)

start:
    // Clear screen
    jsr $e544
    
    // Copy the full-screen logo to screen RAM and color RAM
    jsr draw_logo

    // Execute detection routines
    jsr detect_sid
    jsr detect_cpu
    jsr detect_gpu
    jsr detect_memory
    jsr detect_cartridge
    jsr detect_serial
    jsr detect_tape
    jsr detect_kernal

    // Print fetch output over the logo
    jsr print_info
    
    // Return to BASIC
    rts

// ------------------------------------------------------------------------------
// Draw Logo
// ------------------------------------------------------------------------------
draw_logo:
    ldx #$00
copy_logo_loop:
    lda screen_data,x
    sta $0400,x
    lda color_data,x
    sta $d800,x

    lda screen_data+250,x
    sta $0400+250,x
    lda color_data+250,x
    sta $d800+250,x

    lda screen_data+500,x
    sta $0400+500,x
    lda color_data+500,x
    sta $d800+500,x

    lda screen_data+750,x
    sta $0400+750,x
    lda color_data+750,x
    sta $d800+750,x

    inx
    cpx #250
    bne copy_logo_loop
    rts

// ------------------------------------------------------------------------------
// Print string routine
// Pointer in $fb (low), $fc (high)
// ------------------------------------------------------------------------------
print_string:
    ldy #$00
print_string_loop:
    lda ($fb),y
    beq print_string_done
    jsr $ffd2
    iny
    bne print_string_loop
print_string_done:
    rts

move_right:
    lda #29         // CRSR RIGHT
mr_loop:
    jsr $ffd2
    dex
    bne mr_loop
    rts

// ------------------------------------------------------------------------------
// Detection Routines
// ------------------------------------------------------------------------------

// --- CPU Detection ---
// Based on korbosoft/64Fetch, detect.c lines 149-184.
detect_cpu:
    // Detect 65C816 (SuperCPU)
    lda #$00
    .byte $1a       // INC A on 65C02/65816, NOP on 6502/6510
    cmp #$01
    bne cpu_check_base
    
    // Is CMOS, check for 65816
    clc
    .byte $fb       // XCE (Exchange Carry with Emulation bit)
    bcc cpu_is_65c02   // If C is still 0, it's 65C02 (XCE does nothing)
    
    // It's 65C816!
    sec
    .byte $fb       // XCE (Restore Emulation mode)
    
    lda #<str_cpu_65c816
    sta ptr_cpu
    lda #>str_cpu_65c816
    sta ptr_cpu+1
    rts

cpu_is_65c02:
    lda #<str_cpu_65c02
    sta ptr_cpu
    lda #>str_cpu_65c02
    sta ptr_cpu+1
    rts

cpu_check_base:
    // Not CMOS. Check base 6502 family via IO port ($00)
    lda $00
    cmp #47         // Standard C64 IO direction
    bne cpu_is_6502
    
    // $00 is 47. Check for Commodore 128 (8502)
    lda $d030       // C128 clock speed register
    cmp #255
    bne cpu_is_8502 // If not 255, it's C128
    
    // It's C64 or C64C. Check SID to guess 6510 vs 8500
    lda ptr_sid
    cmp #<str_sid_8580
    bne cpu_is_6510
    lda ptr_sid+1
    cmp #>str_sid_8580
    bne cpu_is_6510
    
    // SID is 8580 -> MOS 8500 (C64C)
    lda #<str_cpu_8500
    sta ptr_cpu
    lda #>str_cpu_8500
    sta ptr_cpu+1
    rts

cpu_is_6510:
    lda #<str_cpu_6510
    sta ptr_cpu
    lda #>str_cpu_6510
    sta ptr_cpu+1
    rts

cpu_is_8502:
    lda #<str_cpu_8502
    sta ptr_cpu
    lda #>str_cpu_8502
    sta ptr_cpu+1
    rts

cpu_is_6502:
    lda #<str_cpu_6502
    sta ptr_cpu
    lda #>str_cpu_6502
    sta ptr_cpu+1
    rts

// --- GPU Detection (VIC-II PAL/NTSC) ---
detect_gpu:
gpu_sync1:
    lda $d011
    bmi gpu_sync1      // Wait until raster < 256
gpu_sync2:
    lda $d011
    bpl gpu_sync2      // Wait until raster >= 256
    
    ldx #$00
gpu_wait_max:
    lda $d012
    sta temp_raster
    cpx temp_raster
    beq gpu_update
    bcs gpu_done_max   // X > temp_raster, so raster wrapped around
gpu_update:
    ldx temp_raster
    jmp gpu_wait_max
gpu_done_max:
    // If max raster low byte > $20, it's PAL
    cpx #$20
    bcs gpu_is_pal
    
    lda #<str_gpu_ntsc
    sta ptr_gpu
    lda #>str_gpu_ntsc
    sta ptr_gpu+1
    rts
gpu_is_pal:
    lda #<str_gpu_pal
    sta ptr_gpu
    lda #>str_gpu_pal
    sta ptr_gpu+1
    rts

// --- SID Detection ---
// Source: https://web.archive.org/web/20220522192025/https://codebase64.org/doku.php?id=base:detecting_sid_type_-_safe_method
detect_sid:
    // By SounDemon - Based on a tip from Dag Lem.
    // Put together by FTC after SounDemons instructions
    // ...and tested by Rambones and Jeff.
    
    sei         // No disturbing interrupts
    lda #$ff
sid_wait_badline:
    cmp $d012   // Don't run it on a badline.
    bne sid_wait_badline
    
    // Detection itself starts here
    lda #$ff    // Set frequency in voice 3 to $ffff 
    sta $d412   // ...and set testbit (other bits don't matter) in VCREG3 ($d412) to disable oscillator
    sta $d40e
    sta $d40f
    lda #$20    // Sawtooth wave and gatebit OFF to start oscillator again.
    sta $d412
    lda $d41b   // Accu now has different value depending on sid model (6581=3/8580=2)
    lsr         // ...that is: Carry flag is set for 6581, and clear for 8580.
    bcc sid_model_8580

sid_model_6581:
    lda #<str_sid_6581
    sta ptr_sid
    lda #>str_sid_6581
    sta ptr_sid+1
    cli         // Re-enable interrupts!
    rts

sid_model_8580:
    lda #<str_sid_8580
    sta ptr_sid
    lda #>str_sid_8580
    sta ptr_sid+1
    cli         // Re-enable interrupts!
    rts

// --- Memory & REU Detection ---
detect_memory:
    // Default to 64K
    lda #<str_mem_64k
    sta ptr_mem
    lda #>str_mem_64k
    sta ptr_mem+1

    // Check for REU
    lda $df02
    pha             // Save old value
    
    lda #$55
    sta $df02
    cmp $df02
    bne mem_no_reu
    
    lda #$aa
    sta $df02
    cmp $df02
    bne mem_no_reu
    
    // Match! REU is present
    lda #<str_mem_reu
    sta ptr_mem
    lda #>str_mem_reu
    sta ptr_mem+1

mem_no_reu:
    pla
    sta $df02       // Restore old value
    rts

// --- Cartridge Detection ---
detect_cartridge:
    ldx #0
cart_check_cbm:
    lda $8004,x
    cmp str_cbm80,x
    bne cart_no_cart
    inx
    cpx #5
    bne cart_check_cbm
    
    lda #<str_cart_yes
    sta ptr_cart
    lda #>str_cart_yes
    sta ptr_cart+1
    rts

cart_no_cart:
    lda #<str_cart_no
    sta ptr_cart
    lda #>str_cart_no
    sta ptr_cart+1
    rts

// --- Serial Bus Detection ---
detect_serial:
    ldx #0
    stx serial_count
    
    lda #4
    sta current_device
    
    ldy #0
ser_serial_loop:
    lda current_device
    jsr $ffb1       // LISTEN
    lda #$ff
    jsr $ff93       // LSTNSA
    
    jsr $ffb7       // READST
    pha
    
    jsr $ffae       // UNLISTEN
    
    pla
    bmi ser_next_device // Device not present if Bit 7 is set
    
    inc serial_count
    
    // Convert current_device to ASCII string (1 or 2 digits)
    lda current_device
    cmp #10
    bcc ser_single_digit
    
    sec
    sbc #10
    pha
    lda #'1'
    sta str_serial_buf,y
    iny
    pla
ser_single_digit:
    ora #$30        // Convert to PETSCII
    sta str_serial_buf,y
    iny
    
    lda #' '
    sta str_serial_buf,y
    iny

ser_next_device:
    inc current_device
    lda current_device
    cmp #12
    bne ser_serial_loop
    
    lda #0
    sta str_serial_buf,y
    
    lda serial_count
    bne ser_has_devices
    
    lda #<str_serial_none
    sta ptr_serial
    lda #>str_serial_none
    sta ptr_serial+1
    rts

ser_has_devices:
    lda #<str_serial_buf
    sta ptr_serial
    lda #>str_serial_buf
    sta ptr_serial+1
    rts

// --- Tape Detection ---
detect_tape:
    lda $0001
    and #$10        // Bit 4 = Cassette Switch
    bne tape_no_tape
    
    lda #<str_tape_yes
    sta ptr_tape
    lda #>str_tape_yes
    sta ptr_tape+1
    rts

tape_no_tape:
    lda #<str_tape_no
    sta ptr_tape
    lda #>str_tape_no
    sta ptr_tape+1
    rts

// --- KERNAL Detection ---
// Based on korbosoft/64Fetch, detect.c lines 186-200.
detect_kernal:
    // Calculate 16-bit checksum of $E000-$FFFF
    lda #$00
    sta temp_sum
    sta temp_sum+1
    sta $fb
    lda #$e0
    sta $fc

    ldy #$00
kernal_sum_loop:
    lda ($fb),y
    clc
    adc temp_sum
    sta temp_sum
    bcc kernal_sum_skip
    inc temp_sum+1
kernal_sum_skip:
    iny
    bne kernal_sum_loop
    inc $fc
    lda $fc
    cmp #$00        // Wraps from $FF to $00
    bne kernal_sum_loop

    // Compare temp_sum against known KERNAL checksums

    // C64 KERNAL V3 ($C70A)
    lda temp_sum+1
    cmp #$c7
    bne kernal_check_v2
    lda temp_sum
    cmp #$0a
    bne kernal_check_v2
    
    lda #<str_kernal_v3
    sta ptr_kernal
    lda #>str_kernal_v3
    sta ptr_kernal+1
    rts

kernal_check_v2:
    // C64 KERNAL V2 ($C70B)
    lda temp_sum+1
    cmp #$c7
    bne kernal_check_v1
    lda temp_sum
    cmp #$0b
    bne kernal_check_v1
    
    lda #<str_kernal_v2
    sta ptr_kernal
    lda #>str_kernal_v2
    sta ptr_kernal+1
    rts

kernal_check_v1:
    // C64 KERNAL V1 ($D4FD)
    lda temp_sum+1
    cmp #$d4
    bne kernal_check_pet64
    lda temp_sum
    cmp #$fd
    bne kernal_check_pet64
    
    lda #<str_kernal_v1
    sta ptr_kernal
    lda #>str_kernal_v1
    sta ptr_kernal+1
    rts

kernal_check_pet64:
    // PET64 KERNAL ($C210)
    lda temp_sum+1
    cmp #$c2
    bne kernal_check_unknown
    lda temp_sum
    cmp #$10
    bne kernal_check_unknown
    
    lda #<str_kernal_pet64
    sta ptr_kernal
    lda #>str_kernal_pet64
    sta ptr_kernal+1
    rts

kernal_check_unknown:
    // Fallthrough to Unknown
    jmp kernal_unknown

kernal_unknown:
    // Convert temp_sum (High byte temp_sum+1, Low byte temp_sum) to Hex string in str_kernal_hex
    lda temp_sum+1
    lsr
    lsr
    lsr
    lsr
    jsr hex_to_petscii
    sta str_kernal_hex+10 // "UNKNOWN ($XXXX)" +10 offset is X1

    lda temp_sum+1
    and #$0f
    jsr hex_to_petscii
    sta str_kernal_hex+11 // X2

    lda temp_sum
    lsr
    lsr
    lsr
    lsr
    jsr hex_to_petscii
    sta str_kernal_hex+12 // X3

    lda temp_sum
    and #$0f
    jsr hex_to_petscii
    sta str_kernal_hex+13 // X4

    lda #<str_kernal_hex
    sta ptr_kernal
    lda #>str_kernal_hex
    sta ptr_kernal+1
    rts

hex_to_petscii:
    cmp #$0a
    bcc hex_is_digit
    clc
    adc #55         // 'A' is 65. 10 + 55 = 65.
    rts
hex_is_digit:
    clc
    adc #48         // '0' is 48.
    rts

// ------------------------------------------------------------------------------
// Print Info layout
// ------------------------------------------------------------------------------

print_info:
    // Go home (top-left)
    lda #19
    jsr $ffd2
    
    // Move down 2 lines to start
    lda #17
    jsr $ffd2
    jsr $ffd2

    // Line 0: Title
    ldx #15
    jsr move_right
    lda #<str_lbl_title
    sta $fb
    lda #>str_lbl_title
    sta $fc
    jsr print_string
    lda #13
    jsr $ffd2

    // Line 1: CPU
    ldx #15
    jsr move_right
    lda #<str_lbl_cpu
    sta $fb
    lda #>str_lbl_cpu
    sta $fc
    jsr print_string
    lda ptr_cpu
    sta $fb
    lda ptr_cpu+1
    sta $fc
    jsr print_string
    lda #13
    jsr $ffd2

    // Line 1.5: Kernal
    ldx #15
    jsr move_right
    lda #<str_lbl_kernal
    sta $fb
    lda #>str_lbl_kernal
    sta $fc
    jsr print_string
    lda ptr_kernal
    sta $fb
    lda ptr_kernal+1
    sta $fc
    jsr print_string
    lda #13
    jsr $ffd2

    // Line 2: GPU
    ldx #15
    jsr move_right
    lda #<str_lbl_gpu
    sta $fb
    lda #>str_lbl_gpu
    sta $fc
    jsr print_string
    lda ptr_gpu
    sta $fb
    lda ptr_gpu+1
    sta $fc
    jsr print_string
    lda #13
    jsr $ffd2

    // Line 3: Sound
    ldx #15
    jsr move_right
    lda #<str_lbl_snd
    sta $fb
    lda #>str_lbl_snd
    sta $fc
    jsr print_string
    lda ptr_sid
    sta $fb
    lda ptr_sid+1
    sta $fc
    jsr print_string
    lda #13
    jsr $ffd2

    // Line 4: Memory
    ldx #15
    jsr move_right
    lda #<str_lbl_mem
    sta $fb
    lda #>str_lbl_mem
    sta $fc
    jsr print_string
    lda ptr_mem
    sta $fb
    lda ptr_mem+1
    sta $fc
    jsr print_string
    lda #13
    jsr $ffd2

    // Line 5: Cartridge
    ldx #15
    jsr move_right
    lda #<str_lbl_cart
    sta $fb
    lda #>str_lbl_cart
    sta $fc
    jsr print_string
    lda ptr_cart
    sta $fb
    lda ptr_cart+1
    sta $fc
    jsr print_string
    lda #13
    jsr $ffd2

    // Line 6: Serial
    ldx #15
    jsr move_right
    lda #<str_lbl_ser
    sta $fb
    lda #>str_lbl_ser
    sta $fc
    jsr print_string
    lda ptr_serial
    sta $fb
    lda ptr_serial+1
    sta $fc
    jsr print_string
    lda #13
    jsr $ffd2

    // Line 7: Tape
    ldx #15
    jsr move_right
    lda #<str_lbl_tape
    sta $fb
    lda #>str_lbl_tape
    sta $fc
    jsr print_string
    lda ptr_tape
    sta $fb
    lda ptr_tape+1
    sta $fc
    jsr print_string
    lda #13
    jsr $ffd2
    jsr $ffd2
    jsr $ffd2
    jsr $ffd2
    jsr $ffd2
    jsr $ffd2

    rts

// ------------------------------------------------------------------------------
// Variables
// ------------------------------------------------------------------------------

ptr_cpu:        .byte 0, 0
ptr_gpu:        .byte 0, 0
ptr_sid:        .byte 0, 0
ptr_mem:        .byte 0, 0
ptr_cart:       .byte 0, 0
ptr_serial:     .byte 0, 0
ptr_tape:       .byte 0, 0

temp_raster:    .byte 0
temp_sum:       .byte 0, 0
ptr_kernal:     .byte 0, 0
serial_count:   .byte 0
current_device: .byte 0

// ------------------------------------------------------------------------------
// Strings and Data
// ------------------------------------------------------------------------------

str_lbl_title:  .text "6502FETCH "
                .byte 28    // Red
                .byte 211   // Heart
                .byte 154   // Light Blue
                .text " BKNACKKR '26"
                .byte 0

str_lbl_cpu:    .text "CPU: "
                .byte 0
str_lbl_kernal: .text "KERNAL: "
                .byte 0
str_lbl_gpu:    .text "GPU: "
                .byte 0
str_lbl_snd:    .text "SOUND: "
                .byte 0
str_lbl_mem:    .text "MEM: "
                .byte 0
str_lbl_cart:   .text "CART: "
                .byte 0
str_lbl_ser:    .text "SERIAL: "
                .byte 0
str_lbl_tape:   .text "TAPE: "
                .byte 0

str_cpu_6510:   .text "MOS 6510"
                .byte 0
str_cpu_65c02:  .text "WDC 65C02"
                .byte 0
str_cpu_65c816: .text "WDC 65C816 (SUPERCPU)"
                .byte 0

str_cpu_8502:   .text "MOS 8502"
                .byte 0
str_cpu_8500:   .text "MOS 8500"
                .byte 0
str_cpu_6502:   .text "MOS 6502"
                .byte 0

str_kernal_v1:  .text "C64 KERNAL V1"
                .byte 0
str_kernal_v2:  .text "C64 KERNAL V2"
                .byte 0
str_kernal_v3:  .text "C64 KERNAL V3"
                .byte 0
str_kernal_pet64: .text "PET64 KERNAL"
                .byte 0
str_kernal_hex: .text "UNKNOWN ($XXXX)"
                .byte 0

str_gpu_pal:    .text "VIC-II (PAL)"
                .byte 0
str_gpu_ntsc:   .text "VIC-II (NTSC)"
                .byte 0

str_sid_6581:   .text "MOS 6581 SID"
                .byte 0
str_sid_8580:   .text "MOS 8580 SID"
                .byte 0

str_mem_64k:    .text "64KB"
                .byte 0
str_mem_reu:    .text "64KB + REU"
                .byte 0

str_cbm80:      .byte $c3, $c2, $cd, $38, $30
str_cart_yes:   .text "DETECTED"
                .byte 0
str_cart_no:    .text "NONE"
                .byte 0

str_serial_none:.text "NONE"
                .byte 0
str_serial_buf: .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

str_tape_yes:   .text "BUTTON PRESSED"
                .byte 0
str_tape_no:    .text "INACTIVE"
                .byte 0

screen_data:
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,233,160,160,160,223,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,233,160,160,160,160,160,223,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,233,160,160,160,160,160,160,160,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,160,160,160,105,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,233,160,160,105,32,32,32,32,32,160,160,160,105,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,160,160,160,32,32,32,32,32,32,160,160,105,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,160,160,160,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,160,160,160,32,32,32,32,32,32,160,160,223,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,95,160,160,223,32,32,32,32,32,160,160,160,223,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,160,160,160,223,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,95,160,160,160,160,160,160,160,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,95,160,160,160,160,160,105,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,95,160,160,160,105,32,32,32,32,32,32,160,160,160,160,160,160,160,160,160,160,160,160,160,160,160,160,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32

color_data:
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,2,2,2,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,2,2,2,2,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
    .byte 14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
