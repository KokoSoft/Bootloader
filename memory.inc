; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>
#include "net.inc"
#include "config.inc"

; FSR0 - Source Pointer parameter
; FSR1 - Destination Pointer parameter
; FSR2 - RX Frame RAM Buffer write pointer

; We have 128 bytes in bank E
; We have 96 bytes in bank F

#define VARS_BASE	0xE00
#define VARS_ACCESS	b

#define BUFF_BASE	0x020
#define BUFF_ACCESS	a


PSECT boot_vars,space=1
PSECT rx_buffer,abs, ovrld, space=1,class=RAM
;-------------------------------------------------------------------------------
; RAM Memory map:
;-------------------------------------------------------------------------------
; Access RAM (0x00 - 0x5F)
ORG VARS_BASE
VAR_temp0:			DS 1
VAR_tx_page:		DS 1

; Used to store partial checksum by eth_checksum_ptr, eth_checksum_byte, eth_checksum, ip_checksum
VAR_checksum:		DS 2

; Used to temporarly store of ethernet ram read/write pointer
; Can be outside of access ram
VAR_ptr:			DS 2

; Parameters for eth_checksum_byte
; Lenght of a data to be checksumed
VAR_check_len:		DS 2
; 0x0A
VAR_last_seq:		DS 4
; 0x0E
VAR_boot_counter:	DS 4
; 0x12
VAR_received_udp:	DS 4
; 0x16
VAR_received_arp:	DS 4
; 0x1A = 24


;ALIGN 0x10 DO NOT USE ALIGN!!!! Assembler bug?!
;ORG 0x60 - (_rx_size + _mac_size + _ip_size + _udp_size)		; 0x60 - 0x07 - 0x0E - 0x14 - 0x08 = 2F - 0x15D RX Frame RAM Buffer
;ORG VARS_BASE + 0x20 - _rx_size
ORG BUFF_BASE
Rx_buf:			DS _rx_size		; Receive Status Vector
Rx_mac:			DS _mac_size	; MAC Header
; Access RAM ends here
Rx_arp:
Rx_ip:			DS _ip_size		; IP Header
Rx_udp:			DS _udp_size	; UDP Header
Rx_proto:
Rx_boot_header:	DS _hdr_size	; Bootloader protocol header
Rx_boot:

; _rx_size + _mac_size + _ip_size + _udp_size + _hdr_size
; 0x006 + 0x00E + 0x014 + 0x008 + 0x04 = 0x34 (52)

IF 5 > 0x60
	ERROR "Too much variables! Move Rx buffer to bank E."
ENDIF

L	EQU	3	; Low byte
H	EQU	2	; High byte
UL	EQU 1	; Upper low byte
UH	EQU 0	; Upper high byte
#define LE_BYTE(addr, byte_sel)			((addr) + 3 - (byte_sel))

#define RX_ACCESS BUFF_ACCESS
#define RX_be8(proto, field)			BANKMASK((Rx_ ## proto) + (_ ## proto ## _ ## field)), RX_ACCESS
#define RX_be16(proto, field, byte_sel)	BANKMASK((Rx_ ## proto) + (_ ## proto ## _ ## field) + (byte_sel) - 2), RX_ACCESS
#define RX_be32(proto, field, byte_sel)	BANKMASK((Rx_ ## proto) + (_ ## proto ## _ ## field) + (byte_sel)), RX_ACCESS

#define RX_le8(proto, field)			BANKMASK((Rx_ ## proto) + (_ ## proto ## _ ## field)), RX_ACCESS
#define RX_le16(proto, field, byte_sel)	BANKMASK((Rx_ ## proto) + (_ ## proto ## _ ## field) + 3 - (byte_sel)), RX_ACCESS
#define RX_le32(proto, field, byte_sel)	BANKMASK((Rx_ ## proto) + (_ ## proto ## _ ## field) + 3 - (byte_sel)), RX_ACCESS

; Variables are stored as little endian
#define VAR_ACCESS VARS_ACCESS
#define VAR8(variable)					BANKMASK(VAR8_ADDR(variable)), VAR_ACCESS
#define VAR16(variable, byte_sel)		BANKMASK(VAR16_ADDR(variable, byte_sel)), VAR_ACCESS
#define VAR32(variable, byte_sel)		BANKMASK(VAR32_ADDR(variable, byte_sel)), VAR_ACCESS

#define VAR_BIT(variable, bit)			BANKMASK(VAR8_ADDR(variable) + (bit / 8)), (bit mod 8), VAR_ACCESS

#define VAR_ADDR(variable)				(VAR_ ## variable)
#define VAR8_ADDR(variable)				(VAR_ ## variable)
#define VAR16_ADDR(variable, byte_sel)	LE_BYTE((VAR_ ## variable), byte_sel)
#define VAR32_ADDR(variable, byte_sel)	LE_BYTE((VAR_ ## variable), byte_sel)

; TODO: Move it to a right place
;-------------------------------------------------------------------------------
; Network configuration
; Keep it with this order! meminit fills this memory.
; This stuff is accessed only via FSRs.
;-------------------------------------------------------------------------------
PSECT config_vars,abs, ovrld, space=1,class=RAM
ORG 0xF00
arp_filter:			DS ARP_FILTER_LENGTH


; MAC address must be placed right before IP address (ARP packet aligned)
mac_addr:			DS ETH_ALEN
ip_addr:			DS IP_ALEN


;-------------------------------------------------------------------------------
; Ethernet buffer layout
;-------------------------------------------------------------------------------
	; Default values:
	; ERXND		1FFF	8191
	; ERXST		5FA		1530
	; ETXST		0
	; ETXEN		0
PSECT ethernet_buffer,abs,local,noexec,note,size=2000h,space=100,class=ETH
;ALIGN 2
eth_rx_start:
ORG 1C00h
eth_rx_end:

Tx_start:	DS 1							; PER-PACKET CONTROL BYTE
Tx_mac:		DS _mac_size					; MAC Header
Tx_arp:										; ARP Packet
Tx_ip:		DS _ip_size 					; IP Header
Tx_udp:		DS _udp_size					; UDP Header
Tx_payload:	DS 100h - 50					; Bootloader protocol data
Tx_status:	DS _tx_size						; 7-byte transmit status vector
Tx_end:										; Bootloader Packet end pointer
ORG 1F00h
TX_PAGE_BIT		EQU	1						; This is bit number, not a bit mask!

GLOBAL mem_init_data