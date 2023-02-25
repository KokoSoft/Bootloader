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
