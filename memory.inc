; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>
#include "net.inc"

; FSR0 - Source Pointer parameter
; FSR1 - Destination Pointer parameter
; FSR2 - RX Frame RAM Buffer write pointer


PSECT boot_vars,space=1
PSECT rx_buffer,abs, ovrld, space=1,class=COMRAM
;-------------------------------------------------------------------------------
; RAM Memory map:
;-------------------------------------------------------------------------------
; Access RAM (0x00 - 0x5F)
temp0:			DS 1
use_me:			DS 1

; Used to store partial checksum by eth_checksum_ptr, eth_checksum_byte, eth_checksum, ip_checksum
checksumH:		DS 1
checksumL:		DS 1

; Used to temporarly store of ethernet ram read/write pointer
; Can be outside of access ram
ptrH:			DS 1
ptrL:			DS 1

; Parameters for eth_checksum_byte
; Lenght of a data to be checksumed
check_lenH:		DS 1
check_lenL:		DS 1


;ALIGN 0x10 DO NOT USE ALIGN!!!! Assembler bug?!
;ORG 0x60 - (_rx_size + _mac_size + _ip_size + _udp_size)		; 0x60 - 0x07 - 0x0E - 0x14 = 2F - 0x15D RX Frame RAM Buffer
ORG 0x20 - _rx_size
Rx_buf:			DS _rx_size		; Receive Status Vector
Rx_mac:			DS _mac_size	; MAC Header
; Access RAM ends here
Rx_arp:							; ARP Packet = IP Header
Rx_ip:			DS _ip_size		; IP Header
Rx_udp:			DS _udp_size	; UDP Header
Rx_proto:

IF 5 > 0x60
	ERROR "Too much variables! Move Rx buffer to bank E."
ENDIF




; Network configuration
; TODO: Move it to a right place
; Keep it with this order (ARP packet aligned)
arp_filter		EQU	0xF00
mac_addr		EQU arp_filter + ARP_FILTER_LENGTH
ip_addr			EQU mac_addr + ETH_ALEN


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
ORG 1F00h
eth_rx_end:

Tx_start:		DS 1							; PER-PACKET CONTROL BYTE
Tx_mac:			DS _mac_size					; MAC Header
Tx_arp:											; ARP Packet
Tx_ip:						 					; IP Header
				DS _ip_size
Tx_udp:			DS _udp_size					; UDP Header
Tx_boot:										; Bootloader protocol data

GLOBAL mem_init_data
