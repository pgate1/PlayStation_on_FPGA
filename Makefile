.SUFFIXES: .sflp .sfl .h .v

SFLP = PlayStation_core.sflp R3000A.sflp div_u32.sflp bsr_s32.sflp Cache_IR.sflp Timer.sflp \
DDS_50to33868800.sflp DMA_SPU.sflp SoundProcessingUnit.sflp DigitalSignalProcessor.sflp dsp_ch.sflp bsr_s16.sflp \
bsr_s24.sflp ADSR.sflp reverb.sflp ram_16x32k.sflp dsdac10.sflp GraphicProcessingUnit.sflp \
DMA_OTC.sflp DMA_GPU.sflp VGA_ctrl.sflp ram_320x240x15_dp.sflp inv_table.sflp drawPoly.sflp \
drawFillRect.sflp view_ram_ctrl.sflp view_ram_ctrl_one.sflp CDROM_controller.sflp PAD_controller.sflp PAD.sflp drawRect.sflp \
gamma_correction.sflp ram_8x4k.sflp DMA_CDR.sflp \
GeometryTransformationEngine.sflp gte_DIVIDE.sflp gte_LIMIT.sflp Scratchpad.sflp \
pseudo_cdrom_data.sflp drawpoly_cache.sflp MDEC.sflp

SFLS = $(SFLP:.sflp=.sfl)
HEAD = $(SFLP:.sflp=.h)
VLOG = $(SFLS:.sfl=.v)

MAKEFLAGS += --no-print-directory

sfl2vl:
	make sfl
	make vl
#	verilator --cc dsp_ch.v --compiler msvc --public
#	verilator --cc GraphicProcessingUnit.v --compiler msvc --public --l2-name v
#	verilator --cc drawPoly.v --compiler msvc --public --l2-name v
#	verilator --cc CDROM_controller.v --compiler msvc --public --l2-name v
#	verilator --cc PAD_controller.v --compiler msvc --public --l2-name v
#	verilator --cc drawTextureRect.v --compiler msvc --public --l2-name v
#	verilator --cc GeometryTransformationEngine.v --compiler msvc --public --l2-name v
#	verilator --cc gte_DIVIDE.v --compiler msvc --public --l2-name v
#	verilator --cc R3000A.v --compiler msvc --public --l2-name v
#	verilator --cc GeometryTransformationEngine.v --Mdir obj_dir_gcc --exe gte_sim.cpp --public --l2-name v
#	cd obj_dir_gcc; make -j -f VGeometryTransformationEngine.mk; ./VGeometryTransformationEngine.exe; cd ../
#	verilator --cc PlayStation_core.v --compiler msvc --public --l2-name v
#	verilator --cc CDROM_controller.v --compiler msvc --public --l2-name v
#	verilator --cc PAD_controller.v --compiler msvc --public --l2-name v

	verilator --lint-only PlayStation_core.v -y demo
#	verilator --lint-only core.v -y demo -y ../../hdl -y ../../DE2-115
#	verilator --cc core_sim.v --compiler msvc --public --l2-name v
	# ok

sfl: $(SFLS)

vl: $(VLOG)

.sflp.sfl:
	sflp $<

.sfl.v:
	sfl2vl $< -O2

clean:
	rm -f $(SFLP:.sflp=.sfl) $(SFLP:.sflp=.h) $(SFLS:.sfl=.v)

