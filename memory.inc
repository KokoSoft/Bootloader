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

; Used to store partial checksum by eth_checksum_ptr, eth_checksum_byte, eth_checksum, ip_checksum
checksumL:		DS 1
checksumH:		DS 1


lengthL:		DS 1
lengthH:		DS 1
ptrL:			DS 1
ptrH:			DS 1

; Parameters for eth_checksum_byte
; big endian! Used to checksum calculation! Eee? Chyba jednak nie?
check_lenH:		DS 1
check_lenL:		DS 1

; Partial UDP checksum (zero, protocol, src and dst address)
; I gave up with it. Using this cost 8 instruction words and 2 bytes of memory
; to allow saving a 6 instruction words and 3 CPU cycles.
;udp_cksumL:		DS 1
;udp_cksumH:		DS 1

ALIGN 0x10
;ORG 0x60 - _rx_size - _mac_size		; 0x60 - 0x07 - 0x0E - 0x14 =     0x04c - 0x15D RX Frame RAM Buffer
Rx_buf:			DS _rx_size		; Receive Status Vector
Rx_mac:			DS _mac_size	; MAC Header
; Access RAM ends here
Rx_ip:			DS _ip_size		; IP Header
; TODO: Mo¿na tutaj zrobiæ dziure na UDP pseudo header i jednym callem liczyæ sumê dla udp
Rx_udp:			DS _udp_size	; UDP Header
Rx_proto:
Rx_arp			EQU Rx_ip		; ARP Packet = IP Header

IF 5 > 0x60
	ERROR "Too much variables! Move Rx buffer to bank E."
ENDIF




; Network configuration
; TODO: Move it to a right place
; Keep it with this order (ARP packet aligned)
mac_addr		EQU 0xF00
ip_addr			EQU 0xF06
arp_filter		EQU	0xF0A

; Tx packet scratch pad
; TODO: Move it to a right place
;prep_boot_ip	EQU 0xE00 						; IP Header
;prep_boot_udp	EQU (prep_boot_ip + _ip_size)	; UDP Header



;-------------------------------------------------------------------------------
; Ethernet buffer layout
;-------------------------------------------------------------------------------
	; Default values:
	; ERXND		1FFF	8191
	; ERXST		5FA		1530
PSECT ethernet_buffer,abs,local,noexec,note,size=2000h,space=100,class=ETH
;ALIGN 2
eth_rx_start:
ORG 1E00h
eth_rx_end:

Tx_arp_start:	DS 1							; PER-PACKET CONTROL BYTE
Tx_arp_mac:		DS _mac_size					; MAC Header
Tx_arp:			DS _arp_size					; ARP Packet
Tx_arp_status:	DS _tx_size						; 7-byte transmit status vector
Tx_arp_end:										; ARP Packet end pointer
; Tx_arp_size	50 bytes

;ALIGN 2
ORG 1F00h

Tx_boot_start:	DS 1							; PER-PACKET CONTROL BYTE
Tx_boot_mac:	DS _mac_size					; MAC Header
Tx_boot_ip:		DS _ip_size 					; IP Header
Tx_boot_udp:	DS _udp_size					; UDP Header
Tx_boot:		DS 100h - 50					; Bootloader protocol data
Tx_boot_status:	DS _tx_size						; 7-byte transmit status vector
Tx_boot_end:									; Bootloader Packet end pointer

GLOBAL mem_init_data