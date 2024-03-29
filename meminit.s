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

#if ETH_LEDS
	;PORTA pins, RA0 and RA1.
	REG_WRITE(TRISA, 11111100B)	; Configure RA0 and RA1 as outputs - ETH LEDs
#endif

	; Receive filters configuration
	REG_WRITE(ERXFCON, RX_FILTER)

	; MAC initialization
	; MAC CONTROL REGISTER 1
	REG_WRITE(MACON1, MAC_CONTROL1)

	; MAC CONTROL REGISTER 3
	REG_WRITE(MACON3, MAC_CONTROL3)

#if !ETH_FULL_DUPLEX
	; MAC CONTROL REGISTER 4
	REG_WRITE(MACON4, MAC_CONTROL4)
#endif

	; Maximum frame length to be permitted to be received or transmitted.
	REG_WRITE(MAMXFLH, HIGH(ETH_MAX_LENGTH))
	REG_WRITE(MAMXFLL, LOW(ETH_MAX_LENGTH))

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

#if ETH_LEDS
	; PHY MODULE LED CONTROL REGISTER
	MII_WRITE(PHLCON, PHY_LED)
#endif

#if !TX_DOUBLE_BUFFERING
	; Ethernet Write Pointer High Byte
	REG_WRITE(EWRPTH, HIGH(BUF_Tx_start))

#if TX_BUFFER_SIZE == 256
	; Transmit End Pointer High Byte
	REG_WRITE(ETXNDH, HIGH(BUF_Tx_start))
#endif
#endif

#if TX_DOUBLE_BUFFERING
	; Initialize TX_PAGE value
	REG_WRITE(TX_PAGE_ADDR, HIGH(BUF_Tx_start))
#else
	; Transmit Start Pointer High Byte
	REG_WRITE(ETXSTH, HIGH(BUF_Tx_start))
#endif

	; Transmit Start Pointer Low Byte
	REG_WRITE(ETXSTL, LOW(BUF_Tx_start))

	; TODO: Remove debug leds
	REG_WRITE(TRISB, 11110000B)	; RB0 - RB3 Ledy
	REG_WRITE(LATB, 0x01)

	DB 0 ; End marker


;-------------------------------------------------------------------------------
; Memory initialization array
;-------------------------------------------------------------------------------
	MEM_INIT(arp_filter, ARP_FILTER_LENGTH + CONFIGURE_NETWORK_SIZE)

	; ARP request packet filter
	DW	BIGENDIAN(ARPHRD_ETHER)		; be16_t		hardwareAddressType
	DW	BIGENDIAN(ETH_TYPE_IP)		; be16_t		protocolAddressType
	DB	ETH_ALEN					; uint8_t		hardwareAddressLength  // in bytes
	DB	IP_ALEN						; uint8_t		protocolAddressLength  // in bytes
	DW	BIGENDIAN(ARP_OP_REQUEST)	; be16_t		opCode

IF CONFIGURE_NETWORK
	DB	MAC_ADDRESS
	DB	IP_ADDRESS

	; Network address configuration
	MEM_INIT(MAADR5, ETH_ALEN)
	DB	ETH_MAC_ADDR(MAC_ADDRESS)
ENDIF

	; Ethernet buffer configuration
	MEM_INIT(ERXSTL, 0x06)
	; ERXSTL:ERXSTH
	DW	eth_rx_start
	; ERXNDL:ERXNDH
	DW	eth_rx_end - 1
	; ERXRDPTL:ERXRDPTH
	DW	eth_rx_end - 1

	; End marker
	DB	0x00				; Size = 0
