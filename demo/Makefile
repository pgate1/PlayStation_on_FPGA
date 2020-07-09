.SUFFIXES: .sflp .sfl .h .v

SFLP = demo_core.sflp sin_table.sflp cos_table.sflp
SFLS = $(SFLP:.sflp=.sfl)
HEAD = $(SFLP:.sflp=.h)
VLOG = $(SFLS:.sfl=.v)

MAKEFLAGS += --no-print-directory

sfl2vl:
	make sfl
	make vl
	verilator --lint-only demo.v
	# ok

sfl: $(SFLS)

vl: $(VLOG)

.sflp.sfl:
	sflp $< $@

.sfl.v:
	sfl2vl $< -O2

clean:
	rm -f $(SFLP:.sflp=.sfl) $(SFLP:.sflp=.h) $(SFLS:.sfl=.v)

