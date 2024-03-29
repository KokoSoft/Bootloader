; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>

#include "config.inc"

;-------------------------------------------------------------------------------
; Receive Status Vector (little endian fields)
;-------------------------------------------------------------------------------
; Next Packet Pointer
_rx_next		EQU	0x000
; Indicates length of the received frame. This includes the destination
; address, source address, type/length, data, padding and CRC fields. This
; field is stored in little-endian format.
_rx_len			EQU	0x002	; status[15:0]		15-0 Received Byte Count
_rx_status		EQU	0x004	; status[31:16]		23 Received OK, 25 Receive Broadcast Packet
_rx_size		EQU	0x006

#define RX_BROADCAST	RX_BIT_LE(rx, status, 9)
;-------------------------------------------------------------------------------
; Transmit Status Vector (little endian fields)
;-------------------------------------------------------------------------------
_tx_len		EQU	0x000	; status[15:0]		15-0 Transmit Byte Count
_tx_status0		EQU	0x002	; status[23:16]
_tx_status1		EQU	0x003	; status[31:24]
_tx_status2		EQU	0x004	; status[39:32]
_tx_status3		EQU	0x005	; status[47:40]
_tx_status4		EQU	0x006	; status[55:48]
_tx_size		EQU	0x007

;-------------------------------------------------------------------------------
; MAC Header
;-------------------------------------------------------------------------------
_mac_dst			EQU	0x000	; MAC_Address	destination
_mac_src			EQU	0x006	; MAC_Address	source
_mac_type			EQU	0x00C	; EtherType		etherType
_mac_size			EQU	0x00E
_mac_footer_size	EQU	0x004

ETH_ALEN			EQU 6		; Octets in one ethernet address
ETH_TYPE_ARP		EQU 0x0806	; Address Resolution packet
ETH_TYPE_IP			EQU 0x0800	; Internet Protocol packet

;-------------------------------------------------------------------------------
; IP Header
;-------------------------------------------------------------------------------
_ip_ver			EQU 0x000	; uint8_t		Version_HeaderLength
_ip_tos			EQU 0x001	; uint8_t		TypeOfService
_ip_len			EQU 0x002	; be16_t		TotalLength
_ip_id			EQU 0x004	; be16_t		Identification
_ip_flags		EQU 0x006	; be16_t		Flags_Offset
_ip_ttl			EQU 0x008	; uint8_t		TimeToLive
_ip_proto		EQU 0x009	; uint8_t		Protocol
_ip_chsum		EQU 0x00A	; be16_t		HeaderChecksum
_ip_src			EQU 0x00C	; IP_Address	SourceAddress
_ip_dst			EQU 0x010	; IP_Address	DestinationAddress
_ip_size		EQU 0x014

;  0                   1                   2                   3
;  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; |Version|  IHL  |Type of Service|          Total Length         |
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; |         Identification        |Flags|      Fragment Offset    |
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; |  Time to Live |    Protocol   |         Header Checksum       |
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; |                       Source Address                          |
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; |                    Destination Address                        |
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; |                    Options                    |    Padding    |
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

IP_ALEN			EQU 4			; Address length
IP_DEF_TTL		EQU 64			; Default Time to Live
IP_VERSION		EQU 4
IP_SIZE_UNIT	EQU 4

IP_FLAG_DF		EQU 0x4000		; Don't fragment
IP_FLAG_MF		EQU 0x2000		; More fragments
IP_FRAG_OFF		EQU 0x1FFF		; Fragment offset

IP_PROTO_UDP	EQU 17			; User Datagram Protocol

;-------------------------------------------------------------------------------
; UDP Packet
;-------------------------------------------------------------------------------
_udp_src		EQU 0x000	; be16_t		Source port 
_udp_dst		EQU 0x002	; be16_t		Destination port
_udp_len		EQU 0x004	; be16_t		Length
_udp_cksum		EQU 0x006	; be16_t		Checksum 
_udp_size		EQU 0x008

; User Datagram Header Format:
; 0       7 8     15 16    23 24    31
; +--------+--------+--------+--------+
; |     Source      |   Destination   |
; |      Port       |      Port       |
; +--------+--------+--------+--------+
; |      Length     |     Checksum    |
; +--------+--------+--------+--------+
; | data octets ...
; +---------------- ...

; Pseudo header for checksum:
;  0      7 8     15 16    23 24    31
; +--------+--------+--------+--------+
; |           source address          |
; +--------+--------+--------+--------+
; |        destination address        |
; +--------+--------+--------+--------+
; |  zero  |protocol|    UDP length   |
; +--------+--------+--------+--------+

