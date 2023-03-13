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


PSECT code

;-------------------------------------------------------------------------------
; Bootloader services structure
;-------------------------------------------------------------------------------
;PSECT code, abs
;ORG	1FC00h
start:
	BRA		init
	BRA		mem_init
	BRA		reg_init

;-------------------------------------------------------------------------------
; Bootloader entry point
;-------------------------------------------------------------------------------
PSECT code
GLOBAL init
init:
	; Select bank E
	; Whole Bootloader uses access RAM and bank E only.
	MOVLB	0x0E

	CLRF	RX_LE16(rx, next, L)
	CLRF	RX_LE16(rx, next, H)

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
	RCALL	reg_init
	RCALL	mem_init

	; ERXSTL is used as zero reg. Initialized by reg_init
#define ZERO_REG	ERXSTL, b

	; Enable packet reception
	MOVLW	ECON1_RXEN_MASK			; Receive Enable
	MOVWF	ECON1, a				; ETHERNET CONTROL REGISTER 1

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
	MOVF	RX_LE16(rx, next, L), W
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

	MOVF	RX_LE16(rx, next, H), W					; Status:        Z,     N
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

	; Switch Tx buffer page
	tx_switch_buffer


;-------------------------------------------------------------------------------
; Incoming frame parser
;	1. Read the Next Packet Pointer, Receive Status Vector and the Ethernet Header to RAM Buffer
;	2. Check received ok, broadcast and Received Byte Count
;	3. Parse ethertype and jump to ARP or IP/UDP parser
;-------------------------------------------------------------------------------
parse_frame:
	BTG		LATB, 1, a
	
	; Read Receive Status Vector and ETH Header
	LFSR	2, RX_PROTO(rx)		; Initialize Rx Buffer Pointer
	
	MOVLW	_rx_size + _mac_size
	RCALL	eth_read

	; Ethernet has a minimum frame size of 64 bytes, comprising an 18-byte header and a payload of 46 bytes.
	; It also has a maximum frame size of 1518 bytes, in which case the payload is 1500 bytes.
	; Check ether_type high byte == 0x80
	MOVF	RX_BE16(mac, type, H), W
	XORLW	HIGH(ETH_TYPE_ARP)	
	BNZ		done_frame

	; Check ether_type low byte
	MOVF	RX_BE16(mac, type, L), W
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
	LFSR	0, RX_PROTO(arp)
	LFSR	1, arp_filter
	MOVLW	ARP_FILTER_LENGTH
	RCALL	memcmp

	; Is it directed to our IP?
	LFSR	0, RX_ADDR(arp, dst_ip)
	LFSR	1, ip_addr
	MOVLW	IP_ALEN
	RCALL	memcmp

	; Prepare ARP reply

	; Change opCode to reply
	MOVLW	LOW(ARP_OP_REPLY)
	MOVWF	RX_BE16(arp, op, L)

	; Set ethernet buffer write pointer
	eth_write_pos	TX_ADDR(mac, type)

	; Wait for transmitter idle before modifying the buffer content
	tx_wait

	; Write etherType and part of the ARP reply
	LFSR	0, RX_ADDR(mac, type)
	MOVLW	2 + _arp_src_mac
	RCALL	eth_write

	; Set our MAC and IP as source
	LFSR	0, mac_addr
	MOVLW	ETH_ALEN + IP_ALEN
	RCALL	eth_write

	; Source MAC and IP from request -> destination MAC and IP in response
	LFSR	0, RX_ADDR(arp, src_mac)
	MOVLW	ETH_ALEN + IP_ALEN
	RCALL	eth_write

	; Start transmission
	;MOVLW	_mac_size + _arp_size
	BSF		LATB, 2, a
	BRA		eth_send

	
	; Every internet module must be able to forward a datagram of 68
	; octets without further fragmentation. This is because an internet
	; header may be up to 60 octets, and the minimum fragment is 8 octets.
	; Every internet destination must be able to receive a datagram of 576
	; octets either in one piece or in fragments to be reassembled.

