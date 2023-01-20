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

ORG 0x60 - _rx_size - _mac_size		;	0x04c - 0x15D RX Frame RAM Buffer
Rx_buf:			DS _rx_size		; Receive Status Vector
Rx_mac:			DS _mac_size	; MAC Header
; Access RAM ends here
Rx_ip:			DS _ip_size		; IP Header
Rx_udp:			DS _udp_size	; UDP Header
Rx_data:
Rx_arp			EQU Rx_ip		; ARP Packet = IP Header

; Bank 0 ends on Rx_buf + 0xA1
;db 123



; Network configuration
; TODO: Move it to a right place
; Keep it with this order (ARP packet aligned)
mac_addr		EQU 0xF00
ip_addr			EQU 0xF06
arp_filter		EQU	0xF0A


;-------------------------------------------------------------------------------
; Ethernet buffer layout
;-------------------------------------------------------------------------------
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