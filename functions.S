; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>
#include <xc.inc>

;-------------------------------------------------------------------------------
; Read from the Ethernet buffer to a RAM location pointed by FSR2
; W - read length, 0 will copy 256 bytes
; FSR2 - Destination pointer
; See the note at page 223 of the processor Datasheet
;-------------------------------------------------------------------------------
Eth_read:
	MOVFF	EDATA, POSTINC2
	DECFSZ	WREG, W, a
	BRA		Eth_read
	RETURN


;-------------------------------------------------------------------------------
; Write a data pointed by the FSR1 to the Ethernet buffer
; W - write length, 0 will copy 256 bytes
; FSR0 - Source pointer
; See the note at page 223 of the processor Datasheet
;-------------------------------------------------------------------------------
Eth_write:
	MOVFF	POSTINC0, EDATA
	DECFSZ	WREG, W, a
	BRA		Eth_read
	RETURN


;-------------------------------------------------------------------------------
; Send network frame
; Sends data from EWRPTH:0 to EWRPTH:EWRPTL - 1. Fill MAC addresses in ETH Header
;-------------------------------------------------------------------------------
eth_send:
	; Wait for transmitter idle
	BTFSC	TXRTS
	BRA		eth_send

	; Set Tx start and end address based on Write Pointer
	MOVF	EWRPTH, b, W	; start = write_ptr & 0xff000
	MOVWF	ETXSTH, b
	MOVWF	ETXNDH, b
	DECF	EWRPTH, b, W	; end = write_ptr - 1
	MOVWF	ETXNDL, b

	; Move write pointer to eth header
	MOVLW	1
	MOVWF	EWRPTH, b

	; Set destination MAC to source MAC of received frame
	LFSR	0, Rx_mac + $mac_dst
	MOVLW	6
	RCALL	eth_write

	; Set out MAC as source address
	LFSR	0, mac_addr
	MOVLW	6
	RCALL	eth_write

	; Start the transmission process by setting the TXRTS bit (ECON1<3>).
	BSF		TXRTS			; ECON1 = FD2
	BRA		done_frame


;-------------------------------------------------------------------------------
; Compare memory, return to done_frame on mismatch
; W - compare length, 0 will compare 256 bytes
; FSR0, FSR1 - Pointers to data
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
