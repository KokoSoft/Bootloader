; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>
#include <xc.inc>
#include "memory.inc"
#include "net.inc"
#include "config.inc"
#include "functions.inc"
#include "bootloader.inc"

CONFIG1L	EQU 300000h
CONFIG1H	EQU 300001h
CONFIG2L	EQU 300002h
CONFIG2H	EQU 300003h
CONFIG3L	EQU 300004h
CONFIG3H	EQU 300005h
DEVID1		EQU 3FFFFEh
DEVID2		EQU 3FFFFFh

GLOBAL udp_send

PSECT code

; Code limit = 928 bytes
; 9 instructions remeaning (886 / 929)

; Cost: 6 instructions


bootloader_net_config:
	; Read MAC and IP address
	LFSR	2, mac_addr
	MOVLW	_mac_size + _ip_size
	RCALL	eth_read

	; Configure MAC address in ethernet module
#if NET_CONFIG_MAC_EXTENDED
	; 4 instructions if net_config frame will contains scrambled MAC address too.
	LFSR	2, MAADR5
	MOVLW	ETH_ALEN
	RCALL	eth_read
#else
	; 12 instructions
	MOVFF	mac_addr + 0, MAADR5
	MOVFF	mac_addr + 1, MAADR6
	MOVFF	mac_addr + 2, MAADR3
	MOVFF	mac_addr + 3, MAADR4
	MOVFF	mac_addr + 4, MAADR1
	MOVFF	mac_addr + 5, MAADR2
#endif

bootloader_discover:
	; Set source IP address as permitted programmer
	LFSR	0, Rx_ip + _ip_src
	LFSR	1, programmer_ip_addr
	MOVLW	IP_ALEN
	RCALL	memcpy

#if VERSION_IN_INITRAM
	LFSR	0, discovery_reply
	MOVLW	VERSION_IN_INITRAM_SIZE
	RCALL	eth_write
#else
	MOVLW	LOW(BOOTLOADER_VERSION)
	MOVWF	EDATA, a
	MOVLW	HIGH(BOOTLOADER_VERSION)
	MOVWF	EDATA, a

	MOVFF	PCL, EDATA
	MOVFF	PCLATH, EDATA
	MOVFF	PCLATU, EDATA
	MOVFF	WREG, EDATA
#endif
	; TODO: Przenieœæ dev_id za boot_addr w strukturze DiscoverReply!
	CLRF	TBLPTRU, a
	CLRF	TBLPTRH, a
	CLRF	TBLPTRL, a
	; Dummy read to decrement flash pointer
	TBLRD*-					; Table read with Post-Decrement

	; Fallback to bootloader_read to read device id
	MOVLW	2

bootloader_read:
	DECF	temp0, a, f
	BNC		send_reply
	TBLRD*+					; Table read Post-Increment
	MOVFF	TABLAT, EDATA
	BRA		bootloader_read

; Single block writter
bootloader_write:
	RCALL check_op_address
	; TODO: Check size to not allow bootloader code to be overwritten
	; TODO: Address and size must be aligned to 64 bytes
	; TODO: Limit size to a reasonable values
	; TODO: cHECK FRAME SIZE
	; TODO: Move the check_op_address function to this file

	; Unlike previous PIC MCU devices, members of the PIC18F97J60 family
	; do not reset the holding registers after a write occurs.

	; Dummy read to decrement flash pointer
	TBLRD*-					; Table read with Post-Decrement
flash_write_block:
	; Write 64 bytes with pre-increment
	MOVLW	64
flash_fill:
	MOVFF	EDATA, TABLAT
	TBLWT+*					; Table write with Pre-Increment
	DECF	WREG, a
	BNZ		flash_fill

	; Before setting the WR bit, the Table Pointer address needs to be within
	; the intended address range of the 64 bytes in the holding register.
#if !MULTIBLOCK_WRITE
	BRA		flash_write_cycle
#else
	RCALL	flash_write_cycle
	; Decrement block counter
	DECF	WREG, a
	BC		flash_write_block
	BRA		send_reply
#endif

bootloader_erase:
	RCALL check_op_address

	; Enable Row Erase operation. Set FREE bit in EECON1 register.
	BSF		FREE
#if MULTIBLOCK_WRITE
	RCALL	flash_write_cycle
	BRA		send_reply
#endif
	
flash_write_cycle:
	; Enable write to memory. Set WREN bit in EECON1 register.
	BSF		WREN

	; Required Sequence
	MOVLW	0x55
	MOVWF	EECON2, a		; write 55h
	MOVLW	0xAA
	MOVWF	EECON2, a		; write 0AAh

	; Set WR bit in EECON1 register. This will begin the write cycle.
	BSF		WR				; start erase (CPU stall)
	CLRF	EECON1, a
#if MULTIBLOCK_WRITE
	RETURN
#endif
send_reply:




;-------------------------------------------------------------------------------
; Check operation address to protect bootloader code
; Compare operation address bits 20:10 with Program Counter
; 13 instructions
;-------------------------------------------------------------------------------
GLOBAL check_op_address
GLOBAL reply_error

; Maximum PC value
MAX_PC	EQU	2 * 1024 * 1024 - 1



TODO: Przenieœæ funkcje na pocz¹tek tego pliku

;-------------------------------------------------------------------------------
; Check operation address to protect bootloader code
; Compare operation address bits 20:10 with Program Counter
; 13 instructions
;-------------------------------------------------------------------------------
check_op_address:
	; Check address to protect bootloader code
	MOVF	PCL, a, W			; Read PCL to store PC in PCLATH and PCLATU
	MOVF	Rx_boot_header + _hdr_address + 1, a, W
	ANDLW	UPPER(MAX_PC)
	;XORWF	PCLATU, a, W
	;BNZ		no_boot_code
	CPFSEQ	PCLATU, a
	RETURN

IF SMALL_BOOTLOADER
	; Protect one page
	MOVLW	HIGH(~(_FLASH_ERASE_SIZE - 1))
ELSE
	; Protect two pages
	TODO: Dokumentacja: Bootloader jest PIC (Position independent Code), ale jeœli zajmuje 2 strony to musi byæ wgrany od parzystej strony
	MOVLW	HIGH(~(2* _FLASH_ERASE_SIZE - 1))
ENDIF
	ANDWF	PCLATH, a, f
	ANDWF	Rx_boot_header + _hdr_address + 2, a, W
	;XORWF	PCLATH, a, W
	;BNZ		no_boot_code
	CPFSEQ	PCLATH, a
	RETURN

	MOVLW	STATUS_INV_ADDR
reply_error_pop:
	POP
	BRA		reply_error





