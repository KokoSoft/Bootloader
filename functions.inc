; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>

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
;GLOBAL eth_checksum

;-------------------------------------------------------------------------------
; IP Header Checksum
; Huge, super fast checksum for ip header only (20 bytes)
; FSR0 - Source pointer
;-------------------------------------------------------------------------------
GLOBAL ip_header_checksum						; 44 instructions

;-------------------------------------------------------------------------------
; Ethernet transmit buffer helper macros
;-------------------------------------------------------------------------------
; Switch to next transmit buffer
tx_switch_buffer MACRO
	MOVF	ETXSTH, b, W
	BTG		WREG, TX_PAGE_BIT, a
	MOVWF	EWRPTH, b
	MOVWF	VAR8(tx_page)
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

; Set ethernet write pointer (low address only)
eth_write_pos MACRO
	NOP
ENDM

; Wait for transmitter idle
tx_wait MACRO
	
ENDM


;-------------------------------------------------------------------------------
; Workaround for Microchip buggy assembler! This piece of shit produce invalid jumps between files
; and does not check relative jump range!
;-------------------------------------------------------------------------------
#define OPCODE_BC					1110001000000000B
#define OPCODE_BN					1110011000000000B
#define OPCODE_BNC					1110001100000000B
#define OPCODE_BNN					1110011100000000B
#define OPCODE_BNOV					1110010100000000B
#define OPCODE_BNZ					1110000100000000B
#define OPCODE_BOV					1110010000000000B
#define OPCODE_BRA					1101000000000000B
#define OPCODE_BZ					1110000000000000B
#define OPCODE_RCALL				1101100000000000B
#define OPCODE_SLEEP				0000000000000011B

#define REL_DIFF(address, len)		((((address) - $ - 2) >> 1) and ((1 << len)-1))
#define REL_DIFF_SIMPLE(address)	((address) - $ - 2)

#define ADDR_SHIFT(x, bit)			(REL_DIFF_SIMPLE((x)) >> (bit))
#define ADDR_ERROR(addr, len)		((ADDR_SHIFT(addr, len) ^ ADDR_SHIFT(addr, len + 1)) and 0x01)

; Clears value on error
#define NULLIFY(opcode, error)		(opcode) * (1 - (error))

; Produce sleep instruction on error
#define SLEEPIFY(error)				(OPCODE_SLEEP * (error))

; Produce forever loop on error
#define LOOPIFY(error)				(0000000000000011B * (error))

; Generate opcode with error checking
#define OPCODE(code, addr, len)		NULLIFY(code | REL_DIFF(addr, len), ADDR_ERROR(addr, len)) | SLEEPIFY(ADDR_ERROR(addr, len))

#define BC		_BC
_BC MACRO address
	DW OPCODE(OPCODE_BC, address, 8)
ENDM

#define BN		_BN
_BN MACRO address
	DW OPCODE(OPCODE_BN, address, 8)
ENDM

#define BNC		_BNC
_BNC MACRO address
	DW OPCODE(OPCODE_BNC, address, 8)
ENDM

#define BNN		_BNN
_BNN MACRO address
	DW OPCODE(OPCODE_BNN, address, 8)
ENDM

#define BNOV	_BNOV	
_BNOV	 MACRO address
	DW OPCODE(OPCODE_BNOV, address, 8)
ENDM

#define BOV		_BOV
_BOV MACRO address
	DW OPCODE(OPCODE_BOV, address, 8)
ENDM

#define BZ		_BZ
_BZ MACRO address
	DW OPCODE(OPCODE_BZ, address, 8)
ENDM

#define BRA		_BRA
_BRA MACRO address
	DW OPCODE(OPCODE_BRA, address, 11)
ENDM

#define BNZ		_BNZ
_BNZ MACRO address
	DW OPCODE(OPCODE_BNZ, address, 8)
ENDM

#define RCALL	_RCALL
_RCALL MACRO address
	DW OPCODE(OPCODE_RCALL, address, 11)
ENDM