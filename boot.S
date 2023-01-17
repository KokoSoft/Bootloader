; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>
#include <xc.inc>
#include "phy.inc"
#include "memory.inc"


GLOBAL eth_read
GLOBAL eth_read
GLOBAL memcmp
GLOBAL memcmp
GLOBAL eth_write
GLOBAL eth_write
GLOBAL eth_send

PSECT boot,space=0
PSECT code

; Default values
;ERXND		1FFF	8191
;ERXST		5FA		1530

;-------------------------------------------------------------------------------
; Memory initializer (34 words)
;
; Init block structure:
;	DB size		- 0 - end marker
;	DW address	- big endian! Set MSB to address ethernet RAM 
;	DB data * size
;-------------------------------------------------------------------------------
mem_init:
	; Set Flash pointer
	MOVLW	mem_init_data >> 16
	MOVWF	TBLPTRU, a
	MOVLW	HIGH(mem_init_data)
	MOVWF	TBLPTRH, a
	MOVLW	LOW(mem_init_data)
	MOVWF	TBLPTRL, a

mem_init_header:
	TBLRD*+					; read Flash post-increment
	MOVF	TABLAT, a, W	; size
	BZ		mem_init_done

	TBLRD*+					; read high address byte
	BTFSC	TABLAT, 7, a	; Check MSB: 0 - ram, 1 - eth
	BRA		mem_init_eth

mem_init_ram:
	MOVFF	TABLAT, FSR1H
	TBLRD*+					; read low address byte
	MOVFF	TABLAT, FSR1L

mem_init_ram_loop:
	TBLRD*+
	MOVFF	TABLAT, POSTINC1
	DECFSZ	WREG, a, W
	BRA		mem_init_ram_loop
	BRA		mem_init_header

mem_init_eth:
	MOVFF	TABLAT, EWRPTH
	TBLRD*+					; read low address byte
	MOVFF	TABLAT, EWRPTL

mem_init_eth_loop:
	TBLRD*+
	MOVFF	TABLAT, EDATA
	DECFSZ	WREG, a, W
	BRA		mem_init_eth_loop
	BRA		mem_init_header

mem_init_done:



;-------------------------------------------------------------------------------
; Ethernet configuration
;-------------------------------------------------------------------------------
	; The Ethernet SFRs with the ‘E’ prefix are always accessible,
	; regardless of whether or not the module is enabled.
	; Ethernet Module Enable
	BSF		ETHEN

	; Reset Transmit and Receive Logic
	MOVLW	ECON1_RXRST_MASK | ECON1_TXRST_MASK
	MOVWF	ECON1, a

	; Receive filters configuration - Broadcast Filter | Unicast Filter | Post-Filter CRC Check
	MOVLW	ERXFCON_BCEN_MASK | ERXFCON_UCEN_MASK | ERXFCON_CRCEN_MASK
	MOVWF	ERXFCON, b

	; Wait for Ethernet PHY start-up timer has expired; PHY is ready
