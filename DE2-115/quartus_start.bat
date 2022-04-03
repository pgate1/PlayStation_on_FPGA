attrib -R /S /D .

@rem start C:\altera\13.1\quartus\bin64\quartus.exe PlayStation.qpf

set QUARTUS_ROOTDIR=C:\altera\13.1\quartus
%QUARTUS_ROOTDIR%\bin64\quartus_sh.exe --flow compile PlayStation.qpf

@echo;
@powershell -c "(Get-Content output_files\PlayStation.sta.rpt | Select-Object -first 165 | Select-Object -last 4).subString(0, 38)"

@powershell -c (New-Object -com SAPI.SpVoice).Speak('ƒRƒ“ƒpƒCƒ‹Š®—¹‚Å‚·') > nul
@rem echo 

pause

configure.bat
