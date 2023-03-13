::"c:\Program Files\Microchip\xc8\v2.40\pic-as\bin\pic-as.exe" -mcpu=PIC18F67J60 functions.S
cd out
"c:\Program Files\Microchip\xc8\v2.40\pic-as\bin\pic-as.exe" -mcpu=PIC18F67J60 -Wl,-Map=bootloader.map,-ABOOT=1FC00h-1FFF7h,-AETH=0h-1FFFh,-Pmem_init=BOOT ../functions.S ../boot.S ../meminit.s ../chip_config.asm ../bootloader.S -msummary=+mem,+psect,+class,-hex,-file

:: -L-ver=XC8^PIC(R)^Assembler###V2.40
:: -D__PICAS -D__PICAS_VERSION=2400
:: -D__18F67J60 -D__18F67J60__ -D_18F67J60 
:: -D__EXTMEM=1966080 -D_ROMSIZE=131064 -D_RAMSIZE=3808 
:: -D_EEPROMSIZE=0
:: -D_FLASH_ERASE_SIZE=1024 
:: -D_FLASH_WRITE_SIZE=64 -D_COMMON_=1 -D_COMMON_ADDR_=0 -D_COMMON_SIZE_=96 -D_ERRATA_TYPES=0 -D_18F97J60_FAMILY_ -D__J_PART 
:: -D__TRADITIONAL18__=1 -D_PIC18
