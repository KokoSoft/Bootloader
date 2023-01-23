; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>

#include <xc.inc>
#include "memory.inc"
#include "config.inc"
#include "phy.inc"

; MAADR5:MAADR6:MAADR3:MAADR4:MAADR1:MAADR2
#define ETH_MAC_ADDR2(a1, a2, a3, a4, a5, a6)	a5, a6, a3, a4, a1, a2
#define ETH_MAC_ADDR(arg)						ETH_MAC_ADDR2(arg)

#define MEM_INIT(address, size)					DB size, HIGH(address), LOW(address)
#define REG_ADDR(addr)			((addr) - REG_INIT_REF)
#define REG_WRITE(reg, val)		DB REG_ADDR(reg), val
#define REG_WRITE2(reg, val)	REG_ADDR(reg), val
#define MII_WRITE(reg, val)													\
	DB REG_WRITE2(MIREGADR, reg),	/* MII Address Register */				\
	REG_WRITE2(MIWRL, LOW(val)),	/* MII Write Data Register Low Byte */	\
	REG_WRITE2(MIWRH, HIGH(val))	/* MII Write Data Register High Byte */
#define BIGENDIAN(val)			(LOW(val) << 8 | HIGH(val))

PSECT mem_init,noexec,class=BOOT
mem_init_data:
;-------------------------------------------------------------------------------
; Registers initialization array
;-------------------------------------------------------------------------------
	; Enable PPL - Set 41.667 Mhz CPU Clock
	REG_WRITE(OSCTUNE, OSCTUNE_PLLEN_MASK)

	;PORTA pins, RA0 and RA1.
	REG_WRITE(LATB, 0x00)
	REG_WRITE(TRISA, 11111100B)	; Configure RA0 and RA1 as outputs - ETH LEDs
	REG_WRITE(TRISB, 11110000B)	; RB0 - RB3 Ledy
    
	; Receive filters configuration
	REG_WRITE(ERXFCON, RX_FILTER)

	; MAC initialization
	; MAC CONTROL REGISTER 1
	REG_WRITE(MACON1, MAC_CONTROL1)

	; MAC CONTROL REGISTER 3
	REG_WRITE(MACON3, MAC_CONTROL3)

	; Maximum frame length to be permitted to be received or transmitted.
	REG_WRITE(MAMXFLH, HIGH(RX_LENGTH_MAX))
	REG_WRITE(MAMXFLL, LOW(RX_LENGTH_MAX))

	; MAC Non Back-to-Back Inter-Packet Gap Register
	REG_WRITE(MAIPGL, LOW(NBB_GAP))
	REG_WRITE(MAIPGH, HIGH(NBB_GAP))

	; MAC Back-to-Back Inter-Packet Gap Register
	REG_WRITE(MABBIPG, BB_GAP)

    ; PHY initialization
	; PHY CONTROL REGISTER 1
	MII_WRITE(PHCON1, PHY_CONTROL1)

	; PHY CONTROL REGISTER 2
	MII_WRITE(PHCON2, PHY_CONTROL2)

	; PHY MODULE LED CONTROL REGISTER
	MII_WRITE(PHLCON, PHY_LED)

	REG_WRITE(LATB, 0x01)

	DB 0 ; End marker


;-------------------------------------------------------------------------------
; Memory initialization array
;-------------------------------------------------------------------------------
IF CONFIGURE_NETWORK
	; Network address configuration
	MEM_INIT(MAADR5, 6)							; 06 0e 80
	DB	ETH_MAC_ADDR(MAC_ADDRESS)				; B2 31 4F 4C 2A CB

	MEM_INIT(mac_addr, 10 + ARP_FILTER_LENGTH)
	DB	MAC_ADDRESS								; 0x2A, 0xCB, 0x4F, 0x4C, 0xB2, 0x31
	DB	IP_ADDRESS
ELSE
	MEM_INIT(arp_filter, ARP_FILTER_LENGTH)
ENDIF

	; ARP request packet filter
	DW	BIGENDIAN(ARPHRD_ETHER)		; be16_t		hardwareAddressType
	DW	BIGENDIAN(ETH_TYPE_IP)		; be16_t		protocolAddressType
	DB	ETH_ALEN					; uint8_t		hardwareAddressLength  // in bytes
	DB	IP_ALEN						; uint8_t		protocolAddressLength  // in bytes
	DW	BIGENDIAN(ARP_OP_REQUEST)	; be16_t		opCode

	; ARP response packet template
	MEM_INIT(Tx_arp_mac + _mac_type | INIT_ADDR_ETH, 0x0A)
	DW	BIGENDIAN(ETH_TYPE_ARP)		; be16_t		etherType
	DW	BIGENDIAN(ARPHRD_ETHER)		; be16_t		hardwareAddressType
	DW	BIGENDIAN(ETH_TYPE_IP)		; be16_t		protocolAddressType
	DB	ETH_ALEN					; uint8_t		hardwareAddressLength  // in bytes
	DB	IP_ALEN						; uint8_t		protocolAddressLength  // in bytes
	DW	BIGENDIAN(ARP_OP_REPLY)		; be16_t		opCode

	; Ethernet buffer configuration
	MEM_INIT(ERXSTL, 0x06)
	; ERXSTL:ERXSTH
	DW	eth_rx_start
	; ERXNDL:ERXNDH
	DW	eth_rx_end - 1
	; ERXRDPTL:ERXRDPTH
	DW	eth_rx_end - 1

#if 0
	; Bootloader protocol response template
	MEM_INIT(Tx_boot_mac + _mac_type | INIT_ADDR_ETH, 0x04)
	DW	BIGENDIAN(ETH_TYPE_IP)							; be16_t		etherType
	DB	(IP_VERSION << 4) | (IP_HLEN / IP_SIZE_UNIT)	; uint8_t		Version_HeaderLength
	DB	0												; uint8_t		TypeOfService

_ip_len			EQU 0x002	; be16_t		TotalLength
_ip_id			EQU 0x004	; be16_t		Identification

	DW	0												; be16_t		Flags_Offset
	DB	IP_DEF_TTL										; uint8_t		TimeToLive
	DB	IP_PROTO_UDP									; uint8_t		Protocol


_ip_chsum		EQU 0x00A	; be16_t		HeaderChecksum
_ip_src			EQU 0x00C	; IP_Address	SourceAddress
_ip_dst			EQU 0x010	; IP_Address	DestinationAddress


_udp_src		EQU 0x000	; be16_t		Source port 
_udp_dst		EQU 0x002	; be16_t		Destination port
_udp_len		EQU 0x004	; be16_t		Length
_udp_cksum		EQU 0x006	; be16_t		Checksum 

; Zerujac bufor trzeba ustawiæ tylko 5 bajtów (ethType, ip_ver, ttl, proto, upd_src_port)
;   Tablica offset:value 10 bajtów
;   + ~9 (18 bajtów!) instrukcji na ustawiaczke
;   no to mamy ju¿ 28 bajtów, wiecej niz inicjaja ca³ego ip

; Bez zerowania 8 bajtów
; 13 bajtów w pamiêci (18 z portem udp)
; Zerowanko i tak nam siê przyda przy liczeniu sumy kontrolnej
; Inicjalizacja pocz¹tku IP z ethertype = 12 bajtów = 15 bajtów
; Inicjalizacja ca³ego IP, ethertype i portu udp = 24 = 27 bajtów
#endif
	; End marker
	DB	0x00				; Size = 0

