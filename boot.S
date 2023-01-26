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

inc_dw MACRO var
	MOVLW	0
	INCF	var, a, f
	ADDWFC	var + 1, a, f
	ADDWFC	var + 2, a, f
	ADDWFC	var + 3, a, f
ENDM

PSECT code

;-------------------------------------------------------------------------------
; Bootloader services structure
;-------------------------------------------------------------------------------
;PSECT code, abs
;ORG	1FC00h
start:
	BRA		init
	_BRA		mem_init
	_BRA		reg_init

;-------------------------------------------------------------------------------
; Bootloader entry point
;-------------------------------------------------------------------------------
PSECT code
GLOBAL init
init:
	; Select bank E
	; Whole Bootloader uses access RAM and bank E only.
	MOVLB	0x0E

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

	; ERXSTL is used as zero reg. Initialized by reg_init
#define ZERO_REG	ERXSTL, b

	; Enable packet reception
	MOVLW	ECON1_RXEN_MASK			; Receive Enable
	MOVWF	ECON1, a				; ETHERNET CONTROL REGISTER 1

	inc_dw boot_counter

	; Jump to received frame processor
	BRA		done_frame

;-------------------------------------------------------------------------------
; Frame processor
;-------------------------------------------------------------------------------
done_frame_pop:				; Verify functions jump here if an error was detected
	; TODO: Move it to memcmp
	POP
done_frame:
	; Advance Eth read pointer (ERDPT)
	; Freeing Receive Buffer Space (ERXRDPT)
	; application must write to ERXRDPTL first, then to ERXRDPTH
	MOVF	Rx_buf + _rx_nextL, a, W
	MOVWF	ERDPTL, a

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

	SUBFWB	ZERO_REG, W		; W = W - 0 - BORROW	; Use:    C
	BTFSS	CARRY			; CARRY = !BORROW
	MOVLW	HIGH(eth_rx_end - 1)
	MOVWF	ERXRDPTH, b


wait_frame:					; Wait loop for receive network frame
	BTFSS	PKTIF			; Receive Packet Pending Interrupt Flag bit		a EIR		F 60h
	BRA		wait_frame

	; Decrement EPKTCNT
	BSF		PKTDEC			;												b ECON2		E FEh

;-------------------------------------------------------------------------------
; Incoming frame parser
;	1. Read the Next Packet Pointer, Receive Status Vector and the Ethernet Header to RAM Buffer
;	2. Check received ok, broadcast and Received Byte Count
;	3. Parse ethertype and jump to ARP or IP/UDP parser
;-------------------------------------------------------------------------------
parse_frame:
	BTG		LATB, 1, a
	
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

	inc_dw received_arp

	; Prepare ARP reply

	; Change opCode to reply
	MOVLW	LOW(ARP_OP_REPLY)
	MOVWF	Rx_arp + _arp_op + 1, a

	; Set ethernet buffer write pointer
	MOVLW	HIGH(Tx_arp_mac + _mac_type)
	MOVWF	EWRPTH, b
	MOVLW	LOW(Tx_arp_mac + _mac_type)
	MOVWF	EWRPTL, b

	; Write etherType and part of the ARP reply
	LFSR	0, Rx_mac + _mac_type
	MOVLW	2 + _arp_src_mac
	_RCALL	eth_write

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
	BSF		LATB, 2, a
	_BRA		eth_send

	
	; Every internet module must be able to forward a datagram of 68
	; octets without further fragmentation. This is because an internet
	; header may be up to 60 octets, and the minimum fragment is 8 octets.
	; Every internet destination must be able to receive a datagram of 576
	; octets either in one piece or in fragments to be reassembled.

