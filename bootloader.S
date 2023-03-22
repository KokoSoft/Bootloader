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


PSECT bootloader,space=0

; Code limit = 928 bytes
; 9 instructions remeaning (886 / 929)

; Cost: 6 instructions

; Minimalny rozmiar ramki to 60 bajtów
; mac + ip + udp to 42 bajty, zostaje 18 bajtów
; boot header ma 10 bajtów, netconfig


;-------------------------------------------------------------------------------
; Bootloader packet processor
;-------------------------------------------------------------------------------
bootloader_processor:
	; Check operation code
	; Skip version and sequential number check if operation is OP_DISCOVER od OP_NET_CONFIG
	MOVLW	OP_NET_CONFIG
	; Skip instruction if operation > OP_NET_CONFIG, unsigned comparison
	CPFSGT	RX_BE8(boot, operation)
	BRA		bootloader_skip_check

	; Check protocol version
	MOVLW	PROTOCOL_VERSION
	XORWF	RX_BE8(boot, version), W
	; Unsupported protocol version - can't return error code
	BNZ		done_frame_pop_bra

	; Check if the sender is permitted
	LFSR	0, RX_ADDR(ip, src)
	LFSR	1, programmer_ip_addr
	MOVLW	IP_ALEN
	MOVWF	VAR8(temp0)

check_sender_continue:
	; Compare byte
	MOVF	POSTINC0, a, W
	XORWF	POSTINC1, a, W
	BNZ		reply_invalid_sender
	; Can save one instruction
	;MOVLW	STATUS_INV_SRC
	;BNZ	reply_error

	; Loop control
	DECF	VAR8(temp0), f
	BNZ		check_sender_continue

	; Check sequential number, must be one greater than the previous
	; TODO: Or just diffrent?
	MOVF	VAR8(expected_seq), W
	XORWF	RX_BE8(boot, seq), W
	; Duplicated / out of order frame - just drop
	BNZ		done_frame_pop_bra
	; Increment sequential number
	INCF	VAR8(expected_seq), f

	; Check operation code range
	MOVLW	OP_MAX
	; Skip next instruction if operation > OP_MAX, unsigned comparison
	CPFSGT	RX_BE8(boot, operation)

	; Drop broadcast frames - only OP_DISCOVER od OP_NET_CONFIG can use broadcast frame
	; Skip next instruction if broadcast bit not set
	BTFSC	RX_BROADCAST
	BRA		reply_invalid_operation

bootloader_skip_check:
	; Check is it a request to a device (status = STATUS_REQUEST)
	MOVF	RX_BE8(boot, status), W
	BNZ		done_frame_pop_bra

	; Set flash memory pointer and check its range
	MOVF	RX_BE32(boot, address, UH), f
	BNZ		reply_invalid_param

	MOVF	RX_BE32(boot, address, UL), W
	MOVWF	TBLPTRU, a
	XORWF	TBLPTRU, a, W
	BNZ		reply_invalid_param

	MOVFF	RX_ADDR_BE32(boot, address, L), TBLPTRL
	MOVFF	RX_ADDR_BE32(boot, address, H), TBLPTRH

	; Wait for transmitter idle before modifying the buffer content
	tx_wait

	; Move eth write pointer to response payload start
	eth_write_pos	TX_ADDR(boot, payload)

DW NOPIFY(OPCODE_SLEEP, HIGH(switch_end) - HIGH(switch_start))

switch_start:
	; Read current PC to update PCLATH and PCLATU
	MOVF	PCL, a, W
	RLCF	RX_BE8(boot, operation), W
	; To prevent the PC from becoming misaligned with word instructions,
	; the Least Significant bit of PCL is fixed to a value of ‘0’.
	; TODO: Microchip's simulator have a bug, and use lsb in address!
	ADDWF	PCL, a, f

	; OP_DISCOVER			EQU 0		; Reply: DiscoverReply
	BRA		bootloader_discover
	; OP_NET_CONFIG			EQU 1		; Reply: DiscoverReply
	BRA		bootloader_net_config
	; OP_READ				EQU 2		; Reply: ReadReply with STATUS_INPROGRESS, STATUS_DONE
	BRA		bootloader_read
	; OP_WRITE				EQU 3		; Reply: Header with STATUS_INPROGRESS, STATUS_DONE
	BRA		bootloader_write
	; OP_ERASE				EQU 4		; Reply: Header with STATUS_INPROGRESS, STATUS_DONE
	BRA		bootloader_erase
	; OP_RESET				EQU 5		; Reply: Header with STATUS_OK
	; TODO: Send reply to reset? Check some magic values?
	RESET
	; OP_ERASE_WRITE		EQU 6		; Reply: Header with STATUS_INPROGRESS, STATUS_DONE
	BRA		bootloader_erase_write
	; OP_CHIP_ERASE			EQU 7		; Reply: Header with STATUS_INPROGRESS, STATUS_DONE
	BRA		bootloader_chip_erase
