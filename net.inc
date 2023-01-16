; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>

;-------------------------------------------------------------------------------
; Receive Status Vector
;-------------------------------------------------------------------------------
$rx_nextL		EQU	0x000
$rx_nextH		EQU	0x001
$rx_lenL		EQU	0x002	; status[7:0]		15-0 Received Byte Count
$rx_lenH		EQU	0x003	; status[15:8]		15-0 Received Byte Count
$rx_statusL		EQU	0x004	; status[23:16]		23 Received OK
$rx_statusH		EQU	0x005	; status[31:24]		25 Receive Broadcast Packet
$rx_size		EQU	0x006

;-------------------------------------------------------------------------------
; Transmit Status Vector
;-------------------------------------------------------------------------------
$tx_lenL		EQU	0x000	; status[7:0]		15-0 Transmit Byte Count
$tx_lenH		EQU	0x001	; status[15:8]		15-0 Transmit Byte Count
$tx_status0		EQU	0x002	; status[23:16]
$tx_status1		EQU	0x003	; status[31:24]
$tx_status2		EQU	0x004	; status[39:32]
$tx_status3		EQU	0x005	; status[47:40]
$tx_status4		EQU	0x006	; status[55:48]
$tx_size		EQU	0x007

;-------------------------------------------------------------------------------
; MAC Header
;-------------------------------------------------------------------------------
$mac_dst		EQU	0x000	; MAC_Address	destination
$mac_src		EQU	0x006	; MAC_Address	source
$mac_type		EQU	0x00C	; EtherType		etherType
$mac_size		EQU	0x00E

;-------------------------------------------------------------------------------
; IP Header
;-------------------------------------------------------------------------------
$ip_ver			EQU 0x000	; uint8_t		Version_HeaderLength
$ip_tos			EQU 0x001	; uint8_t		TypeOfService
$ip_len			EQU 0x002	; be16_t		TotalLength
$ip_id			EQU 0x004	; be16_t		Identification
$ip_flags		EQU 0x006	; be16_t		Flags_Offset
$ip_ttl			EQU 0x008	; uint8_t		TimeToLive
$ip_proto		EQU 0x009	; uint8_t		Protocol
$ip_chsum		EQU 0x00A	; be16_t		HeaderChecksum
$ip_src			EQU 0x00C	; IP_Address	SourceAddress
$ip_dst			EQU 0x010	; IP_Address	DestinationAddress
$ip_size		EQU 0x014

;-------------------------------------------------------------------------------
; UDP Packet
;-------------------------------------------------------------------------------
$udp_src		EQU 0x000	; be16_t		Source port 
$udp_dst		EQU 0x002	; be16_t		Destination port
$udp_len		EQU 0x004	; be16_t		Length
$udp_cksum		EQU 0x006	; be16_t		Checksum 
$udp_size		EQU 0x008

;-------------------------------------------------------------------------------
; ARP
;-------------------------------------------------------------------------------
$arp_hw_type	EQU 0x000	; be16_t		hardwareAddressType
$arp_prot_type	EQU 0x002	; be16_t		protocolAddressType
$arp_hw_len		EQU 0x004	; uint8_t		hardwareAddressLength  // in bytes
$arp_prot_len	EQU 0x005	; uint8_t		protocolAddressLength  // in bytes
$arp_op			EQU 0x006	; be16_t		opCode
$arp_src_mac	EQU 0x008	; MAC_Address	senderHardwareAddress
$arp_src_ip		EQU 0x00E	; IP_Address	senderProtocolAddress
$arp_dst_mac	EQU 0x012	; MAC_Address	targetHardwareAddress
$arp_dst_ip		EQU 0x018	; IP_Address	targetProtocolAddress
$arp_size		EQU 0x01C

;-------------------------------------------------------------------------------
; Constants
;-------------------------------------------------------------------------------
ETH_TYPE_ARP	EQU 0x0806	; Address Resolution packet
ETH_TYPE_IP		EQU 0x0800	; Internet Protocol packet
IP_PROTO_UDP	EQU 17		; User Datagram Protocol

; ARP protocol HARDWARE identifiers.
ARPHRD_ETHER	EQU 1		; Ethernet 10Mbps

; ARP protocol opcodes.
ARP_OP_REQUEST	EQU 1		; ARP request
ARP_OP_REPLY	EQU 2		; ARP reply
ETH_ALEN		EQU 6		; Octets in one ethernet address
