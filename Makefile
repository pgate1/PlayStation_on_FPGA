.SUFFIXES: .sflp .sfl .h .v

SFLP = PSX_core.sflp R3000A.sflp div_u32.sflp bsr_s32.sflp Cache_IR.sflp rootcounter.sflp DDS_50to33868800.sflp DMA_SPU.sflp SPU_core.sflp dsp_core.sflp dsp_ch.sflp bsr_s16.sflp bsr_s24.sflp ADSR.sflp reverb.sflp ram_16x32k.sflp dsdac10.sflp core.sflp GPU_core.sflp DMA_OTC.sflp DMA_GPU.sflp VGA_ctrl.sflp ram_320x240x15.sflp inv_table.sflp drawGouraudShading.sflp drawRect.sflp view_ram_ctrl.sflp CDR_core.sflp SIO_core.sflp drawTextureRect.sflp gamma_correction.sflp
SFLS = $(SFLP:.sflp=.sfl)
HEAD = $(SFLP:.sflp=.h)
VLOG = $(SFLS:.sfl=.v)

MAKEFLAGS += --no-print-directory

sfl2vl:
	make sfl
	make vl
#	verilator --cc dsp_ch.v --compiler msvc --public
#	verilator --cc GPU_core.v --compiler msvc --public --l2-name v
#	verilator --cc drawGouraudShading.v --compiler msvc --public --l2-name v
#	verilator --cc CDR_core.v --compiler msvc --public --l2-name v
#	verilator --cc SIO_core.v --compiler msvc --public --l2-name v
#	verilator --cc drawTextureRect.v --compiler msvc --public --l2-name v
	verilator --lint-only PSX_core.v -y demo
	# ok

sfl: $(SFLS)

vl: $(VLOG)

.sflp.sfl:
	sflp $< $@

.sfl.v:
	sfl2vl $< -O2

clean:
	rm -f $(SFLP:.sflp=.sfl) $(SFLP:.sflp=.h) $(SFLS:.sfl=.v)