switch_end:

GLOBAL done_frame
GLOBAL done_frame_pop_bra
done_frame_pop_bra:
	POP
	BRA		done_frame

;-------------------------------------------------------------------------------
; Configure network addresses
; 8/16 instructions
;-------------------------------------------------------------------------------
bootloader_net_config:
	; Check packet length
	MOVF	RX_BE16(udp, len, H), W
	BNZ		reply_wrong_packet_size
	MOVF	RX_BE16(udp, len, L), W
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
	LFSR	0, RX_ADDR(ip, src)
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
	CLRF	RX_BE16(boot, length, H)
	MOVLW	2
	MOVWF	RX_BE16(boot, length, L)

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
	MOVF	RX_BE16(boot, length, L), W
	SUBLW	LOW(MAX_READ_LENGTH)					; Subtract W from literal
	MOVLW	HIGH(MAX_READ_LENGTH)
	SUBFWB	RX_BE16(boot, length, H), W	; Subtract f from W
	BNC		reply_invalid_param

	; TODO: #if bieda checksum
	; Length must be word aligned
	BTFSC	RX_BIT_BE16(boot, length, 0)
	BRA		reply_invalid_param

	RCALL	reply_inprogress

bootloader_read_checked:
	; If low byte of length is not zero then jump to read
	MOVF	RX_BE16(boot, length, L), f
	BNZ		bootloader_read_copy

bootloader_read_check_high:
	; Decrement high byte
	DECF	RX_BE16(boot, length, H), f
	BNC		reply_success

bootloader_read_copy:
	TBLRD*+					; Table read Post-Increment
	MOVFF	TABLAT, EDATA

	; Decrement low byte
	; Can be moved up and replace the zero check. It will allow us to save 2 instructions
	; but requre two more clock cycles per byte
	DECF	RX_BE16(boot, length, L), f
	BNZ		bootloader_read_copy
	BRA		bootloader_read_check_high


;-------------------------------------------------------------------------------
; Send reply with status
; ?? instructions
;-------------------------------------------------------------------------------
; Special reply type, must call here
reply_inprogress:
	MOVLW	STATUS_INPROGRESS
	BRA		bootloader_reply_code


; Return with status in WREG
reply_wrong_packet_size:
	RETLW	STATUS_PKT_SIZE
reply_illegal_address:
	RETLW	STATUS_INV_ADDR
reply_invalid_param:
	RETLW	STATUS_INV_PARAM
reply_invalid_operation:
	RETLW	STATUS_INV_OP
reply_invalid_sender:
	RETLW	STATUS_INV_SRC
reply_success:
	RETLW	STATUS_OK

bootloader_reply_code:	; Place status in WREG
	MOVWF	RX_BE8(boot, status)

	; Move eth write pointer to response start
	eth_write_pos_ex	TX_PROTO(boot)

	; Write header
	LFSR	0, RX_PROTO(boot)
	MOVLW	_boot_size
	RCALL	eth_write
	BRA		udp_send