phy_init:
	BTFSS	PHYRDY
	BRA		phy_init

	; Receive Start Register
	CLRF	ERXSTL, b
	CLRF	ERXSTH, b

	; Receive End Register and Receive Buffer Read Pointer
	; To program the ERXRDPT registers, write to ERXRDPTL first, followed by ERXRDPTH.
	SETF	ERXNDL, b
	SETF	ERXRDPTL, b
	MOVLW	HIGH(eth_rx_end)
	MOVWF	ERXNDH, b
	MOVWF	ERXRDPTH, b

	; MAC initialization

	; Between any instruction which addresses a MAC or MII register, at least one NOP or other
	; instruction must be executed.

	; MAC Receive Enable, Pause Control Frame Reception Enable, Pause Control Frame Transmission Enable
	MOVLW	MACON1_MARXEN_MASK | MACON1_RXPAUS_MASK | MACON1_TXPAUS_MASK  
	MOVWF	MACON1, b				; MAC CONTROL REGISTER 1

	; MAC Full-Duplex Enable, Frame Length Checking Enable, Transmit CRC Enable
	; All short frames are zero-padded to 60 bytes and a valid CRC is appended
	MOVLW	MACON3_FULDPX_MASK | MACON3_FRMLNEN_MASK | MACON3_TXCRCEN_MASK | (1 << MACON3_PADCFG0_POSN)
	MOVWF	MACON3, b				; MAC CONTROL REGISTER 3

	; Maximum frame length to be permitted to be received or transmitted.
	MOVLW	HIGH(1518)
	MOVWF	MAMXFLH, b
	MOVLW	LOW(1518)
	MOVWF	MAMXFLL, b

	; Configure full duplex connection
	MOVLW	0x12
	MOVWF	MAIPGL, b				; MAC Non Back-to-Back Inter-Packet Gap Register
	CLRF	MAIPGH, b
	MOVLW	0x15
	MOVWF	MABBIPG, b				; MAC Back-to-Back Inter-Packet Gap Register

    ; TODO: Program the local MAC address
    ;MAADR1 = my_mac.b[0];
    ;MAADR2 = my_mac.b[1];
    ;MAADR3 = my_mac.b[2];
    ;MAADR4 = my_mac.b[3];
    ;MAADR5 = my_mac.b[4];
    ;MAADR6 = my_mac.b[5];

    ; PHY initialization
	; The PHY registers must not be read or written to until the PHY start-up timer has expired

	; PHY CONTROL REGISTER 1
	MOVLW	PHCON1
	MOVWF	MIREGADR, b				; MII Address Register

	MOVLW	LOW(PHCON1_PDPXMD_MASK)	; PHY Duplex Mode
	MOVWF	MIWRL, b				; MII Write Data Register Low Byte

	; Errata: Between a write to the MIWRL and MIWRH, the core mustn't executes any
	; instruction that reads or writes to any memory address that has the
	; Least Significant six address bits of 36h (‘b11 0110)
	
	; Writing to this register automatically begins the MII transaction, so it must
	; be written to after MIWRL. The BUSY bit is set automatically after two TCY.
	MOVLW	HIGH(PHCON1_PDPXMD_MASK)
	MOVWF	MIWRH, b				; MII Write Data Register High Byte

mii_busy:
	BTFSC	BUSY					; MII Management Busy (MISTAT.BUSY)
	BRA		mii_busy

	; PHY CONTROL REGISTER 2
	; RX+/RX- Operating mode, PHY Half-Duplex Loopback Disable
	; Improper Ethernet operation may result if HDLDIS or RXAPDIS is cleared, which is the Reset default.
	MOVLW	PHCON2
	MOVWF	MIREGADR, b				; MII Address Register

	MOVLW	LOW(PHCON2_RXAPDIS_MASK | PHCON2_HDLDIS_MASK)
	MOVWF	MIWRL, b				; MII Write Data Register Low Byte

	MOVLW	HIGH(PHCON2_RXAPDIS_MASK | PHCON2_HDLDIS_MASK)
	MOVWF	MIWRH, b				; MII Write Data Register High Byte

mii_busy2:
	BTFSC	BUSY					; MII Management Busy (MISTAT.BUSY)
	BRA		mii_busy2

	; LED Pulse Stretching Enable, LED Pulse Stretch Time Configuration, LEDA Configuration bits - Green,
	; LEDB Configuration bits - Yellow, Write as `1`
	PHLCON_VAL EQU (1 << PHLCON_STRCH_POSN) | (PHY_LED_STR_NORMAL << PHLCON_LFRQ_POSN) | (PHY_LED_LINK_RX_ACT << PHLCON_LACFG_POSN) | (PHY_LED_TX_ACT << PHLCON_LBCFG_POSN) | PHLCON_MUST1_MASK
	; PHY MODULE LED CONTROL REGISTER
	MOVLW	PHLCON
	MOVWF	MIREGADR, b				; MII Address Register

	MOVLW	LOW(PHLCON_VAL)
	MOVWF	MIWRL, b				; MII Write Data Register Low Byte

	MOVLW	HIGH(PHLCON_VAL)
	MOVWF	MIWRH, b				; MII Write Data Register High Byte

	; Enable packet reception
	MOVLW	ECON1_RXEN_MASK			; Receive Enable
	MOVWF	ECON1, a				; ETHERNET CONTROL REGISTER 1







init:
	MOVLB	0xE				; Select bank E
	CLRF	ETXSTL, b		; Ethernet Transmit Start (zero after reset)
	CLRF	Rx_buf + _rx_nextL, a
	CLRF	Rx_buf + _rx_nextH, a
	; ERXSTH is used as zero reg

;-------------------------------------------------------------------------------
; Frame processor
;-------------------------------------------------------------------------------
done_frame_pop:				; Verify functions jump here if an error was detected
	POP