;-------------------------------------------------------------------------------
; ARP
;-------------------------------------------------------------------------------
_arp_hw_type	EQU 0x000	; be16_t		hardwareAddressType
_arp_prot_type	EQU 0x002	; be16_t		protocolAddressType
_arp_hw_len		EQU 0x004	; uint8_t		hardwareAddressLength  // in bytes
_arp_prot_len	EQU 0x005	; uint8_t		protocolAddressLength  // in bytes
_arp_op			EQU 0x006	; be16_t		opCode
_arp_src_mac	EQU 0x008	; MAC_Address	senderHardwareAddress
_arp_src_ip		EQU 0x00E	; IP_Address	senderProtocolAddress
_arp_dst_mac	EQU 0x012	; MAC_Address	targetHardwareAddress
_arp_dst_ip		EQU 0x018	; IP_Address	targetProtocolAddress
_arp_size		EQU 0x01C

; ARP protocol HARDWARE identifiers.
ARPHRD_ETHER	EQU 0x0001	; Ethernet 10Mbps

; ARP protocol opcodes.
ARP_OP_REQUEST	EQU 0x0001	; ARP request
ARP_OP_REPLY	EQU 0x0002	; ARP reply

;-------------------------------------------------------------------------------
; Bootloader protocol
;-------------------------------------------------------------------------------

PROTOCOL_VERSION	EQU 1

OP_DISCOVER			EQU 0		; Reply: DiscoverReply, STATUS_OK
OP_NET_CONFIG		EQU 1		; Reply: DiscoverReply, STATUS_OK
OP_READ				EQU 2		; Reply: ReadReply with STATUS_INPROGRESS, STATUS_OK
OP_WRITE			EQU 3		; Reply: Header with STATUS_INPROGRESS, STATUS_OK
OP_ERASE			EQU 4		; Reply: Header with STATUS_INPROGRESS, STATUS_OK
OP_RESET			EQU 5		; Reply: Header with STATUS_OK
OP_ERASE_WRITE		EQU 6		; Reply: Header with STATUS_INPROGRESS, STATUS_OK
OP_CHIP_ERASE		EQU 7		; Reply: Header with STATUS_INPROGRESS, STATUS_OK
OP_CHECKSUM			EQU 8		; Reply: ChecksumReply, STATUS_OK
OP_MAX				EQU OP_CHIP_ERASE

STATUS_REQUEST			EQU	0	; It is a request to a device
STATUS_OK				EQU	1		
STATUS_INPROGRESS		EQU	2	; Read, Write, Erase, Checksum in progress
STATUS_INV_SRC			EQU	3	; Sender aren't permitted to perform this operation - discover first
STATUS_INV_OP			EQU	4	; Unknown / unsupported operation
STATUS_INV_PARAM		EQU	5	; Invalid operation parameters
STATUS_INV_LENGTH		EQU 6	; Invalid operation length.
STATUS_INV_ADDR			EQU	7	; Invalid operation address
STATUS_PROTECTED_ADDR	EQU 8	; Forbidden operation address.
STATUS_PKT_SIZE			EQU	9	; Invalid packet size

; Request header
_boot_version		EQU 0x00	; be8_t			version;
_boot_seq			EQU 0x01	; be8_t			seq;
_boot_operation		EQU 0x02	; be8_t			operation;
_boot_status		EQU 0x03	; be8_t			status;
_boot_address		EQU 0x04	; be32_t		address;
_boot_length		EQU 0x08	; be16_t		length;
_boot_size			EQU 0x0A

; Reply header
_boot_replay_size			EQU 0x04
_boot_replay_payload		EQU 0x04

; DiscoverReply
_disc_rpl_version	EQU 0x00	; be16_t	version;
_disc_rpl_boot_addr	EQU 0x02	; be32_t	bootloader_address;
_disc_rpl_dev_id	EQU 0x06	; be16_t	device_id;
_disc_rpl_size		EQU 0x08

; NetworkConfig
_netcfg_mac			EQU 0x00	; uint8_t	mac_address[6];
_netcfg_ip			EQU 0x06	; uint32_t	ip_address;
#if NET_CONFIG_MAC_EXTENDED
_netcfg_mac_ext		EQU 0x0A	; uint8_t	mac_address[6];
_netcfg_size		EQU 0x10
#else
_netcfg_size		EQU 0x0A
#endif


; ChecksumReply
_cksum_rpl_sum		EQU 0x00	; be32_t	checksum;
_cksum_rpl_size		EQU 0x04
