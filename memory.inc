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
PSECT COMRAM
;-------------------------------------------------------------------------------
; RAM Memory map:
;-------------------------------------------------------------------------------
; Access RAM (0x00 - 0x5F)
temp0			EQU 0x000

;	0x05E - 0x15D RX Frame RAM Buffer
Rx_buf			EQU	0x04C				; Receive Status Vector
Rx_mac			EQU	Rx_buf + _rx_size	; MAC Header
; Access RAM ends here
Rx_ip			EQU Rx_mac + _mac_size	; IP Header
Rx_udp			EQU Rx_ip + _ip_size	; UDP Header
Rx_data			EQU	Rx_udp + _upd_size
Rx_arp			EQU Rx_ip				; ARP Packet = IP Header

; Bank 0 ends on Rx_buf + 0xA1


; Network configuration
; TODO: Move it to a right place
; Keep it with this order (ARP packet aligned)
mac_addr		EQU 0x600
ip_addr			EQU 0x606
arp_filter		EQU	0x60A


;-------------------------------------------------------------------------------
; Ethernet buffer layout
;-------------------------------------------------------------------------------
PSECT ethernet_buffer,abs,local,noexec,note,size=2000h,space=100
;ALIGN 2
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
; Tx_boot_size	50 bytes

;Tx_arp_start	EQU 0x000						; PER-PACKET CONTROL BYTE
;Tx_arp_mac		EQU Tx_arp_start + 0x001		; MAC Header
;Tx_arp			EQU Tx_arp_mac + _mac_size		; ARP Packet
;Tx_arp_status	EQU Tx_arp + _arp_size			; 7-byte transmit status vector
;Tx_arp_end		EQU Tx_arp_status + _tx_size	; ARP Packet end pointer
;; Tx_arp_size	50 bytes
;
;Tx_boot_start	EQU Tx_arp_end					; PER-PACKET CONTROL BYTE
;Tx_boot_mac		EQU Tx_boot_start + 0x001		; MAC Header
;Tx_boot_ip		EQU Tx_boot_mac + _mac_size		; IP Header
;Tx_boot_udp		EQU Tx_boot_ip + _ip_size		; UDP Header
;Tx_boot			EQU Tx_boot_udp + _udp_size		; Bootloader protocol data
;Tx_boot_status	EQU Tx_boot + 1000				; 7-byte transmit status vector
;Tx_boot_end		EQU Tx_boot_status + _tx_size	; ARP Packet end pointer


;-------------------------------------------------------------------------------
; Memory initialization array
;-------------------------------------------------------------------------------
PSECT mem_init,noexec
mem_init_data:

; ARP request packet filter
DB	0x08		; Size
DW	arp_filter	; Address

DW	0x00, 0x01	; be16_t		hardwareAddressType
DB	0x08, 0x00	; be16_t		protocolAddressType
DB	0x06		; uint8_t		hardwareAddressLength  // in bytes
DB	0x04		; uint8_t		protocolAddressLength  // in bytes
DB	0x00, 0x01	; be16_t		opCode

; ARP response packet template
DB	0x08							; Size
DW	Tx_arp_mac + _mac_type | 0x8000	; Address + Ethernet flag

DB	0x00, 0x01	; be16_t		hardwareAddressType
DB	0x08, 0x00	; be16_t		protocolAddressType
DB	0x06		; uint8_t		hardwareAddressLength  // in bytes
DB	0x04		; uint8_t		protocolAddressLength  // in bytes
DB	0x00, 0x02	; be16_t		opCode

; End marker
DB	0x00				; Size = 0