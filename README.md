# PlayStation on FPGA
implemented PlayStation on an FPGA.  

<!--
When executing with the Terasic DE2-115 FPGA board, write the BIOS of SCPH-5500 to address 0 of the flash memory.
Reset is BUTTON 0.  
<pre>
 SW17 SW16:
  0    0     SONY logo -> PS logo.
  0    1     My polygon demo.
  1    0     SONY logo -> "Not a PlayStation standard disc"
  1    1     SONY logo -> Main menu view.
</pre>
-->

<a target=_blank href="https://pgate1.at-ninja.jp/PSX_on_FPGA/">PlayStation Sound Player on FPGA</a>  
<a target=_blank href="https://www.youtube.com/watch?v=2PupKQtSOCA">PlayStation on FPGA feat. DE2-115 (Kernel run and the Texture)</a>  
<a target=_blank href="https://www.youtube.com/watch?v=xV6hRjSPIlo">PlayStation on FPGA feat. Pocket</a>
  
<!--
2019/11/12  
Run BIOS.  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/20191112_sony.jpg">

2020/07/09  
Add texture and dither.  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/20200717_VGA_ok.jpg">

2020/09/05  
Add CDROM controller.  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/20200905_NotPlayStationDisc.jpg">

2021/02/25  
Add geometry engine for viewing PS logo.  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/PS_20210225_ok.jpg">
  
Tobal No.1 play  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/v_TobalNo1.jpg">
  
Einhander play  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/v_Einhander.jpg">
  
Metalgear Solid demo  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/v_MetalgearSolid.jpg">
  
2022/03/27  
Add MemoryCard Controller for Saga Frontier 2.  
<img width=600 src="https://pgate1.at-ninja.jp/PSX_on_FPGA/github_img/v_SagaFrontier2.jpg">
-->

## Screenshots

<img width=200 src="img/20230129_Einhander.jpg"><img width=200 src="img/20230318_VagrantStory.jpg">
<img width=200 src="img/20230201_MetalGearSolid.jpg"><img width=200 src="img/20230318_XI.jpg">
<img width=200 src="img/20230129_Dewprism.jpg"><img width=200 src="img/20230203_RayStorm.jpg">

## Working game list

Here's a list of games that work a little. There may be other games that work as well.

- Einhander
- Ridge Racer
- Tobal No.1
- Ace Combat 2
- XI
- Vagrant Story
- Love & Destroy
- iS internal section
- Saga Frontier 2
- Dewprism
- Metal Gear Solid Integral VR disc
- Ray Storm