process_ip:	; IP Datagram
	; Clear checksum
	CLRF	checksumL, a
	CLRF	checksumH, a

	; Read IP header
	MOVLW	_ip_size
	_RCALL	eth_read

	; IP header checksum calculation
	LFSR	0, Rx_ip
	MOVLW	_ip_size / 2
	_RCALL	ip_checksum

	; Check checksum
	COMF	checksumL, a
	BNZ		done_frame
	COMF	checksumH, a
	BNZ		done_frame

	; TODO: Check length!!!!

	; 4 bytes to check, 1 and mask, 11 instructions 
	; Check header version and size
	MOVLW	(IP_VERSION << 4) | (_ip_size / IP_SIZE_UNIT)
	XORWF	Rx_ip + _ip_ver, a, W
	BNZ		done_frame

	; Check destination ip address
	LFSR	0, Rx_ip + _ip_dst
	LFSR	1, ip_addr
	MOVLW	IP_ALEN
	; Skip if broadcast
	BTFSS	Rx_buf + RX_BROADCAST, a
	_RCALL	memcmp

ip_dst_checked:
	; Check flags - allow only don't fragment flag
	MOVLW	~HIGH(IP_FLAG_DF)
	ANDWF	Rx_ip + _ip_flags, a, W
	BNZ		done_frame
	; Non zero fragment offset is not allowed
	MOVF	Rx_ip + _ip_flags + 1, a, W
	BNZ		done_frame

	; Check protocol
	MOVLW	IP_PROTO_UDP
	XORWF	Rx_ip + _ip_proto, a, W
	BNZ		done_frame

	; IP payload length calculation
	MOVLW	_ip_size
	SUBWF	Rx_ip + _ip_len + 1, a, f
	CLRF	WREG, a
	SUBWFB	Rx_ip + _ip_len, a, f

process_udp:
	; Read UDP header
	MOVLW	_udp_size
	_RCALL	eth_read

	; Compare IP length with UDP length
	MOVF	Rx_ip + _ip_len + 1, a, W
	XORWF	Rx_udp + _udp_len + 1, a, W
	BNZ		done_frame
	MOVF	Rx_ip + _ip_len, a, W
	XORWF	Rx_udp + _udp_len, a, W
	BNZ		done_frame

	; Compute checksum
	; TODO: Move to function to save 1 instructions
	;CLRF	checksumH, a	; Zero - already here because IP checksum was correct
	MOVLW	IP_PROTO_UDP
	MOVWF	checksumL, a	; Protocol

	; Add IP source and destination address + udp header
	LFSR	0, Rx_ip + _ip_src
	MOVLW	(2 * IP_ALEN + _udp_size) / 2	; in words
	_RCALL	ip_checksum

	; UDP payload length calculation
	MOVLW	_udp_size
	SUBWF	Rx_udp + _udp_len + 1, a, f
	CLRF	WREG, a
	SUBWFB	Rx_udp + _udp_len, a, f

	; Save read pointer
	MOVFF	ERDPTH, ptrH
	MOVFF	ERDPTL, ptrL

	; Checksum UDP Payload
	MOVFF	Rx_udp + _udp_len, check_lenH
	MOVFF	Rx_udp + _udp_len + 1, check_lenL
	_RCALL	eth_checksum_byte

	; Restore read pointer
	MOVFF	ptrH, ERDPTH
	MOVFF	ptrL, ERDPTL

	; Validate checksum - compare with UDP Length from pseudo header.
	; This length is equal to length in the header (already modified) and
	; the current IP Length value (IP Header length already subtracted)
	; call ip_checksum with checksum in FSR0 will requre 2 words more.
	COMF	Rx_ip + _ip_len, a, W
	XORWF	checksumH, a, f		; XOR with checksum to clear checksum variable
	BNZ		done_frame
	COMF	Rx_ip + _ip_len + 1, a, W
	XORWF	checksumL, a, f
	BNZ		done_frame

	; Check destination port
	MOVLW	HIGH(UDP_PORT)
	XORWF	Rx_udp + _udp_dst, a, W
	BNZ		done_frame
	MOVLW	LOW(UDP_PORT)
	XORWF	Rx_udp + _udp_dst + 1, a, W
	BNZ		done_frame


