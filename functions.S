; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>
#include <xc.inc>
#include "memory.inc"
#include "config.inc"
#include "functions.inc"

PSECT boot_functions,space=0

;-------------------------------------------------------------------------------
; Memory initializer (34 words)
; Set Flash pointer (TBLPTRU:TBLPTRH:TBLPTRL) before calling this function
; Init block structure:
;	DB size		- 0 - end marker
;	DW address	- big endian! Set MSB to address ethernet RAM 
;	DB data * size
;-------------------------------------------------------------------------------
mem_init:
	TBLRD*+					; read Flash post-increment
	MOVF	TABLAT, a, W	; size
	BZ		mem_init_done

	TBLRD*+					; read high address byte
	MOVFF	TABLAT, FSR1H
	TBLRD*+					; read low address byte
	MOVFF	TABLAT, FSR1L

mem_init_loop:
	TBLRD*+
	MOVFF	TABLAT, POSTINC1
	DECFSZ	WREG, a, W
	BRA		mem_init_loop
	BRA		mem_init

mem_init_done:
	RETURN


;-------------------------------------------------------------------------------
; Register initializer (14 words)
; Can access registers EA0 - F9F without F20
; Can be used to configure ports! :)
;
; Init block structure:
;	DB register offset to 0xF20 (-128 - 127), 0 - end marker
;	DB value
;-------------------------------------------------------------------------------
reg_init:
	LFSR	1, REG_INIT_REF
reg_init_loop:
	TBLRD*+					; read Flash post-increment
	MOVLW	LOW(MIREGADR - REG_INIT_REF)	; EB4h - F20h = 94h
	CPFSEQ	TABLAT, a
	BRA		reg_init_do
	; Wait BUSY before access to MIREGADR
mii_busy:
	; Errata: Between a write to the MIWRL and MIWRH, the core mustn't executes any
	; instruction that reads or writes to any memory address that has the
	; Least Significant six address bits of 36h (‘b11 0110)
	
	; Writing to this register automatically begins the MII transaction, so it must
	; be written to after MIWRL. The BUSY bit is set automatically after two TCY.
	BTFSC	BUSY					; MII Management Busy (MISTAT.BUSY)
	BRA		mii_busy

reg_init_do:
	MOVF	TABLAT, a, W	; address
	BZ		reg_init_done	; Done if offset == 0
	TBLRD*+					; read Flash post-increment
	MOVFF	TABLAT, PLUSW1	; Write value to FSR1 + W
	BRA		reg_init_loop

reg_init_done:
	RETURN


;-------------------------------------------------------------------------------
; Read from the Ethernet buffer to a RAM location pointed by FSR2
; W - read length, 0 will copy 256 bytes
; FSR2 - Destination pointer
; See the note at page 223 of the processor Datasheet
;-------------------------------------------------------------------------------
eth_read:
	MOVFF	EDATA, POSTINC2
	DECFSZ	WREG, W, a
	BRA		eth_read
	RETURN


;-------------------------------------------------------------------------------
; Write a data pointed by the FSR1 to the Ethernet buffer
; W - write length, 0 will copy 256 bytes
; FSR0 - Source pointer
; See the note at page 223 of the processor Datasheet
;-------------------------------------------------------------------------------
eth_write:
	MOVFF	POSTINC0, EDATA
	DECFSZ	WREG, W, a
	BRA		eth_write
	RETURN


;-------------------------------------------------------------------------------
; Send network frame
; Sends data from EWRPTH:0 to EWRPTH:EWRPTL - 1. Fill MAC addresses in ETH Header
; Use EWRPTH as packets pointer, decrements only EWRPTL to calculate end address,
; so max packet length is 255
; Function jumps to done_frame on exit
;-------------------------------------------------------------------------------

	; TODO: Bug report
	; I encountered a transmitter error. If the sent frame exceeds allowed length
	; configured in the MAMXFLH register, the transmitter cuts it and reports an
	; Abort error. The next frame will never be sent - the transmitter goes into
	; a deadlock! Resetting it before sending the next frame helps.
	; This occurred on full-duplex!
	
	; TODO: Errata workaround
	; Errata:
	; There is a small chance that the Ethernet transmit engine will internally
	; deadlock. The PHY will stop transmitting the packet and normal RX operations
	; will continue. However, the TXRTS bit will stay set indefinitely. The TXIF
	; and TXERIF bits will not become set.
	; This deadlock condition applies only to half-duplex operation

