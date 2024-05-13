.PHONY:	all callgraph-full callgraph-sane vars lint tags check test m2

GOOD_M2=/Users/cleyon/bin-n.yuuko/m2
AWK=/usr/bin/awk
GAWK=/usr/local/bin/gawk
MAWK=/usr/local/bin/mawk
NAWK=/usr/bin/nawk
CALLGRAPH=~/repos.cp/github.com/koknat/callGraph/callGraph
CALLGRAPH_IGNORE_REGEXP=(rm_quotes|assert_(valid_env_var_name|sym_unprotected|(cmd_name|sym|seq)_(valid_name|okay_to_define))|chomp|end_program|dbg|tmpdir|uuid|build_subsep|find_closing_brace|hex_digits|load_init_files|initialize|initialize_debugging|strictp|flush_stdout|error|currently_active_p|dbg_print|warn|integerp|calc3_eval|randint|print_stderr|first|last|chop|qsort)

all:
	@echo "Say what now?"

callgraph-full:
	$(CALLGRAPH) m2 -language awk

callgraph callgraph-sane:
	$(CALLGRAPH) m2 -language awk -ignore '$(CALLGRAPH_IGNORE_REGEXP)'

gm2:
	sed '1s,$(AWK),$(GAWK),' m2 > $@
	chmod +x $@

mm2:
	sed '1s,$(AWK),$(MAWK),' m2 > $@
	chmod +x $@

nm2:
	sed '1s,$(AWK),$(NAWK),' m2 > $@
	chmod +x $@

vars:
	@rm -f awkvars.out
	$(GAWK) -d -f m2 /dev/null >/dev/null

lint:
	$(GAWK) --lint -f m2 /dev/null

tags:
	etags m2

test check:
#	@$(VPATH)/tests/check.sh $(VPATH)/tests $(pkgversion)
	@./tests/check.sh "`pwd`/tests" # $(pkgversion)
