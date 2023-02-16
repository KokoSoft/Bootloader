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


PSECT code

; Code limit = 928 bytes
; 9 instructions remeaning (886 / 929)

; Cost: 6 instructions

; Minimalny rozmiar ramki to 60 bajtów
; mac + ip + udp to 42 bajty, zostaje 18 bajtów
; boot header ma 10 bajtów, netconfig


;-------------------------------------------------------------------------------
; Configure network addresses
; 8/16 instructions
;-------------------------------------------------------------------------------
bootloader_net_config:
	; Check packet length
	MOVF	Rx_udp + _udp_len, a, W
	BNZ		reply_wrong_packet_size
	MOVF	Rx_udp + _udp_len + 1, a, W
	XORLW	_netcfg_size
	BNZ		reply_wrong_packet_size

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

	; Fallback to discover


;-------------------------------------------------------------------------------
; Discover targed in network
; 17/25 instructions
;-------------------------------------------------------------------------------
bootloader_discover:
	; Set source IP address as permitted programmer
	LFSR	0, Rx_ip + _ip_src
	LFSR	1, programmer_ip_addr
	MOVLW	IP_ALEN
	RCALL	memcpy

#if VERSION_IN_INITRAM
	; Chcesz mieæ bootloader niezalezny od pozycji kodu aby pasowa³ do PIC18FxxJ6x
	; Wiêc wpychanie adresu do init ramu nie ma sensu!
	LFSR	0, discovery_reply
	MOVLW	VERSION_IN_INITRAM_SIZE
	RCALL	eth_write
#else
	MOVLW	HIGH(BOOTLOADER_VERSION)
	MOVWF	EDATA, a				; It move also ERDPT
	MOVLW	LOW(BOOTLOADER_VERSION)
	MOVWF	EDATA, a				; It move also ERDPT

	MOVLW	0
	MOVWF	EDATA, a				; It move also ERDPT
	MOVF	PCL, a, W				; Must read PCL first
	MOVFF	PCLATU, EDATA
	MOVFF	PCLATH, EDATA
	MOVWF	EDATA, a				; It move also ERDPT
#endif

	; Set TBLPTR to read device id
	SETF	TBLPTRU, a
	SETF	TBLPTRH, a
	MOVLW	LOW(DEVID1)
	MOVWF	TBLPTRL, a

	; Fallback to bootloader_read to read device id
	CLRF	Rx_boot_header + _hdr_length + 0, a
	MOVLW	2
	MOVWF	Rx_boot_header + _hdr_length + 1, a

	; Fallback to read
	BRA		bootloader_read_checked

;-------------------------------------------------------------------------------
; Read devices flash memory
; 15/17 instructions
;-------------------------------------------------------------------------------
bootloader_read:
	; Limit read length to a reasonable value
	; Subtract requested length from max length. Report error if result is < 0 - carry flag cleared
	; TODO: Potencja³ do wydzielenia makra!
	MOVF	Rx_boot_header + _hdr_length + 1, a, W
	SUBLW	LOW(MAX_READ_LENGTH)					; Subtract W from literal
	MOVLW	HIGH(MAX_READ_LENGTH)
	SUBFWB	Rx_boot_header + _hdr_length + 0, a, W	; Subtract f from W
	BNC		reply_invalid_param

	; TODO: #if bieda checksum
	; Length must be word aligned
	BTFSC	Rx_boot_header + _hdr_length + 1, 0, a
	BRA		reply_invalid_param

	RCALL	reply_inprogress

bootloader_read_checked:
	; If low byte of length is not zero then jump to read
	MOVF	Rx_boot_header + _hdr_length + 1, a, f
	BNZ		bootloader_read_copy

bootloader_read_check_high:
	; Decrement high byte
	DECF	Rx_boot_header + _hdr_length + 0, a, f
	BNC		reply_success

bootloader_read_copy:
	TBLRD*+					; Table read Post-Increment
	MOVFF	TABLAT, EDATA

	; Decrement low byte
	; Can be moved up and replace the zero check. It will allow us to save 2 instructions
	; but requre two more clock cycles per byte
	DECF	Rx_boot_header + _hdr_length + 1, a, f
	BNZ		bootloader_read_copy
	BRA		bootloader_read_check_high


