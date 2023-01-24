; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>

#include "phy.inc"

;-------------------------------------------------------------------------------
; Bootloader configuration
;-------------------------------------------------------------------------------
CONFIGURE_NETWORK	EQU 1	; Set to 1 to set default network addresses
#define IP_ADDRESS			10, 0, 1, 250
#define MAC_ADDRESS			0x2A, 0xCB, 0x4F, 0x4C, 0xB2, 0x31
UDP_PORT			EQU 666	; UDP port used by bootloader to communicate

;-------------------------------------------------------------------------------
; Ethernet module configuration
;-------------------------------------------------------------------------------
; Receive filters configuration - Broadcast Filter | Unicast Filter | Post-Filter CRC Check
RX_FILTER			EQU ERXFCON_BCEN_MASK | ERXFCON_UCEN_MASK | ERXFCON_CRCEN_MASK

; MAC Receive Enable, Pause Control Frame Reception Enable, Pause Control Frame Transmission Enable
MAC_CONTROL1		EQU MACON1_MARXEN_MASK | MACON1_RXPAUS_MASK | MACON1_TXPAUS_MASK

; MAC Full-Duplex Enable, Frame Length Checking Enable, Transmit CRC Enable
; All short frames are zero-padded to 60 bytes and a valid CRC is appended
MAC_CONTROL3		EQU MACON3_FULDPX_MASK | MACON3_FRMLNEN_MASK | MACON3_TXCRCEN_MASK | (1 << MACON3_PADCFG0_POSN)

; Maximum frame length to be permitted to be received or transmitted.
RX_LENGTH_MAX		EQU 1518

; Configure full duplex connection
; MAC Non Back-to-Back Inter-Packet Gap
NBB_GAP				EQU 0x12

; MAC Back-to-Back Inter-Packet Gap Register
BB_GAP				EQU 0x15

PHY_CONTROL1		EQU PHCON1_PDPXMD_MASK

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
INIT_ADDR_ETH		EQU	0x8000
