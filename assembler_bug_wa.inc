;-------------------------------------------------------------------------------
; Workaround for Microchip buggy assembler! This piece of shit produce invalid
; jumps between files and does not check relative jump range!
;-------------------------------------------------------------------------------
#define OPCODE_NOP					0000000000000000B
#define OPCODE_NOP2					1111000000000000B
#define OPCODE_BC					1110001000000000B
#define OPCODE_BN					1110011000000000B
#define OPCODE_BNC					1110001100000000B
#define OPCODE_BNN					1110011100000000B
#define OPCODE_BNOV					1110010100000000B
#define OPCODE_BNZ					1110000100000000B
#define OPCODE_BOV					1110010000000000B
#define OPCODE_BRA					1101000000000000B
#define OPCODE_BZ					1110000000000000B
#define OPCODE_RCALL				1101100000000000B
#define OPCODE_SLEEP				0000000000000011B
;#define OPCODE_HALT					0x0001
#define OPCODE_TRAP					0x00E0

#define CONDITIONAL_BRANCH_SIZE		8
#define UNCONDITIONAL_BRANCH_SIZE	11
#define BIT_MASK(len)				((1 << (len)) - 1)

#define REL_DIFF(address, len)		((((address) - $ - 2) >> 1) and BIT_MASK(len))
#define REL_DIFF_SIMPLE(address)	((address) - $ - 2)

#define ADDR_SHIFT(x, bit)			(REL_DIFF_SIMPLE((x)) >> (bit))
#define ADDR_ERROR(addr, len)		((ADDR_SHIFT(addr, len) ^ ADDR_SHIFT(addr, len + 1)) and 0x01)

; Clears value on error
#define NULLIFY(opcode, error)		(opcode) * (1 - (error))

; Produce sleep instruction on error
#define SLEEPIFY(error)				(OPCODE_SLEEP * (error))

; Produce forever loop on error
#define LOOPIFY(error)				((OPCODE_BRA | BIT_MASK(UNCONDITIONAL_BRANCH_SIZE)) * (error))

; Generate opcode with error checking
#define OPCODE(code, addr, len)		NULLIFY(code | REL_DIFF(addr, len), ADDR_ERROR(addr, len)) | SLEEPIFY(ADDR_ERROR(addr, len))

; produce NOP if not error
#define NOPIFY(opcode, error)		(opcode | (OPCODE_NOP2 * (error)))

#define BC		_BC
_BC MACRO address
	DW OPCODE(OPCODE_BC, address, CONDITIONAL_BRANCH_SIZE)
ENDM

#define BN		_BN
_BN MACRO address
	DW OPCODE(OPCODE_BN, address, CONDITIONAL_BRANCH_SIZE)
ENDM

#define BNC		_BNC
_BNC MACRO address
	DW OPCODE(OPCODE_BNC, address, CONDITIONAL_BRANCH_SIZE)
ENDM

#define BNN		_BNN
_BNN MACRO address
	DW OPCODE(OPCODE_BNN, address, CONDITIONAL_BRANCH_SIZE)
ENDM

#define BNOV	_BNOV	
_BNOV	 MACRO address
	DW OPCODE(OPCODE_BNOV, address, CONDITIONAL_BRANCH_SIZE)
ENDM

#define BOV		_BOV
_BOV MACRO address
	DW OPCODE(OPCODE_BOV, address, CONDITIONAL_BRANCH_SIZE)
ENDM

#define BZ		_BZ
_BZ MACRO address
	DW OPCODE(OPCODE_BZ, address, CONDITIONAL_BRANCH_SIZE)
ENDM

#define BRA		_BRA
_BRA MACRO address
	DW OPCODE(OPCODE_BRA, address, UNCONDITIONAL_BRANCH_SIZE)
ENDM

#define BNZ		_BNZ
_BNZ MACRO address
	DW OPCODE(OPCODE_BNZ, address, CONDITIONAL_BRANCH_SIZE)
ENDM

#define RCALL	_RCALL
_RCALL MACRO address
	DW OPCODE(OPCODE_RCALL, address, UNCONDITIONAL_BRANCH_SIZE)
ENDM
