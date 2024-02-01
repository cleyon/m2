AWK=/usr/bin/awk
GAWK=/usr/local/bin/gawk
MAWK=/usr/local/bin/mawk
NAWK=/usr/bin/nawk

all:
	@echo "Possible targets are 'lint', 'tags', maybe more"

gm2: m2
	sed '1s,$(AWK),$(GAWK),' m2 > $@
	chmod +x $@

mm2: m2
	sed '1s,$(AWK),$(MAWK),' m2 > $@
	chmod +x $@

nm2: m2
	sed '1s,$(AWK),$(NAWK),' m2 > $@
	chmod +x $@

lint:
	$(GAWK) --lint -f m2 /dev/null

tags:
	ctags m2
