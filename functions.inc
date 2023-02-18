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
; Function jumps to done_frame_pop if the memory differs
; Uses temp0!
;-------------------------------------------------------------------------------
GLOBAL memcmp

; Return point
GLOBAL done_frame_pop

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

#if 0
; TODO: To be removed.
;-------------------------------------------------------------------------------
; Ethernet read with IP Checksum
; Super simple implementation. Operates on words only.
; FSR2 - Destination pointer
; WREG - words count, 0 will compute 256 words
; Uses temp0!
; Can save 1 instruction, but will use 3 more cycles per word.
;-------------------------------------------------------------------------------
GLOBAL eth_read_checksum
#endif

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
; Switch to next transmit buffer
tx_switch_buffer MACRO

ENDM

; Mark end of packet
tx_set_end MACRO end_address
IF nul end_address
; argument was not supplied. Use current write pointer value
	NOP
ELSE ;argument was supplied
	NOP
ENDIF
	NOP
ENDM

eth_get_tx_len_l MACRO
	MOVLW	LOW(Tx_boot_udp)
	SUBWF	EWRPTL, b, W
ENDM

eth_get_tx_len_h MACRO
	MOVLW	HIGH(Tx_boot_udp)
	SUBWFB	EWRPTH, b, W
ENDM

; Set ethernet read pointer to prepared tx data
eth_read_pos MACRO pos
	MOVLW	HIGH(pos)
	MOVWF	ERDPTH, a
	MOVLW	LOW(pos)
	MOVWF	ERDPTL, a
ENDM


; Set ethernet write pointer (low address only)
eth_write_pos MACRO pos
	MOVLW	HIGH(pos)
	MOVWF	EWRPTH, b
	MOVLW	LOW(pos)
	MOVWF	EWRPTL, b
ENDM

; Wait for transmitter idle
tx_wait MACRO
	
ENDM

; Wait for transmitter idle in eth_send function
tx_wait_send MACRO
	BTFSC	TXRTS
	BRA		$-2
ENDM

; Save ethernet write pointer
eth_save_write_ptr MACRO
	MOVFF	EWRPTH, ptrH
	MOVFF	EWRPTL, ptrL
ENDM

; Restore ethernet write pointer
eth_restore_write_ptr MACRO
	MOVFF	ptrH, EWRPTH
	MOVFF	ptrL, EWRPTL	
ENDM