;-------------------------------------------------------------------------------
; Erase and write flash memory row
; 17 instructions
;-------------------------------------------------------------------------------
bootloader_erase_write:
	RCALL check_erase_address

	; Length must be aligned to _FLASH_WRITE_SIZE
	; TODO: Mo¿e oprzeæ siê na sprawdzeniu z funckji write. Bêdziemy mieæ co prawda wykasowan¹ ju¿ pamiêæ, ale to nie problem?
	MOVF	RX_BE16(boot, length, L), W
	ANDLW	_FLASH_WRITE_SIZE - 1
	BNZ		reply_invalid_param

	; Limit length to _FLASH_ERASE_SIZE
	; Subtract requested length from max length. Report error if result is < 0 - carry flag cleared
	; TODO: Potencja³ do wydzielenia makra!
	MOVF	RX_BE16(boot, length, L), W
	SUBLW	LOW(_FLASH_ERASE_SIZE)		; Subtract W from literal
	MOVLW	HIGH(_FLASH_ERASE_SIZE)
	SUBFWB	RX_BE16(boot, length, H), W	; Subtract f from W
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
	MOVF	RX_BE32(boot, address, L), W
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
	SUBFWB	RX_BE32(boot, address, H), W
	MOVF	PCLATU, a, W
	SUBFWB	RX_BE32(boot, address, UL), W
	; if start >= boot_end then write is beyond bootloader code
	BC		flash_write_checked

	; Here we have always cleared carry flag
	; Calculate operation end address. Start address is already copied to TBLPTR
	; Subtract one from length
	DECF	RX_BE16(boot, length, L), W
	MOVWF	VAR16(check_len, L)
	MOVLW	0
	SUBWFB	RX_BE16(boot, length, H), W
	MOVWF	VAR16(check_len, H)

	; Add length to address
	MOVF	VAR16(check_len, L), W
	ADDWF	RX_BE32(boot, address, L), f
	MOVF	VAR16(check_len, H), W
	ADDWFC	RX_BE32(boot, address, H), f
	MOVLW	0
	ADDWFC	RX_BE32(boot, address, UL), f
	; Here we always have cleared carry
	;ADDWFC	RX_BE32(boot, address, UH), f

	; Check address possible boundaries
	BTFSC	RX_BIT_BE32(boot, address, 21)
	BRA		reply_invalid_param

	; Check if the operation end address is below the bootloader address.
	; Low bytes is always equal to 0
	MOVF	PCLATH, a, W
	ANDLW	~HIGH(BOOTLOADER_SIZE - 1)	; Calculate bootloader start address high byte
	SUBWF	RX_BE32(boot, address, H), W
	MOVF	PCLATU, a, W
	SUBWFB	RX_BE32(boot, address, UL), W
	; if end < boot_start then write is beyond bootloader code
	BC		reply_illegal_address

flash_write_checked:
	; Length must be aligned to flash write size (64 bytes)
	; Unlike previous PIC MCU devices, members of the PIC18F97J60 family
	; do not reset the holding registers after a write occurs.
	MOVF	RX_BE16(boot, length, L), W
	ANDLW	_FLASH_WRITE_SIZE - 1
	BNZ		reply_invalid_param

	; Check operation length is equal to packet length
	MOVF	RX_BE16(udp, len, H), W
	XORWF	RX_BE16(boot, length, H), W
	BNZ		reply_wrong_packet_size
	MOVF	RX_BE16(udp, len, L), W
	XORWF	RX_BE16(boot, length, L), W
	BNZ		reply_wrong_packet_size

	RCALL	reply_inprogress

	; Shift length left by 2 bits to store it in single register
	RLCF	RX_BE16(boot, length, L), f
	RLCF	RX_BE16(boot, length, H), f
	RLCF	RX_BE16(boot, length, L), f
	RLCF	RX_BE16(boot, length, H), f
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
	DECF	RX_BE16(boot, length, H), f
	BNZ		copy

	BRA		reply_success
#endif


;-------------------------------------------------------------------------------
; Erase flash row
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
	MOVF	RX_BE32(boot, address, UL), W
	ANDLW	UPPER(MAX_PC)
	;XORWF	PCLATU, a, W
	;BNZ		no_boot_code
	CPFSEQ	PCLATU, a
	RETURN						; Is is not boot code area

	MOVLW	HIGH(~(BOOTLOADER_SIZE - 1))
	ANDWF	PCLATH, a, f
	ANDWF	RX_BE32(boot, address, H), W
	;XORWF	PCLATH, a, W
	;BNZ		no_boot_code
	CPFSEQ	PCLATH, a
	RETURN						; Is is not boot code area

reply_error_pop:
	POP
	BRA		reply_illegal_address