process_ip:	; IP Datagram
	; Clear checksum
	CLRF	VAR16(checksum, L)
	CLRF	VAR16(checksum, H)

	; Read IP header
	MOVLW	_ip_size
	RCALL	eth_read

	; IP header checksum calculation
	LFSR	0, RX_PROTO(ip)
	ip_header_checksum

	; Check checksum
	COMF	VAR16(checksum, L)
	BNZ		done_frame
	COMF	VAR16(checksum, H)
	BNZ		done_frame

	; Subtract ethernet header and footer size from received length
	MOVLW	LOW(_mac_size + _mac_footer_size)
	SUBWF	RX_LE16(rx, len, L), f
	MOVLW	HIGH(_mac_size + _mac_footer_size)
	SUBWFB	RX_LE16(rx, len, H), f

	; Subtract IP datagram size
	MOVF	RX_BE16(ip, len, L), W
	SUBWF	RX_LE16(rx, len, L), f
	MOVF	RX_BE16(ip, len, H), W
	SUBWFB	RX_LE16(rx, len, H), f
	; Check if the whole IP datagram has been received
	BNC		done_frame

	; 4 bytes to check, 1 and mask, 11 instructions 
	; Check header version and size
	MOVLW	(IP_VERSION << 4) | (_ip_size / IP_SIZE_UNIT)
	XORWF	RX_BE8(ip, ver), W
	BNZ		done_frame

	; Check destination ip address
	LFSR	0, RX_ADDR(ip, dst)
	LFSR	1, ip_addr
	MOVLW	IP_ALEN
	; Skip if broadcast
	BTFSS	RX_BROADCAST
	RCALL	memcmp

ip_dst_checked:
	; Check flags - allow only don't fragment flag
	MOVLW	~HIGH(IP_FLAG_DF)
	ANDWF	RX_BE16(ip, flags, H), W
	BNZ		done_frame
	; Non zero fragment offset is not allowed
	MOVF	RX_BE16(ip, flags, L), W
	BNZ		done_frame

	; Check protocol
	MOVLW	IP_PROTO_UDP
	XORWF	RX_BE8(ip, proto), W
	BNZ		done_frame

	; IP payload length calculation
	MOVLW	_ip_size
	SUBWF	RX_BE16(ip, len, L), f
	CLRF	WREG, a
	SUBWFB	RX_BE16(ip, len, H), f

process_udp:
	; Read UDP header
	MOVLW	_udp_size
	RCALL	eth_read

	; Compare IP length with UDP length
	MOVF	RX_BE16(ip, len, L), W
	XORWF	RX_BE16(udp, len, L), W
	BNZ		done_frame
	MOVF	RX_BE16(ip, len, H), W
	XORWF	RX_BE16(udp, len, H), W
done_frame_bnz:
	BNZ		done_frame

	; Compute checksum
	; TODO: Move to function to save 1 instructions
	;CLRF	VAR16(checksum, H)	; Checksum registers is already equal to zero because IP checksum was correct
	MOVLW	IP_PROTO_UDP
	MOVWF	VAR16(checksum, L)	; Protocol

	; Add IP source and destination address + udp header
	LFSR	0, RX_ADDR(ip, src)
	MOVLW	(2 * IP_ALEN + _udp_size) / 2	; in words
	RCALL	ip_checksum

	; UDP payload length calculation
	MOVLW	_udp_size
	SUBWF	RX_BE16(udp, len, L), f
	CLRF	WREG, a
	SUBWFB	RX_BE16(udp, len, H), f

	; Save read pointer
	MOVFF	ERDPTH, VAR16_ADDR(ptr, H)
	MOVFF	ERDPTL, VAR16_ADDR(ptr, L)

	; Checksum UDP Payload
	MOVFF	RX_ADDR_BE16(udp, len, H), VAR16_ADDR(check_len, H)
	MOVFF	RX_ADDR_BE16(udp, len, L), VAR16_ADDR(check_len, L)
	RCALL	eth_checksum

	; Restore read pointer
	MOVFF	VAR16_ADDR(ptr, H), ERDPTH
	MOVFF	VAR16_ADDR(ptr, L), ERDPTL

	; Validate checksum - compare with UDP Length from pseudo header.
	; This length is equal to length in the header (already modified) and
	; the current IP Length value (IP Header length already subtracted)
	; call ip_checksum with checksum in FSR0 will requre 2 words more.
	COMF	RX_BE16(ip, len, H), W
	XORWF	VAR16(checksum, H), f		; XOR with checksum to clear checksum variable
	BNZ		done_frame_bnz
	COMF	RX_BE16(ip, len, L), W
	XORWF	VAR16(checksum, L), f
	BNZ		done_frame_bnz

	; Check destination port
	MOVLW	HIGH(UDP_PORT)
	XORWF	RX_BE16(udp, dst, H), W
	BNZ		done_frame_bnz
	MOVLW	LOW(UDP_PORT)
	XORWF	RX_BE16(udp, dst, L), W
	BNZ		done_frame_bnz


bootloader_processor:
	; Move eth write pointer to response start
	eth_write_pos	TX_PROTO(boot)

	; Wait for transmitter idle before modifying the buffer content
	tx_wait