eth_send:
	; Wait for transmitter idle
	tx_wait_send

	; Set Tx start and end address based on Write Pointer
	DECF	EWRPTL, b, W	; end = write_ptr - 1
	MOVWF	ETXNDL, b
#if (TX_BUFFER_SIZE > 256) || TX_DOUBLE_BUFFERING
	MOVLW	0
	SUBWFB	EWRPTH, b, W
	MOVWF	ETXNDH, b
#endif

#if TX_DOUBLE_BUFFERING
	MOVF	TX_PAGE_REG, W
	; Set start pointer
	MOVWF	ETXSTH, b
#elif TX_BUFFER_SIZE > 256
	MOVLW	HIGH(BUF_Tx_start)
#endif

#if TX_BUFFER_SIZE > 256
	; Move write pointer to eth header
	MOVWF	EWRPTH, b
#endif

	; Move write pointer to eth header
	CLRF	EWRPTL, b
	; Can save one instruction, if we accept incrementation of RDPT
	MOVFF	EWRPTL, EDATA	; per-packet control byte

	; Set destination MAC to source MAC of received frame
	LFSR	0, RX_ADDR(mac, src)
	MOVLW	ETH_ALEN
	RCALL	eth_write

	; Set our MAC as source address
	LFSR	0, mac_addr
	MOVLW	ETH_ALEN
	RCALL	eth_write

	; DEBUG
#if 0
	CLRF	ERDPTL, a
	MOVFF	EWRPTH, ERDPTH
	LFSR	2, 0x100
	CLRF	WREG, a
	RCALL	eth_read
	
	;BTFSC 0,0,a
	;DW OPCODE_TRAP
	;BSF 0, 0, a
	
#endif

	; Start the transmission process by setting the TXRTS bit (ECON1<3>).
	BSF		TXRTS			; ECON1 = FD2
	BRA	done_frame
	

;-------------------------------------------------------------------------------
; Compare memory, return to done_frame on mismatch
; W - compare length, 0 will compare 256 bytes
; FSR0, FSR1 - Pointers to data
; Function jumps to done_frame if the memory differs
; Uses temp0!
;-------------------------------------------------------------------------------
memcmp:
	MOVWF	VAR8(temp0)

memcmp_continue:
	; Compare
	MOVF	POSTINC0, a, W
	XORWF	POSTINC1, a, W
GLOBAL done_frame_pop_bra
	; Detected dfferent value. pop return address from stack and drop packet
	BNZ		done_frame_pop_bra

	; Loop control
	DECF	VAR8(temp0), f
	BNZ		memcmp_continue
	RETURN


;-------------------------------------------------------------------------------
; Copy memory
; W - data length, 0 will copy 256 bytes
; FSR0 - Source poiner
; FSR1 - Destination pointer
;-------------------------------------------------------------------------------
memcpy:
	MOVFF	POSTINC0, POSTINC1
	DECF	WREG, W, a
	BNZ		memcpy
	RETURN


;-------------------------------------------------------------------------------
; IP Checksum
; Super simple implementation. Operates on words only.
; FSR0 - Source pointer
; WREG - words count, 0 will compute 256 words
; Uses temp0!
; Can save 1 instruction, but will use 3 more cycles per word.
;-------------------------------------------------------------------------------
#if 0
; Budget version, 1 instruction less, 3 more cycles per word
ip_checksum:						; 11 instructions
	MOVWF	VAR8(temp0)

