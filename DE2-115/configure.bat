@echo off

set PATH=%QUARTUS_ROOTDIR%\bin64;%QUARTUS_ROOTDIR%\bin32;%QUARTUS_ROOTDIR%\bin;%PATH%

quartus_pgm.exe -c "USB-Blaster" -m JTAG -o p;output_files\PlayStation.sof

echo Press any key to finish.
pause > nul
