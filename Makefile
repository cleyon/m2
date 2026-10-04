.PHONY:	all man manview callgraph callgraph-full callgraph-sane callgraph-io clean distclean lint tags \
	bat funcs vars \
	debug check test \
	check-quiet   test-quiet   quiet-check   quiet-test \
	check-verbose test-verbose verbose-check verbose-test \
	testlog testlog-verbose testlog-quiet

GOOD_M2=/Users/cleyon/bin-n.yuuko/m2
AWK=/usr/bin/awk
GAWK=/usr/local/bin/gawk
MAWK=/usr/local/bin/mawk
NAWK=/usr/bin/nawk
CALLGRAPH=~/repos.cp/github.com/koknat/callGraph/callGraph
TAGS=ctags -e

all:
	@echo "Say what now?"

man: m2.cat1

manview: m2.cat1
	less m2.cat1

callgraph-full:
	$(CALLGRAPH) m2 -language awk

callgraph callgraph-sane:
	grex -g --file cg.ignore | sed 's/^.\(.*\).$$/\1/' > ignore.funcs
	$(CALLGRAPH) m2 -language awk -ignore "`cat ignore.funcs`"

debug:
	$(GAWK) -D -f m2

m2.cat1: m2.1
	tbl $^ | nroff -mdoc > $@

m2.ps: m2.1
	tbl $^ | groff -Tps -mdoc > $@

m2.pdf: m2.ps
	pstopdf $^ -o $@

gm2: m2
	sed '1s,$(AWK),$(GAWK),' m2 > $@
	chmod +x $@

mm2: m2
	sed '1s,$(AWK),$(MAWK),' m2 > $@
	chmod +x $@

nm2: m2
	sed '1s,$(AWK),$(NAWK),' m2 > $@
	chmod +x $@

funcs awkfuncs.out: m2
	@rm -f awkfuncs.out
	grep '^function' m2 | sed 's/(.*//' | awk '{print $$2}' | sort >awkfuncs.out

vars awkvars.out: m2
	@rm -f awkvars.out
	$(GAWK) -d -f m2 /dev/null >/dev/null

bat:
	bat -S  --language awk --theme ansi m2

clean:
	rm -f  m2.cat1  test.log.*  tests/*/*/*.actual_*  tests/*/*/*.expected_*

distclean: clean
	rm -f *~ awkvars.out awkfuncs.out

lint:
	@$(GAWK) --source 'BEGIN{exit} END{exit}' -f m2 --lint --posix /dev/null

tags:
	$(TAGS) m2

check-verbose test-verbose verbose-check verbose-test:
	@date
	@/usr/bin/time ./check.sh
	@date

check test check-quiet test-quiet quiet-check quiet-test:
	@/usr/bin/time ./check.sh </dev/null 2>&1 | grep -v 'PASSED \*\*\*$$'
	@date

testlog-verbose:
	@date
	@timeout 90 /usr/bin/time nice ./check.sh </dev/null >test.log.`ts` 2>&1
	@date

testlog testlog-quiet:
	@timeout 90 /usr/bin/time nice ./check.sh </dev/null | grep -v 'PASSED \*\*\*$$' >test.log.`ts` 2>&1
	@date