ip_checksum_continue:
	MOVF	POSTINC0, a, W
	ADDWF	VAR16(checksum, H), f
	MOVF	POSTINC0, a, W
	ADDWFC	VAR16(checksum, L), f			; Store MSB in Carry!

	; Store carry in sum
	MOVLW	0
	ADDWFC	VAR16(checksum, H), f
	ADDWFC	VAR16(checksum, L), f

	; Loop control
	DECF	VAR8(temp0), f
	BNZ		ip_checksum_continue
	RETURN
#else
; Premium version, 1 more instruction, 3 cycles per word less.
ip_checksum:						; 12 instructions
	MOVWF	VAR8(temp0)
	BCF		CARRY					; Clear carry flag

ip_checksum_continue:
	MOVF	POSTINC0, a, W
	ADDWFC	VAR16(checksum, H), f
	MOVF	POSTINC0, a, W
	ADDWFC	VAR16(checksum, L), f

	DECFSZ	VAR8(temp0), f			; Decrement Skip if 0 - no carry flag modification
	BRA		ip_checksum_continue

	MOVLW	0
	ADDWFC	VAR16(checksum, H), f
	ADDWFC	VAR16(checksum, L), f
	RETURN
#endif


#if IP_HEADER_FAST_CHECKSUM
;-------------------------------------------------------------------------------
; IP Header Checksum
; Huge, super fast checksum for ip header only (20 bytes)
; FSR0 - Source pointer
;-------------------------------------------------------------------------------
ip_header_checksum_fun:						; 44 instructions
	; Process first word
	MOVF	POSTINC0, a, W
	ADDWF	VAR16(checksum, H), f
	MOVF	POSTINC0, a, W
	ADDWFC	VAR16(checksum, L), f

	; Process the remaining 9 words
REPT 9
	MOVF	POSTINC0, a, W
	ADDWFC	VAR16(checksum, H), f
	MOVF	POSTINC0, a, W
	ADDWFC	VAR16(checksum, L), f
ENDM

	; Store carry in sum
	MOVLW	0
	ADDWFC	VAR16(checksum, H), f
	ADDWFC	VAR16(checksum, L), f

	RETURN
#endif /* IP_HEADER_FAST_CHECKSUM */


#if ETH_CHECKSUM_MODE == 0
;-------------------------------------------------------------------------------
; IP Checksum ethernet buffer
; Super simple implementation. Operates on words only.
; check_lenH:check_lenL - data length in bytes.
; Operate on word only. 0 will compute 256 words
; Uses temp0!
; Can save 1 instruction, if called always with cleared carry flag.
; 12 + 3 = 15 instructions
;-------------------------------------------------------------------------------
eth_checksum:
	; Divide UDP length by 2 - length in words - stored in W!
	BCF		CARRY			; Clear carry flag
	RRCF	VAR16(check_len, H), W
	RRCF	VAR16(check_len, L), W

; Premium version, 1 more instruction, 3 cycles per word less.
eth_checksum_words:
	MOVWF	VAR8(temp0)
	BCF		CARRY					; Clear carry flag

eth_checksum_continue:
	MOVF	EDATA, a, W
	ADDWFC	VAR16(checksum, H), f
	MOVF	EDATA, a, W
	ADDWFC	VAR16(checksum, L), f

	DECFSZ	VAR8(temp0), f				; Decrement Skip if 0 - no carry flag modification
	BRA		eth_checksum_continue

	MOVLW	0
	ADDWFC	VAR16(checksum, H), f
	ADDWFC	VAR16(checksum, L), f
	RETURN


#elif ETH_CHECKSUM_MODE == 1
;-------------------------------------------------------------------------------
; IP Checksum ethernet buffer with byte support
; check_len - data length in bytes.
; Can save 1 instruction, but will use 3 more cycles per word.
; Uses temp0
; 26 instructions
;-------------------------------------------------------------------------------
; Premium version, 1 more instruction, 3 cycles per word less.
eth_checksum:
	MOVFF	VAR16_ADDR(check_len, L), VAR8_ADDR(temp0)
	BCF		CARRY						; Clear carry flag
	RRCF	VAR16(check_len, H), f		; size >>= 1;
	RRCF	VAR16(check_len, L), f
	BCF		CARRY						; Clear carry flag, BCF not touch flags
	BNZ		eth_checksum_loop			; Z flag set by RRCF