;-------------------------------------------------------------------------------
; Erase and write flash memory row
; 17 instructions
;-------------------------------------------------------------------------------
bootloader_erase_write:
	RCALL check_erase_address

	; Length must be aligned to _FLASH_WRITE_SIZE
	; TODO: Mo¿e oprzeæ siê na sprawdzeniu z funckji write. Bêdziemy mieæ co prawda wykasowan¹ ju¿ pamiêæ, ale to nie problem?
	MOVF	Rx_boot_header + _hdr_length + 1, a, W
	ANDLW	_FLASH_WRITE_SIZE - 1
	BNZ		reply_invalid_param

	; Limit length to _FLASH_ERASE_SIZE
	; Subtract requested length from max length. Report error if result is < 0 - carry flag cleared
	; TODO: Potencja³ do wydzielenia makra!
	MOVF	Rx_boot_header + _hdr_length + 1, a, W
	SUBLW	LOW(_FLASH_ERASE_SIZE)		; Subtract W from literal
	MOVLW	HIGH(_FLASH_ERASE_SIZE)
	SUBFWB	Rx_boot_header + _hdr_length + 0, a, W	; Subtract f from W
	BNC		reply_invalid_param

	RCALL	reply_inprogress

	; Row erase
	; TODO: Can call to the bootloader_erase if it is a function
	; Yhym. Zaoszczêdzimy na BSF, ale musimy dodaæ return i drugi call przy erase...

	; Enable Row Erase operation. Set FREE bit in EECON1 register.
	BSF		FREE
	RCALL	flash_write_cycle

	; Perform flash write
	BRA flash_write_checked

;-------------------------------------------------------------------------------
; Write flash memory
; 55 instructions
;-------------------------------------------------------------------------------
bootloader_write:
	; Address must be aligned to flash write size (64 bytes)
	MOVF	Rx_boot_header + _hdr_address + 3, a, W
	ANDLW	_FLASH_WRITE_SIZE - 1
	BNZ		reply_invalid_param

	; Check address possible boundaries
	BTFSC	TBLPTRU, 5, a
	BRA		reply_invalid_param

	;if (start >= boot_end || end < boot_start) then address is ok
	; Check if the operation address is greater or equal than the end bootloader address.
	; The lsb byte of end address of the bootloader code is always equal to 0xff.
	; The operation address must be aligned to 64 bytes, so its lsb is 00, 40, 80 or C0.
	; After subtracting these values we will always have the carry flag cleared (borrow set).

	; Here we must have cleared carry flag after ADDWF	PCL at switch_start
	;BCF		CARRY

	MOVF	PCLATH, a, W
	IORLW	HIGH(BOOTLOADER_SIZE - 1)	; Calculate bootloader end address high byte
	SUBFWB	Rx_boot + _hdr_address + 2, a, W
	MOVF	PCLATU, a, W
	SUBFWB	Rx_boot + _hdr_address + 1, a, W
	; if start >= boot_end then write is beyond bootloader code
	BC		flash_write_checked

	; Here we have always cleared carry flag
	; Calculate operation end address. Start address is already copied to TBLPTR
	; Subtract one from length
	DECF	Rx_boot_header + _hdr_length + 1, a, W
	MOVWF	check_lenL, a
	MOVLW	0
	SUBWFB	Rx_boot_header + _hdr_length, a, W
	MOVWF	check_lenH, a

	; Add length to address
	MOVF	check_lenL, a, W
	ADDWF	Rx_boot_header + _hdr_address + 3, a, f
	MOVF	check_lenH, a, W
	ADDWFC	Rx_boot_header + _hdr_address + 2, a, f
	MOVLW	0
	ADDWFC	Rx_boot_header + _hdr_address + 1, a, f
	; Here we always have cleared carry
	;ADDWFC	Rx_boot_header + _hdr_address + 0, a, f

	; Check address possible boundaries
	BTFSC	Rx_boot_header + _hdr_address + 1, 5, a
	BRA		reply_invalid_param

	; Check if the operation end address is below the bootloader address.
	; Low bytes is always equal to 0
	MOVF	PCLATH, a, W
	ANDLW	~HIGH(BOOTLOADER_SIZE - 1)	; Calculate bootloader start address high byte
	SUBWF	Rx_boot + _hdr_address + 2, a, W
	MOVF	PCLATU, a, W
	SUBWFB	Rx_boot + _hdr_address + 1, a, W
	; if end < boot_start then write is beyond bootloader code
	BC		reply_illegal_address

flash_write_checked:
	; Length must be aligned to flash write size (64 bytes)
	; Unlike previous PIC MCU devices, members of the PIC18F97J60 family
	; do not reset the holding registers after a write occurs.
	MOVF	Rx_boot_header + _hdr_length + 1, a, W
	ANDLW	_FLASH_WRITE_SIZE - 1
	BNZ		reply_invalid_param

	; Check operation length is equal to packet length
	MOVF	Rx_udp + _udp_len, a, W
	XORWF	Rx_boot_header + _hdr_length, a, W
	BNZ		reply_wrong_packet_size
	MOVF	Rx_udp + _udp_len + 1, a, W
	XORWF	Rx_boot_header + _hdr_length + 1, a, W
	BNZ		reply_wrong_packet_size

	RCALL	reply_inprogress

	; Shift length left by 2 bits to store it in single register
	RLCF	Rx_boot_header + _hdr_length + 1, a, f
	RLCF	Rx_boot_header + _hdr_length + 0, a, f
	RLCF	Rx_boot_header + _hdr_length + 1, a, f
	RLCF	Rx_boot_header + _hdr_length + 0, a, f
	BZ		reply_invalid_param

	; Dummy read to decrement flash pointer
	TBLRD*-					; Table read with Post-Decrement

