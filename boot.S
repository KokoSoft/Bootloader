; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>
#include <xc.inc>
#include "config.inc"
#include "phy.inc"
#include "memory.inc"
#include "functions.inc"

;-------------------------------------------------------------------------------
; Processor configuration words
;-------------------------------------------------------------------------------
;config DEBUG = OFF		// Background Debugger Enable (Background debugger is enabled; RB6 and RB7 are dedicated to In-Circuit Debug)

; CONFIG1L
  CONFIG  WDT = OFF             ; Watchdog Timer Enable bit (WDT disabled (control is placed on SWDTEN bit))
  CONFIG  STVR = ON             ; Stack Overflow/Underflow Reset Enable bit (Reset on stack overflow/underflow enabled)
  CONFIG  XINST = OFF           ; Extended Instruction Set Enable bit (Instruction set extension and Indexed Addressing mode disabled (Legacy mode))

; CONFIG1H
  CONFIG  CP0 = OFF             ; Code Protection bit (Program memory is not code-protected)

; CONFIG2L
  CONFIG  FOSC = HSPLL          ; Oscillator Selection bits (HS oscillator, PLL enabled and under software control)
  CONFIG  FOSC2 = ON            ; Default/Reset System Clock Select bit (Clock selected by FOSC1:FOSC0 as system clock is enabled when OSCCON<1:0> = 00)
  CONFIG  FCMEN = ON            ; Fail-Safe Clock Monitor Enable (Fail-Safe Clock Monitor enabled)
  CONFIG  IESO = ON             ; Two-Speed Start-up (Internal/External Oscillator Switchover) Control bit (Two-Speed Start-up enabled)

; CONFIG2H
  CONFIG  WDTPS = 32768         ; Watchdog Timer Postscaler Select bits (1:32768)

; CONFIG3L

; CONFIG3H
  CONFIG  ETHLED = ON           ; Ethernet LED Enable bit (RA0/RA1 are multiplexed with LEDA/LEDB when Ethernet module is enabled and function as I/O when Ethernet is disabled)


;-------------------------------------------------------------------------------
; Bootloader entry point
;-------------------------------------------------------------------------------
PSECT code

;-------------------------------------------------------------------------------
; Bootloader services structure
;-------------------------------------------------------------------------------
start:
	BRA		init
	BRA		mem_init
	BRA		reg_init

init:
	MOVLB	0xE				; Select bank E

	; ERXSTL is used as zero reg. Initialized by reg_init
ZERO_REG	EQU ERXSTL
	CLRF	Rx_buf + _rx_nextL, a
	CLRF	Rx_buf + _rx_nextH, a

	; Set Flash pointer
	MOVLW	mem_init_data >> 16
	MOVWF	TBLPTRU, a
	MOVLW	HIGH(mem_init_data)
	MOVWF	TBLPTRH, a
	MOVLW	LOW(mem_init_data)
	MOVWF	TBLPTRL, a

;-------------------------------------------------------------------------------
; Ethernet configuration
;-------------------------------------------------------------------------------
	; The Ethernet SFRs with the 'E' prefix are always accessible,
	; regardless of whether or not the module is enabled.
	; Ethernet Module Enable
	BSF		ETHEN

	; Reset Transmit and Receive Logic
	MOVLW	ECON1_RXRST_MASK | ECON1_TXRST_MASK
	MOVWF	ECON1, a

	CLRF	ECON1, a
	; Wait for Ethernet PHY start-up timer has expired; PHY is ready
phy_init:
	BTFSS	PHYRDY
	BRA		phy_init

	; Call initialization functions
	_RCALL	reg_init
	_RCALL	mem_init

	; Enable packet reception
	MOVLW	ECON1_RXEN_MASK			; Receive Enable
	MOVWF	ECON1, a				; ETHERNET CONTROL REGISTER 1

	; Jump to received frame processor
	BRA		done_frame

;-------------------------------------------------------------------------------
; Frame processor
;-------------------------------------------------------------------------------
done_frame_pop:				; Verify functions jump here if an error was detected
	POP
	BRA		done_frame
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

	SUBFWB	ZERO_REG, b, W	; W = W - 0 - BORROW	; Use:    C
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
	BSF		LATB, 1, a
	; Read Receive Status Vector and ETH Header
	LFSR	2, Rx_buf		; Initialize Rx Buffer Pointer
	
MOVLW	_rx_size + _mac_size
	_RCALL	eth_read

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
	BSF		LATB, 2, a
	; Read the ARP packet from Eth to the buffer
	MOVLW	_arp_size
	_RCALL	eth_read

	; Check hardware and protocol address type and length, operation
	LFSR	0, Rx_arp
	LFSR	1, arp_filter
	MOVLW	ARP_FILTER_LENGTH
	_RCALL	memcmp

	; Is it directed to our IP?
	LFSR	0, Rx_arp + _arp_dst_ip
	LFSR	1, ip_addr
	MOVLW	IP_ALEN
	_RCALL	memcmp

	; Prepare ARP reply
	; Set ethernet buffer write pointer
	MOVLW	HIGH(Tx_arp + _arp_src_mac)
	MOVWF	EWRPTH, b
	MOVLW	LOW(Tx_arp + _arp_src_mac)
	MOVWF	EWRPTL, b

	; Set our MAC and IP as source
	LFSR	0, mac_addr
	MOVLW	ETH_ALEN + IP_ALEN
	_RCALL	eth_write

	; Source MAC and IP from request -> destination MAC and IP in response
	LFSR	0, Rx_arp + _arp_src_mac
	MOVLW	ETH_ALEN + IP_ALEN
	_RCALL	eth_write

	; Start transmission
	;MOVLW	_mac_size + _arp_size
	_BRA		eth_send

	


process_ip:

	BNZ		done_frame

END start; Bootloader entry point