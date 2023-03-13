; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>
#include "assembler_bug_wa.inc"

;-------------------------------------------------------------------------------
; Memory initializer (34 words)
; Set Flash pointer (TBLPTRU:TBLPTRH:TBLPTRL) before calling this function
; Init block structure:
;	DB size		- 0 - end marker
;	DW address	- big endian! Set MSB to address ethernet RAM 
;	DB data * size
;-------------------------------------------------------------------------------
GLOBAL mem_init

;-------------------------------------------------------------------------------
; Register initializer (14 words)
; Can access registers EA0 - F9F without F20
; Can be used to configure ports! :)
;
; Init block structure:
;	DB register offset to 0xF20 (-128 - 127), 0 - end marker
;	DB value
;-------------------------------------------------------------------------------
GLOBAL reg_init

;-------------------------------------------------------------------------------
; Read from the Ethernet buffer to a RAM location pointed by FSR2
; W - read length, 0 will copy 256 bytes
; FSR2 - Destination pointer
; See the note at page 223 of the processor Datasheet
;-------------------------------------------------------------------------------
GLOBAL eth_read

;-------------------------------------------------------------------------------
; Write a data pointed by the FSR1 to the Ethernet buffer
; W - write length, 0 will copy 256 bytes
; FSR0 - Source pointer
; See the note at page 223 of the processor Datasheet
;-------------------------------------------------------------------------------
GLOBAL eth_write

;-------------------------------------------------------------------------------
; Send network frame
; Sends data from EWRPTH:0 to EWRPTH:EWRPTL - 1. Fill MAC addresses in ETH Header
; Use EWRPTH as packets pointer, decrements only EWRPTL to calculate end address,
; so max packet length is 255
; Function jumps to done_frame on exit
;-------------------------------------------------------------------------------
GLOBAL eth_send

; Return point
GLOBAL done_frame

;-------------------------------------------------------------------------------
; Compare memory, return to done_frame on mismatch
; W - compare length, 0 will compare 256 bytes
; FSR0, FSR1 - Pointers to data
; Function jumps to done_frame if the memory differs
; Uses temp0!
;-------------------------------------------------------------------------------
GLOBAL memcmp

;-------------------------------------------------------------------------------
; Copy memory
; W - data length, 0 will copy 256 bytes
; FSR0 - Source poiner
; FSR1 - Destination pointer
;-------------------------------------------------------------------------------
GLOBAL memcpy

;-------------------------------------------------------------------------------
; IP Checksum
; Super simple implementation. Operates on words only.
; FSR0 - Source pointer
; WREG - words count, 0 will compute 256 words
; Uses temp0!
; Can save 1 instruction, but will use 3 more cycles per word.
;-------------------------------------------------------------------------------
GLOBAL ip_checksum

;-------------------------------------------------------------------------------
; IP Checksum ethernet buffer
; Super simple implementation. Operates on words only.
; check_lenH:check_lenL - data length in bytes.
; Operate on word only. 0 will compute 256 words
; Uses temp0!
; Can save 1 instruction, if called always with cleared carry flag.
; 12 + 3 = 15 instructions
;-------------------------------------------------------------------------------
GLOBAL eth_checksum_byte

;-------------------------------------------------------------------------------
; IP Checksum ethernet buffer
; Super simple implementation. Operates on words only.
; WREG - words count, 0 will compute 256 words
; Uses temp0!
; Can save 1 instruction, but will use 3 more cycles per word.
; 12 instructions
;-------------------------------------------------------------------------------
; Premium version, 1 more instruction, 3 cycles per word less.
GLOBAL eth_checksum

;-------------------------------------------------------------------------------
; Ethernet transmit buffer helper macros
;-------------------------------------------------------------------------------
; Places the value of the higher byte of the start address of the transmit buffer in WREG. 
eth_tx_high_byte MACRO pos
#if TX_DOUBLE_BUFFERING
	MOVF	TX_PAGE_REG, W
#else
	MOVLW	HIGH(pos)
#endif
ENDM

; Switch to next transmit buffer
; Can save one instruction, but will requre init tx_page. Move tx_page to 
tx_switch_buffer MACRO
#if TX_DOUBLE_BUFFERING
	; While the transmission is in progress, the ETXST and ETXND Pointers should not be modified.

	; Toggle buffer select bit
	BTG		BANKMASK(TX_PAGE_ADDR), TX_PAGE_BIT, TX_PAGE_ACCESS
	MOVF	TX_PAGE_REG, W
#elif TX_BUFFER_SIZE > 256
	MOVLW	HIGH(BUF_Tx_start)
#endif

#if (TX_BUFFER_SIZE > 256) || TX_DOUBLE_BUFFERING
	; Set write pointer high byte to packet start
	MOVWF	EWRPTH, b
#endif
ENDM

eth_get_tx_len_l MACRO
	MOVLW	LOW(TX_PROTO(udp))
	SUBWF	EWRPTL, b, W
ENDM

eth_get_tx_len_h MACRO
#if TX_BUFFER_SIZE == 256
	CLRF WREG, a
#else
	eth_tx_high_byte	TX_PROTO(udp)
	SUBWFB	EWRPTH, b, W
#endif
ENDM

; Set ethernet read pointer to prepared tx data
eth_read_pos MACRO pos
	eth_tx_high_byte	pos
	MOVWF	ERDPTH, a
	MOVLW	LOW(pos)
	MOVWF	ERDPTL, a
ENDM

; Set ethernet write pointer (low address only)
eth_write_pos MACRO pos
	MOVLW	LOW(pos)
	MOVWF	EWRPTL, b
ENDM

; Set ethernet write pointer, use when write pointer high byte may be moved
eth_write_pos_ex MACRO pos
#if TX_BUFFER_SIZE > 256
	eth_tx_high_byte	pos
	MOVWF	EWRPTH, b
#endif
	eth_write_pos pos
ENDM

; Wait for transmitter idle
tx_wait MACRO
#if !TX_DOUBLE_BUFFERING
	; Wait for transmitter idle
	BTFSC	TXRTS
	BRA		$-2
#endif
ENDM

; Wait for transmitter idle in eth_send function
tx_wait_send MACRO
#if TX_DOUBLE_BUFFERING
	; Wait for transmitter idle
	BTFSC	TXRTS
	BRA		$-2
#endif
ENDM

; Save ethernet write pointer
eth_save_write_ptr MACRO
#if TX_BUFFER_SIZE > 256
	MOVFF	EWRPTH, VAR16_ADDR(ptr, H)
#endif
	MOVFF	EWRPTL, VAR16_ADDR(ptr, L)
ENDM

; Restore ethernet write pointer
eth_restore_write_ptr MACRO
#if TX_BUFFER_SIZE > 256
	MOVFF	VAR16_ADDR(ptr, H), EWRPTH
#endif
	MOVFF	VAR16_ADDR(ptr, L), EWRPTL	
ENDM

#if IP_HEADER_FAST_CHECKSUM
;-------------------------------------------------------------------------------
; IP Header Checksum
; Huge, super fast checksum for ip header only (20 bytes)
; FSR0 - Source pointer
;-------------------------------------------------------------------------------
ip_header_checksum MACRO
	RCALL	ip_header_checksum_fun
ENDM
GLOBAL ip_header_checksum_fun					; 44 instructions
#else
ip_header_checksum MACRO
	MOVLW	_ip_size / 2
	RCALL	ip_checksum
ENDM
#endif
