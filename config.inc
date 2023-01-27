; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>

#include "phy.inc"

;-------------------------------------------------------------------------------
; Bootloader configuration
;-------------------------------------------------------------------------------
; Predefine MAC and IP addresses - cost 19 bytes (10 instructions)
;Set to 1 to set default network addresses
#define CONFIGURE_NETWORK			1

#define IP_ADDRESS			10, 11, 12, 13
#define MAC_ADDRESS			0x2A, 0xCB, 0x4F, 0x4C, 0xB2, 0x31
UDP_PORT			EQU 666	; UDP port used by bootloader to communicate


; 854+89

/* Use dedicated function to checksum ip header */
#define IP_HEADER_FAST_CHECKSUM		0

; Allow write multiple sectors with single frame - costs 12 instructions
#define MULTIBLOCK_WRITE			0
; Use bigger net_config frame (two MAC address formats) - save 8 instructions
#define NET_CONFIG_MAC_EXTENDED		0
; Ethernet LEDs control enable - cost 10 bytes (5 instructions)
#define ETH_LEDS					1

; Use full-duplex connections - save 2 bytes (1 instruction)
#define ETH_FULL_DUPLEX				1

;-------------------------------------------------------------------------------
; Ethernet module configuration
;-------------------------------------------------------------------------------
; Receive filters configuration - Broadcast Filter | Unicast Filter | Post-Filter CRC Check
RX_FILTER			EQU ERXFCON_BCEN_MASK | ERXFCON_UCEN_MASK | ERXFCON_CRCEN_MASK

; Maximum frame length to be permitted to be received or transmitted.
RX_LENGTH_MAX		EQU 1518

#if ETH_FULL_DUPLEX
	; MAC Receive Enable, Pause Control Frame Reception Enable, Pause Control Frame Transmission Enable
	MAC_CONTROL1		EQU MACON1_MARXEN_MASK | MACON1_RXPAUS_MASK | MACON1_TXPAUS_MASK

	; MAC Full-Duplex Enable, Frame Length Checking Enable, Transmit CRC Enable
	; All short frames are zero-padded to 60 bytes and a valid CRC is appended
	MAC_CONTROL3		EQU MACON3_FULDPX_MASK | MACON3_FRMLNEN_MASK | MACON3_TXCRCEN_MASK | (1 << MACON3_PADCFG0_POSN)

	; Configure full duplex connection
	; MAC Non Back-to-Back Inter-Packet Gap
	NBB_GAP				EQU 0x12

	; MAC Back-to-Back Inter-Packet Gap Register
	BB_GAP				EQU 0x15

	PHY_CONTROL1		EQU PHCON1_PDPXMD_MASK
#else
	; MAC Receive Enable
	MAC_CONTROL1		EQU MACON1_MARXEN_MASK

	; Frame Length Checking Enable, Transmit CRC Enable
	; All short frames are zero-padded to 60 bytes and a valid CRC is appended
	MAC_CONTROL3		EQU MACON3_FRMLNEN_MASK | MACON3_TXCRCEN_MASK | (1 << MACON3_PADCFG0_POSN)

	; MAC Non Back-to-Back Inter-Packet Gap
	NBB_GAP				EQU 0xC12

	; MAC Back-to-Back Inter-Packet Gap Register
	BB_GAP				EQU 0x12

	; When the medium is occupied, the MAC waits indefinitely
	; for it to become free when attempting to transmit
	; Defer Transmission Enable
	MAC_CONTROL4		EQU MACON4_DEFER_MASK

	PHY_CONTROL1		EQU 0
#endif


; RX+/RX- Operating mode, PHY Half-Duplex Loopback Disable
; Improper Ethernet operation may result if HDLDIS or RXAPDIS is cleared, which is the Reset default.
PHY_CONTROL2		EQU PHCON2_RXAPDIS_MASK | PHCON2_HDLDIS_MASK

; LED Pulse Stretching Enable, LED Pulse Stretch Time Configuration, LEDA Configuration bits - Green,
; LEDB Configuration bits - Yellow, Write as `1`
PHY_LED				EQU (1 << PHLCON_STRCH_POSN) | (PHY_LED_STR_NORMAL << PHLCON_LFRQ_POSN) | (PHY_LED_LINK_RX_ACT << PHLCON_LACFG_POSN) | (PHY_LED_TX_ACT << PHLCON_LBCFG_POSN) | PHLCON_MUST1_MASK

;-------------------------------------------------------------------------------
; Bootloader constants
;-------------------------------------------------------------------------------
ARP_FILTER_LENGTH	EQU 0x08
REG_INIT_REF		EQU 0xF20

; Assembler directives (e.g., EQU) will be processed regardless of the state
; of the condition expression and should not be used inside an IF construct.
; We must use preprocessor #if
#if CONFIGURE_NETWORK
	CONFIGURE_NETWORK_SIZE	EQU ETH_ALEN + IP_ALEN
#else
	CONFIGURE_NETWORK_SIZE	EQU 0
#endif
