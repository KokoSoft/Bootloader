::"c:\Program Files\Microchip\xc8\v2.40\pic-as\bin\pic-as.exe" -mcpu=PIC18F67J60 functions.S
cd out
"c:\Program Files\Microchip\xc8\v2.40\pic-as\bin\pic-as.exe" -mcpu=PIC18F67J60 -Wl,-Map=bootloader.map,-ABOOT=1FC00h-1FFF7h,-AETH=0h-1FFFh,-Pmem_init=BOOT ../functions.S ../boot.S ../meminit.s ../bootloader.S -msummary=+mem,+psect,+class,-hex,-file