bootloader_processor:
	inc_dw received_udp

	; Read current seq
	MOVLW	4
	_RCALL	eth_read

	; If seq == 0 -> Set clear counters flag
	CLRF	use_me, a
	MOVF	Rx_proto, a, W
	BNZ		no_clear
	MOVF	Rx_proto+1, a, W
	BNZ		no_clear
	MOVF	Rx_proto+2, a, W
	BNZ		no_clear
	MOVF	Rx_proto+3, a, W
	BNZ		no_clear
	MOVLW	1
	IORWF	use_me, a, f
no_clear:

	; Move eth write pointer to response start
	MOVLW	HIGH(Tx_boot)
	MOVWF	EWRPTH, b
	MOVLW	LOW(Tx_boot)
	MOVWF	EWRPTL, b

	; Firmware status
	MOVFF	RCON, EDATA
	SETF	RCON, a
	MOVFF	STKPTR, EDATA
	MOVFF	ESTAT, EDATA
	MOVFF	use_me, EDATA

	; Ethernet buffer pointers
	LFSR	0, ERXRDPTL
	MOVLW	4
	_RCALL	eth_write

	; Packets stats
	LFSR	0, last_seq
	MOVLW	4*4
	_RCALL	eth_write

	MOVFF	Rx_proto, last_seq
	MOVFF	Rx_proto+1, last_seq+1
	MOVFF	Rx_proto+2, last_seq+2
	MOVFF	Rx_proto+3, last_seq+3

	; Write current seq
	LFSR	0, Rx_proto
	MOVLW	4
	_RCALL	eth_write

	; Clear counters
	MOVF	use_me, a, W
	BZ		payload
	LFSR	0, boot_counter
	MOVLW	3*4
clear_stats:
	CLRF	POSTINC0, a
	DECF	WREG, a, f
	BNZ		clear_stats

payload:
; Substract seq length
	MOVLW	4
	SUBWF	Rx_udp + _udp_len + 1, a, f
	BZ		payload_end

	; Write xored payload
	MOVLW	0x5A
payload_byte:
	MOVFF	EDATA, temp0
	XORWF	temp0, a, W
	MOVFF	WREG, EDATA
	DECF	Rx_udp + _udp_len + 1, a, f
	BNZ		payload_byte
payload_end:








	; Write payload xored payload
;payload:
;	BNC		payload_end
;	MOVFF	EDATA, WREG
;	XORLW	0x5A
;	MOVFF	WREG, EDATA
;	BRA		payload
;payload_end:





udp_send:
	; Move source port to the destination port
	MOVFF	Rx_udp + _udp_src, Rx_udp + _udp_dst
	MOVFF	Rx_udp + _udp_src + 1, Rx_udp + _udp_dst + 1

	; Set source port
	MOVLW	HIGH(UDP_PORT)
	MOVWF	Rx_udp + _udp_src, a
	MOVLW	LOW(UDP_PORT)
	MOVWF	Rx_udp + _udp_src + 1, a

	; Calculate datagram length with header
	; Store it also in checksum field. It will act as UDP Length field
	; of the pseudo header
	MOVLW	LOW(Tx_boot_udp)
	SUBWF	EWRPTL, b, W
	MOVWF	Rx_udp + _udp_len + 1, a
	MOVWF	Rx_udp + _udp_cksum + 1, a
	MOVWF	Rx_ip + _ip_len + 1, a
	MOVWF	check_lenL, a

	MOVLW	HIGH(Tx_boot_udp)
	SUBWFB	EWRPTH, b, W
	MOVWF	Rx_udp + _udp_len, a
	MOVWF	Rx_udp + _udp_cksum, a
	MOVWF	Rx_ip + _ip_len, a
	MOVWF	check_lenH, a

	; Prepare pseudoheader checksum
	; TODO: Move to function to save 1 instructions
	;CLRF	checksumH, a	; Zero - already here because IP checksum was correct
	MOVLW	IP_PROTO_UDP
	MOVWF	checksumL, a	; Protocol

	; Add ip source and destination address, UDP Header
	LFSR	0, Rx_ip + _ip_src
	MOVLW	(2 * IP_ALEN + _udp_size) / 2	; in words
	_RCALL	ip_checksum

	; Calculate payload length
	MOVLW	_udp_size
	SUBWF	check_lenL, a, f
	MOVLW	0
	SUBWFB	check_lenH, a, f

	; Set ethernet read pointer
	MOVLW	HIGH(Tx_boot)
	MOVWF	ERDPTH, a
	MOVLW	LOW(Tx_boot)
	MOVWF	ERDPTL, a

	; Checksum UDP payload
	_RCALL	eth_checksum_byte

	; Finalize udp checksum
	; If the computed checksum is zero, it is transmitted as all ones
	; An all zero transmitted checksum value means that the transmitter generated no checksum
	COMF	checksumH, a, f
	BNZ		upd_checksum_not_zeroH
	COMF	checksumL, a, f
	BNZ		upd_checksum_not_zeroL

	SETF	checksumH, a