eth_checksum_loop_check:				; check_lenL is 0
	MOVF	VAR16(check_len, H), f
	BZ		eth_checksum_loop_done
	DECFSZ	VAR16(check_len, H), f		; Decrement Skip if 0 - no carry flag modification
	NOP

eth_checksum_loop:
	MOVF	EDATA, a, W
	ADDWFC	VAR16(checksum, H), f
	MOVF	EDATA, a, W
	ADDWFC	VAR16(checksum, L), f

	DCFSNZ	VAR16(check_len, L), f		; Decrement Skip if not 0 - no carry flag modification
	BRA		eth_checksum_loop_check
	BRA		eth_checksum_loop

eth_checksum_loop_done:
	MOVLW	0
	BTFSC	VAR_BIT(temp0, 0)
	MOVF	EDATA, a, W
	ADDWFC	VAR16(checksum, H), f
	MOVLW	0
	ADDWFC	VAR16(checksum, L), f
	ADDWFC	VAR16(checksum, H), f
	RETURN


#elif ETH_CHECKSUM_MODE == 2
;-------------------------------------------------------------------------------
; IP Checksum ethernet buffer
; Fast implementation, operates on double words, words, support byte
; check_lenH:check_lenL - data length in bytes.
; Uses temp0!
; 46 instructions
;-------------------------------------------------------------------------------
eth_checksum:
    MOVFF   VAR16_ADDR(check_len, L), VAR8_ADDR(temp0)
    BCF     CARRY                   ; Clear carry flag
    RRCF    VAR16(check_len, H), f        ; size >>= 1;
    RRCF    VAR16(check_len, L), f
    BCF     CARRY                   ; Clear carry flag
    RRCF    VAR16(check_len, H), f        ; size >>= 1;
    RRCF    VAR16(check_len, L), f

    BCF     CARRY                   ; Clear carry flag
    MOVF    VAR16(check_len, L), f
    BNZ     eth_checksum_dword

eth_checksum_check_dword:                         ; sizeL is 0
    MOVF    VAR16(check_len, H), f
    BZ      eth_checksum_check_word
    DECFSZ  VAR16(check_len, H), f           ; Decrement Skip if 0 - no carry flag modification
    NOP

eth_checksum_dword:
	MOVF	EDATA, a, W
    ADDWFC  VAR16(checksum, H), f
    MOVF	EDATA, a, W
    ADDWFC  VAR16(checksum, L), f
	MOVF	EDATA, a, W
    ADDWFC  VAR16(checksum, H), f
    MOVF	EDATA, a, W
    ADDWFC  VAR16(checksum, L), f

    DCFSNZ  VAR16(check_len, L), f           ; Decrement Skip if not 0 - no carry flag modification
    BRA     eth_checksum_check_dword
    BRA     eth_checksum_dword

eth_checksum_check_word:
    ; Handle single word
    BTFSS   VAR_BIT(temp0, 1)
    BRA     eth_checksum_check_byte

	MOVF	EDATA, a, W
    ADDWFC  VAR16(checksum, H), f
    MOVF	EDATA, a, W
    ADDWFC  VAR16(checksum, L), f

eth_checksum_check_byte:
    BTFSC   VAR_BIT(temp0, 0)
    BRA     eth_checksum_single_byte
	; No byte
    MOVLW   0
    ADDWFC  VAR16(checksum, H), f
    ADDWFC  VAR16(checksum, L), f
    RETURN

eth_checksum_single_byte:
    MOVF	EDATA, a, W
    ADDWFC  VAR16(checksum, H), f
    MOVLW   0
    ADDWFC  VAR16(checksum, L), f
    ADDWFC  VAR16(checksum, H), f
    RETURN
#else /* ETH_CHECKSUM_MODE == 2 */
	ERROR "Invalid ETH_CHECKSUM_MODE value!"
#endif
