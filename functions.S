; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>
#include <xc.inc>
#include "memory.inc"
#include "config.inc"
#include "functions.inc"

;PSECT boot_functions,space=0
PSECT code

GLOBAL init
	BRA	init
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
eth_send:
	; Set Tx start and end address based on Write Pointer
	MOVF	EWRPTH, b, W	; start = write_ptr & 0xff000
	MOVWF	ETXSTH, b
	MOVWF	ETXNDH, b
	DECF	EWRPTL, b, W	; end = write_ptr - 1
	MOVWF	ETXNDL, b

	; Move write pointer to eth header
	CLRF	EWRPTL, b
	MOVFF	EWRPTL, EDATA	; per-packet control byte

	; Set destination MAC to source MAC of received frame
	LFSR	0, Rx_mac + _mac_src
	MOVLW	ETH_ALEN
	RCALL	eth_write

	; Set out MAC as source address
	LFSR	0, mac_addr
	MOVLW	ETH_ALEN
	RCALL	eth_write

	; DEBUG
	CLRF	ERDPTL, a
	MOVFF	EWRPTH, ERDPTH
	LFSR	2, 0x100
	CLRF	WREG, a
	RCALL	eth_read

	; Start the transmission process by setting the TXRTS bit (ECON1<3>).
	BSF		TXRTS			; ECON1 = FD2
	BRA	done_frame
	


;-------------------------------------------------------------------------------
; Compare memory, return to done_frame on mismatch
; W - compare length, 0 will compare 256 bytes
; FSR0, FSR1 - Pointers to data
; Function jumps to done_frame_pop if the memory differs
; Uses temp0!
;-------------------------------------------------------------------------------
memcmp:
	MOVWF	temp0, a

memcmp_continue:
	; Compare
	MOVF	POSTINC0, a, W
	XORWF	POSTINC1, a, W
	BNZ		done_frame_pop

	; Loop control
	DECF	temp0, f, a
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
	MOVWF	temp0, a

ip_checksum_continue:
	MOVF	POSTINC0, a, W
	ADDWF	checksumH, a, f
	MOVF	POSTINC0, a, W
	ADDWFC	checksumL, a, f			; Store MSB in Carry!

	; Store carry in sum
	MOVLW	0
	ADDWFC	checksumH, a, f
	ADDWFC	checksumL, a, f

	; Loop control
	DECF	temp0, a, f
	BNZ		ip_checksum_continue
	RETURN
#else
; Premium version, 1 more instruction, 3 cycles per word less.
ip_checksum:						; 12 instructions
	MOVWF	temp0, a
	BCF		CARRY					; Clear carry flag

ip_checksum_continue:
	MOVF	POSTINC0, a, W
	ADDWFC	checksumH, a, f
	MOVF	POSTINC0, a, W
	ADDWFC	checksumL, a, f

	DECFSZ	temp0, a, f				; Decrement Skip if 0 - no carry flag modification
	BRA		ip_checksum_continue

	MOVLW	0
	ADDWFC	checksumH, a, f
	ADDWFC	checksumL, a, f
	RETURN
#endif

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
; Premium version, 1 more instruction, 3 cycles per word less.
eth_read_checksum:
	MOVWF	temp0, a
	BCF		CARRY					; Clear carry flag

eth_read_checksum_continue:
	MOVF	EDATA, a, W
	MOVWF	POSTINC2, a
	ADDWFC	checksumH, a, f
	MOVF	EDATA, a, W
	MOVWF	POSTINC2, a
	ADDWFC	checksumL, a, f

	DECFSZ	temp0, a, f				; Decrement Skip if 0 - no carry flag modification
	BRA		eth_read_checksum_continue

	MOVLW	0
	ADDWFC	checksumH, a, f
	ADDWFC	checksumL, a, f
	RETURN
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
eth_checksum_byte:
	; Divide UDP length by 2 - length in words - stored in W!
	BCF		CARRY			; Clear carry flag
	RRCF	check_lenH, a, W
	RRCF	check_lenL, a, W

;-------------------------------------------------------------------------------
; IP Checksum ethernet buffer
; Super simple implementation. Operates on words only.
; WREG - words count, 0 will compute 256 words
; Uses temp0!
; Can save 1 instruction, but will use 3 more cycles per word.
; 12 instructions
;-------------------------------------------------------------------------------
; Premium version, 1 more instruction, 3 cycles per word less.
eth_checksum:
	MOVWF	temp0, a
	BCF		CARRY					; Clear carry flag

eth_checksum_continue:
	MOVF	EDATA, a, W
	ADDWFC	checksumH, a, f
	MOVF	EDATA, a, W
	ADDWFC	checksumL, a, f

	DECFSZ	temp0, a, f				; Decrement Skip if 0 - no carry flag modification
	BRA		eth_checksum_continue

	MOVLW	0
	ADDWFC	checksumH, a, f
	ADDWFC	checksumL, a, f
	RETURN


#if 0
;-------------------------------------------------------------------------------
; IP Checksum ethernet buffer with byte support
; check_lenH:check_lenL - data length in bytes.
; Can save 1 instruction, but will use 3 more cycles per word.
; Uses temp0
; 26 instructions
;-------------------------------------------------------------------------------
; Premium version, 1 more instruction, 3 cycles per word less.
_ip_checksum:
	MOVFF	check_lenL, temp0
	BCF		CARRY					; Clear carry flag
	RRCF	check_lenH, a, f		; size >>= 1;
	RRCF	check_lenL, a, f
	BCF		CARRY					; Clear carry flag, BCF not touch flags
	BNZ		loop					; Z flag set by RRCF

loop_check:							; sizeL is 0
	MOVF	check_lenH, a, f
	BZ		loop_done
	DECFSZ	check_lenH, a, f		; Decrement Skip if 0 - no carry flag modification
	NOP

loop:
	MOVF	EDATA, a, W
	ADDWFC	checksumH, a, f
	MOVF	EDATA, a, W
	ADDWFC	checksumL, a, f

	DCFSNZ	check_lenL, a, f		; Decrement Skip if not 0 - no carry flag modification
	BRA		loop_check
	BRA		loop

loop_done:
	MOVLW	0
	BTFSC	temp0, 0, a
	MOVF	EDATA, a, W
	ADDWFC	checksumH, a, f
	MOVLW	0
	ADDWFC	checksumL, a, f
	ADDWFC	checksumH, a, f
	RETURN
#endif


#if 0
PSECT code
;-------------------------------------------------------------------------------
; IP Checksum ethernet buffer
; Super simple implementation. Operates on words only.
; Uses EWRPT as end address
; Warning! Will loop forever if (ERDPT & 1) != (EWRPT & 1)
; Can save 1 instruction, but will use 3 more cycles per word.
; 14 instructions
;-------------------------------------------------------------------------------
; Premium version, 1 more instruction, 3 cycles per word less.
eth_checksum_ptr:
	BCF		CARRY					; Clear carry flag

eth_checksum_ptr_continue:
	MOVF	EDATA, a, W
	ADDWFC	checksumH, a, f
	MOVF	EDATA, a, W
	ADDWFC	checksumL, a, f

	MOVF	ERDPTL, a, W
	XORWF	EWRPTL, b, W
	BNZ		eth_checksum_ptr_continue
	MOVF	ERDPTH, a, W
	XORWF	EWRPTH, b, W
	BNZ		eth_checksum_ptr_continue

	ADDWFC	checksumH, a, f
	ADDWFC	checksumL, a, f
	RETURN
#endif