upd_checksum_not_zeroH:
	COMF	checksumL, a, f

upd_checksum_not_zeroL:
	; Set UDP checksum field
	MOVFF	checksumH, Rx_udp + _udp_cksum
	MOVFF	checksumL, Rx_udp + _udp_cksum + 1

ip_send:
	; Calculate IP Total Length
	MOVLW	_ip_size
	ADDWF	Rx_ip + _ip_len + 1, a, f
	MOVLW	0
	ADDWFC	Rx_ip + _ip_len, a, f

	; Set Time-to-live
	MOVLW	IP_DEF_TTL
	MOVWF	Rx_ip + _ip_ttl, a

	; Destination address
	LFSR	0,	Rx_ip + _ip_src
	LFSR	1,	Rx_ip + _ip_dst
	MOVLW	IP_ALEN
	_RCALL	memcpy

	; Source and destination address
	LFSR	0,	ip_addr
	LFSR	1,	Rx_ip + _ip_src
	MOVLW	IP_ALEN
	_RCALL	memcpy

	; Clear IP checksum field
	CLRF	Rx_ip + _ip_chsum, a
	CLRF	Rx_ip + _ip_chsum + 1, a

	; Checksum
	CLRF	checksumH, a
	CLRF	checksumL, a

	LFSR	0,	Rx_ip
	MOVLW	_ip_size / 2
	_RCALL	ip_checksum

	; Set IP checksum field
	COMF	checksumH, a, W
	MOVWF	Rx_ip + _ip_chsum, a
	COMF	checksumL, a, W
	MOVWF	Rx_ip + _ip_chsum + 1, a
	
	; Save the ethernet write pointer - datagram end marker
	MOVFF	EWRPTH, ptrH
	MOVFF	EWRPTL, ptrL

	; Move eth write pointer to EtherType of ETH header
	MOVLW	HIGH(Tx_boot_mac + _mac_type)
	MOVWF	EWRPTH, b
	MOVLW	LOW(Tx_boot_mac + _mac_type)
	MOVWF	EWRPTL, b

	; Write EtherType, IP and UDP header to the ethernet buffer
	; Source and destination MAC will be written by eth_write
	LFSR	0, Rx_mac + _mac_type
	MOVLW	2 + _ip_size + _udp_size
	_RCALL	eth_write

	; Restore the ethernet write pointer
	MOVFF	ptrH, EWRPTH
	MOVFF	ptrL, EWRPTL
	
	BSF		LATB, 3, a
;gdb:
;	BRA gdb
	;BCF		LATB, 3, a
	; Send data!
	_BRA		eth_send
	
END start; Bootloader entry point