udp_send:
	; Move source port to the destination port
	MOVFF	RX_ADDR_BE16(udp, src, H), RX_ADDR_BE16(udp, dst, H)
	MOVFF	RX_ADDR_BE16(udp, src, L), RX_ADDR_BE16(udp, dst, L)

	; Set source port
	MOVLW	HIGH(UDP_PORT)
	MOVWF	RX_BE16(udp, src, H)
	MOVLW	LOW(UDP_PORT)
	MOVWF	RX_BE16(udp, src, L)

	; Calculate datagram length with header
	; Store it also in checksum field. It will act as UDP Length field
	; of the pseudo header
	eth_get_tx_len_l
	MOVWF	RX_BE16(udp, len, L)
	MOVWF	RX_BE16(udp, cksum, L)
	MOVWF	RX_BE16(ip, len, L)
	MOVWF	VAR16(check_len, L)

	eth_get_tx_len_h
	MOVWF	RX_BE16(udp, len, H)
	MOVWF	RX_BE16(udp, cksum, H)
	MOVWF	RX_BE16(ip, len, H)
	MOVWF	VAR16(check_len, H)

	; Prepare pseudoheader checksum
	; Initialize checksum variable with protocol number
	; TODO: Move to function to save 1 instructions
	;CLRF	VAR16(checksum, H)	; Zero is already in this register because IP checksum was correct
	MOVLW	IP_PROTO_UDP
	MOVWF	VAR16(checksum, L)	; Protocol

	; Add ip source and destination address, UDP Header
	LFSR	0, RX_ADDR(ip, src)
	MOVLW	(2 * IP_ALEN + _udp_size) / 2	; in words
	RCALL	ip_checksum

	; Calculate payload length
	MOVLW	_udp_size
	SUBWF	VAR16(check_len, L), f
#if TX_BUFFER_SIZE == 256
	CLRF	VAR16(check_len, H)
#else
	MOVLW	0
	SUBWFB	VAR16(check_len, H), f
#endif

	; Set ethernet read pointer
	eth_read_pos	TX_PROTO(boot)

	; Checksum UDP payload
	RCALL	eth_checksum

	; Finalize udp checksum
	; If the computed checksum is zero, it is transmitted as all ones
	; An all zero transmitted checksum value means that the transmitter generated no checksum
	COMF	VAR16(checksum, H), f
	BNZ		upd_checksum_not_zeroH
	COMF	VAR16(checksum, L), f
	BNZ		upd_checksum_not_zeroL

	SETF	VAR16(checksum, H)
upd_checksum_not_zeroH:
	COMF	VAR16(checksum, L), f

upd_checksum_not_zeroL:
	; Set UDP checksum field
	MOVFF	VAR16_ADDR(checksum, H), RX_ADDR_BE16(udp, cksum, H)
	MOVFF	VAR16_ADDR(checksum, L), RX_ADDR_BE16(udp, cksum, L)

ip_send:
	; Calculate IP Total Length
	; UDP length is already stored in ip length field
	MOVLW	_ip_size
	ADDWF	RX_BE16(ip, len, L), f
	MOVLW	0
	ADDWFC	RX_BE16(ip, len, H), f

	; Set Time-to-live
	MOVLW	IP_DEF_TTL
	MOVWF	RX_BE8(ip, ttl)

	; Destination address
	LFSR	0,	RX_ADDR(ip, src)
	LFSR	1,	RX_ADDR(ip, dst)
	MOVLW	IP_ALEN
	RCALL	memcpy

	; Source address
	LFSR	0,	ip_addr
	LFSR	1,	RX_ADDR(ip, src)
	MOVLW	IP_ALEN
	RCALL	memcpy

	; Clear IP checksum field
	CLRF	RX_BE16(ip, chsum, H)
	CLRF	RX_BE16(ip, chsum, L)

	; Checksum
	CLRF	VAR16(checksum, H)
	CLRF	VAR16(checksum, L)

	LFSR	0,	RX_PROTO(ip)
	ip_header_checksum

	; Set IP checksum field
	COMF	VAR16(checksum, H), W
	MOVWF	RX_BE16(ip, chsum, H)
	COMF	VAR16(checksum, L), W
	MOVWF	RX_BE16(ip, chsum, L)
	
	; Save the ethernet write pointer - datagram end marker
	; TODO: Może w tym miejscu zaprogramować po prostu długość pakietu zamiast robić to w funkcji send?
	eth_save_write_ptr

	; Move eth write pointer to EtherType of ETH header
	eth_write_pos_ex	TX_ADDR(mac, type)

	; Write EtherType, IP and UDP header to the ethernet buffer
	; Source and destination MAC will be written by eth_write
	LFSR	0, RX_ADDR(mac, type)
	MOVLW	2 + _ip_size + _udp_size
	RCALL	eth_write

	; Restore the ethernet write pointer
	eth_restore_write_ptr
	
	BSF		LATB, 3, a
;gdb:
;	BRA gdb
	;BCF		LATB, 3, a
	; Send data!
	BRA		eth_send
	
END start; Bootloader entry point