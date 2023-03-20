; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>

GLOBAL bootloader_processor
GLOBAL bootloader_reply_code
GLOBAL udp_send

#if 0
GLOBAL reply_inprogress
GLOBAL reply_wrong_packet_size
GLOBAL reply_illegal_address
GLOBAL reply_invalid_param
GLOBAL reply_invalid_operation
GLOBAL reply_invalid_sender
GLOBAL reply_success
GLOBAL reply_code

;-------------------------------------------------------------------------------
; Configure network addresses
; 8/18 instructions
;-------------------------------------------------------------------------------
GLOBAL bootloader_net_config

;-------------------------------------------------------------------------------
; Discover targed in network
; 17/25 instructions
;-------------------------------------------------------------------------------
GLOBAL bootloader_discover

;-------------------------------------------------------------------------------
; Read devices flash memory
; 15/17 instructions
;-------------------------------------------------------------------------------
GLOBAL bootloader_read

;-------------------------------------------------------------------------------
; Erase and write flash memory row
; 17 instructions
;-------------------------------------------------------------------------------
GLOBAL bootloader_erase_write

;-------------------------------------------------------------------------------
; Write flash memory
; 55 instructions
;-------------------------------------------------------------------------------
GLOBAL bootloader_write

;-------------------------------------------------------------------------------
; Erashe flash row
; 4 instructions
;-------------------------------------------------------------------------------
GLOBAL bootloader_erase

;-------------------------------------------------------------------------------
; Erase whole chip without bootloader and config words
; Config words protection requires bootloader placed in last (two) row(s) of flash
; 16 instructions
;-------------------------------------------------------------------------------
GLOBAL bootloader_chip_erase
#endif

#define UPPER(x) (((x) >> 16) & 0xff)