flash_fill_block:
	; Fill holding registers using pre-increment write
	MOVLW	_FLASH_WRITE_SIZE
flash_fill:
	MOVFF	EDATA, TABLAT
	TBLWT+*					; Table write with Pre-Increment
	DECF	WREG, a, W
	BNZ		flash_fill

	; Before setting the WR bit, the Table Pointer address needs to be within
	; the intended address range of the 64 bytes in the holding register.
#if !MULTIBLOCK_WRITE
	BRA		flash_write_cycle
#else
	RCALL	flash_write_cycle

	; Decrement block count
	DECF	Rx_boot_header + _hdr_length + 0, a, f
	BNZ		copy

	BRA		reply_success
#endif


;-------------------------------------------------------------------------------
; Erashe flash row
; 4 instructions
;-------------------------------------------------------------------------------
bootloader_erase:
	RCALL check_erase_address
	RCALL	reply_inprogress

	; Enable Row Erase operation. Set FREE bit in EECON1 register.
	BSF		FREE
	RCALL	flash_write_cycle
	BRA		reply_success

;-------------------------------------------------------------------------------
; Perform flash write/erase operation
; 8 instructions
;-------------------------------------------------------------------------------
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
	RETURN

;-------------------------------------------------------------------------------
; Erase whole chip without bootloader and config words
; Config words protection requires bootloader placed in last (two) row(s) of flash
; 16 instructions
;-------------------------------------------------------------------------------
bootloader_chip_erase:
	; Start from bootloader start and go up to the beginning of flash
	;MOVF	PCL, a, W						; PCL already touched by switch/case to bootloader_*
	MOVFF	PCLATU, TBLPTRU
	MOVF	PCLATH, a, W
	ANDLW	HIGH(~(BOOTLOADER_SIZE - 1))	; Mask out bootloader size bits
	MOVWF	TBLPTRH, a
	DECF	TBLPTRH, a, f					; Decrement pointer to select row before bootloader
	CLRF	WREG, a
	SUBWFB	TBLPTRU, a, f

	RCALL	reply_inprogress

bootloader_chip_erase_row:
	; Enable Row Erase operation. Set FREE bit in EECON1 register.
	BSF		FREE
	; Perform erasing
	RCALL	flash_write_cycle
	; Subtract erase size from the table pointer
	MOVLW	_FLASH_ERASE_SIZE
	SUBWF	TBLPTRH, a, f
	MOVLW	0
	SUBWFB	TBLPTRU, a, f
	; Erase next row if not borrow
	BC		bootloader_chip_erase_row
	BRA		reply_success




;TODO: Przenieœæ funkcje na pocz¹tek tego pliku

;-------------------------------------------------------------------------------
; Check operation address to protect bootloader code
; Compare operation address bits 20:10 with Program Counter
; 20 instructions
;-------------------------------------------------------------------------------
check_erase_address:
	; Operation address must be aligned to _FLASH_ERASE_SIZE
	MOVF	TBLPTRL, a, f
	BNZ		reply_invalid_param
	MOVF	TBLPTRH, a, W
	ANDLW	HIGH(_FLASH_ERASE_SIZE - 1)
	BNZ		reply_invalid_param

	; Check address possible boundaries
	BTFSC	TBLPTRU, 5, a
	BRA		reply_invalid_param

	; Check address to protect bootloader code
	MOVF	PCL, a, W			; Read PCL to store PC in PCLATH and PCLATU
	MOVF	Rx_boot_header + _hdr_address + 1, a, W
	ANDLW	UPPER(MAX_PC)
	;XORWF	PCLATU, a, W
	;BNZ		no_boot_code
	CPFSEQ	PCLATU, a
	RETURN						; Is is not boot code area

	MOVLW	HIGH(~(BOOTLOADER_SIZE - 1))
	ANDWF	PCLATH, a, f
	ANDWF	Rx_boot_header + _hdr_address + 2, a, W
	;XORWF	PCLATH, a, W
	;BNZ		no_boot_code
	CPFSEQ	PCLATH, a
	RETURN						; Is is not boot code area

reply_error_pop:
	POP
	BRA		reply_illegal_address
