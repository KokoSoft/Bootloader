; SPDX-License-Identifier: BSD-3-Clause
;
; Copyright(c) 2023 Koko Software. All rights reserved.
;
; Author: Adrian Warecki <embedded@kokosoftware.pl>

GLOBAL mem_init
GLOBAL reg_init
GLOBAL eth_read
GLOBAL eth_write
GLOBAL eth_send
GLOBAL done_frame
GLOBAL memcmp
GLOBAL done_frame_pop
GLOBAL memcpy

_BRA MACRO address
	;;IF ((address - $ - 2) > 1023)
	;;	ERROR	"BRA address too big!"
	;;ENDIF
	;;IF (address - $ - 2) < -1024
	;;	ERROR	"BRA address too small!"
	;;ENDIF
	DW	1101000000000000B | (((address - $ - 2) shr 1) and 0x7ff)
ENDM

_BNZ MACRO address
	;;IF ((address - $ - 2) > 255)
	;;	ERROR	"BRA address too big!"
	;;ENDIF
	;;IF (address - $ - 2) < -256
	;;	ERROR	"BRA address too small!"
	;;ENDIF
	DW	1110000100000000B | (((address - $ - 2) shr 1) and 0xff)
ENDM

_RCALL MACRO address
	;;IF ((address - $ - 2) > 1023)
	;;	ERROR	"RCALL address too big!"
	;;ENDIF
	;;IF (address - $ - 2) < -1024
	;;	ERROR	"RCALL address too small!"
	;;ENDIF
	DW	1101100000000000B | (((address - $ - 2) shr 1) and 0x7ff)
ENDM