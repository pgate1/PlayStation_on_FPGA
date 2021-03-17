# PlayStation(PSX) on FPGA
implemented PlayStation on an FPGA.  

When executing with the Terasic DE2-115 FPGA board, write the BIOS of SCPH-5500 to address 0 of the flash memory.
Reset is BUTTON 0.  
<pre>
 SW17 SW16:
  0    0     SONY logo -> PS logo.
  0    1     My polygon demo.
  1    0     SONY logo -> "Not a PlayStation standard disc"
  1    1     SONY logo -> Main menu view.
</pre>

<a target=_blank href="https://pgate1.at-ninja.jp/PSX_on_FPGA/">PlayStation Sound Player on FPGA</a>  
<a target=_blank href="https://www.youtube.com/watch?v=2PupKQtSOCA">PlayStation(PSX) on FPGA (Kernel run and the Texture)</a>
  
2019/11/12  
Run BIOS.  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/20191112_sony.jpg">

2020/07/09  
Add texture and dither.   
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/20200717_VGA_ok.jpg">

2020/09/05  
Add a CDROM controller.  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/20200905_NotPlayStationDisc.jpg">

2021/02/25  
Add geometry engine for viewing PS logo.  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/PS_20210225_ok.jpg">