done_frame:
	; Advance Eth read pointer (ERDPT)
	; Freeing Receive Buffer Space (ERXRDPT)
	; application must write to ERXRDPTL first, then to ERXRDPTH
	MOVF	Rx_buf + _rx_nextL, a, W
	MOVWF	ERDPTL, a
	;MOVWF	ERXRDPTL, b

	; Errata
	; The receive hardware may corrupt the circular receive buffer (including the Next Packet Pointer
	; and receive status vector fields) when an even value is programmed into the ERXRDPTH:ERXRDPTL registers.
	; 
	; Work around
	; Ensure that only odd addresses are written to the ERXRDPT registers. Assuming that ERXND contains
	; an odd value, many applications can derive a suitable value to write to ERXRDPT by subtracting
	; 1 from the Next Packet Pointer (a value always ensured to be even because of hardware
	; padding) and then compensating for a potential ERXST to ERXND wrap-around.

	DECF	WREG, a, W		; ERXRDPTL = next - 1	; Status: C, DC, Z, OV, N
	MOVWF	ERXRDPTL, b								; Status: None

	MOVF	Rx_buf + _rx_nextH, a, W				; Status:        Z,     N
	MOVWF	ERDPTH, a								; Status: None
	;MOVWF	ERXRDPTH, b

	SUBFWB	ERXSTH, b, W	; W = W - 0 - BORROW	; Use:    C
	BTFSS	CARRY			; CARRY = !BORROW
	MOVLW	HIGH(eth_rx_end - 1)
	MOVWF	ERXRDPTH, b

	; Decrement EPKTCNT
	; Attempting to decrement EPKTCNT below 0 does not cause an underflow to 255
	BSF		PKTDEC			;												b ECON2		E FEh

wait_frame:					; Wait loop for receive network frame
	BTFSS	PKTIF			; Receive Packet Pending Interrupt Flag bit		a EIR		F 60h
	BRA		wait_frame


;-------------------------------------------------------------------------------
; Incoming frame parser
;	1. Read the Next Packet Pointer, Receive Status Vector and the Ethernet Header to RAM Buffer
;	2. Check received ok, broadcast and Received Byte Count
;	3. Parse ethertype and jump to ARP or IP/UDP parser
;-------------------------------------------------------------------------------
parse_frame:
	; Read Receive Status Vector and ETH Header
	LFSR	2, Rx_buf		; Initialize Rx Buffer Pointer
	
MOVLW	_rx_size + _mac_size
	RCALL	eth_read

	; Ethernet has a minimum frame size of 64 bytes, comprising an 18-byte header and a payload of 46 bytes.
	; It also has a maximum frame size of 1518 bytes, in which case the payload is 1500 bytes.

	; Check ether_type high byte == 0x80
	MOVF	Rx_mac + _mac_type, a, W
	XORLW	HIGH(ETH_TYPE_ARP)	
	BNZ		done_frame

	; Check ether_type low byte
	MOVF	Rx_mac + _mac_type + 1, a, W
	BZ		process_ip			; IP = 80 00
	XORLW	LOW(ETH_TYPE_ARP)	; ARP = 80 06
	BNZ		done_frame

;-------------------------------------------------------------------------------
; ARP packet processor
;-------------------------------------------------------------------------------
process_arp:
	; Read the ARP packet from Eth to the buffer
	MOVLW	_arp_size
	RCALL	eth_read

	; Check hardware and protocol address type and length, operation
	LFSR	0, Rx_arp
	LFSR	1, arp_filter
	MOVLW	8
	RCALL	memcmp

	; Is it directed to our IP?
	LFSR	0, Rx_arp + _arp_dst_ip
	LFSR	1, ip_addr
	MOVLW	4
	RCALL	memcmp

	; Prepare ARP reply
	; Set ethernet buffer write pointer
	MOVLW	HIGH(Tx_arp + _arp_src_mac)
	MOVWF	EWRPTH, b
	MOVLW	LOW(Tx_arp + _arp_src_mac)
	MOVWF	EWRPTL, b

	; Set our MAC and IP as source
	LFSR	0, mac_addr
	MOVLW	6+4
	RCALL	eth_write

	; Source MAC and IP from request -> destination MAC and IP in response
	LFSR	0, Rx_arp + _arp_src_mac
	MOVLW	6+4
	RCALL	eth_write

	; Start transmission
	;MOVLW	_mac_size + _arp_size
	BRA		eth_send

	


process_ip:

	BNZ		done_frame


END mem_init ; Firmware entry point