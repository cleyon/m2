.PHONY:	all man manview callgraph callgraph-full callgraph-sane callgraph-io clean distclean lint tags \
	funcs vars \
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
CALLGRAPH_SANE_IGNORE_REGEXP=(rm_quotes|assert_(valid_env_var_name|sym_unprotected|(cmd_name|sym|seq)_(valid_name|okay_to_define))|chomp|flag_(1|all|any)(true|false)_p|end_program|dbg|tmpdir|uuid|build_subsep|find_closing_brace|hex_digits|load_init_files|initialize|initialize_debugging|strictp|flush_stdout|error|currently_active_p|dbg_print|warn|integerp|calc3_eval|randint|print_stderr|first|last|chop|pp_bool|qsort)
# In callgraph-io, I took out the blk_* functions, even though they're integral to the I/O functioning
CALLGRAPH_IO_IGNORE_REGEXP=(panic|_c3_(advance|calculate_function|calculate_function2|expr|factor|factor2|factor3|rel|term)|_less_than|_ord_init|abs|assert_(cmd_okay_to_define|seq_okay_to_define|seq_valid_name|sym_defined|sym_okay_to_define|sym_unprotected|sym_valid_name|scan_stack_okay|valid_env_var_name)|arr_(clear|size)|build_prog_cmdline|calc3_eval|check__parse_stack|chomp|chop|clear_debugging|curr_atmode|curr_dstblk|dbg|dbg_get_level|dbg_print|dbg_set_level|debugp|default_shell|divnum|double_underscores_p|dump_parse_stack|emptyp|end_program|env_var_name_valid_p|error|exec_prog_cmdline|expand_braces|extract_cmd_name|find_closing_brace|first|flag_(1|all|any)(true|false)_p|flag_set_clear|floatp|flush_stdout|format_message|hex_digits|initialize|integerp|isalpha|isdigit|isspace|last|load_init_files|lower_namespace|ltrim|max|blk_(append|dump_blktab|ll_(slot_type|slot_value|write)|new|to_string|type)|cmd_(defined_p|definition_pp|destroy|ll_read|ll_write|valid_p)|dump__(cmdtab|seqtab|symtab)|nam_(dump_namtab|ll_in|ll_read|ll_write|lookup|parse|ppf_name_level|purge|valid_strict_regexp_p|valid_with_strict_as)|nam__scan|seq_(defined_p|definition_pp|destroy|ll_incr|ll_read|ll_write|valid_p)|stk_(depth|pop|push|top)|sym_(create|defined_p|deferred_define_now|deferred_p|deferred_symbol|destroy|fetch|increment|info_defined_lev_p|ll_fiat|ll_in|ll_protected|ll_read|ll_write|protected_p|purge|store|system_p|true_p|valid_p)|path_exists_p|ppf__(BLK_(AGG|CASE|FILE|FOR|IF|LONGDEF|USER|WHILE)|agg|bool|block|block_type|case|flag_type|flags|for|if|longdef|mode|user|while)|print_stderr|qsort|raise_namespace|randint|rest|readline|restore_context|rm_quotes|round|rtrim|run_latest_tests|save_context|secure_level|setup_prog_paths|strictp|swap|sym_define_all_deferred|sym_definition_pp|tmpdir|trim|(clear|un)divert(_all)?|uuid|warn|with_trailing_slash|xeq_cmd__m2ctl|DIVNUM|FILE|LINE)
TAGS=ctags -e

all:
	@echo "Say what now?"

man: m2.cat1

manview: m2.cat1
	less m2.cat1

callgraph-full:
	$(CALLGRAPH) m2 -language awk

callgraph callgraph-sane:
	$(CALLGRAPH) m2 -language awk -ignore '$(CALLGRAPH_SANE_IGNORE_REGEXP)'

callgraph-io:
	$(CALLGRAPH) m2 -language awk -ignore '$(CALLGRAPH_IO_IGNORE_REGEXP)'

debug:
	$(GAWK) -D -f m2

m2.cat1: m2.1
	nroff -mdoc $^ > $@

m2.ps: m2.1
	groff -Tps -mdoc $^ > $@

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

clean:
	rm -f  m2.cat1  test.log.*  tests/*/*/*.run_*  tests/*/*/*.expected_*

distclean: clean
	rm -f *~ awkvars.out awkfuncs.out

lint:
	$(GAWK) --lint --posix -f m2 /dev/null

tags:
	$(TAGS) m2

check-verbose test-verbose verbose-check verbose-test:
	@date
	@/usr/bin/time ./check.sh
	@date

check test check-quiet test-quiet quiet-check quiet-test:
	@/usr/bin/time ./check.sh </dev/null 2>&1 | grep -v 'PASS \*\*\*$$'
	@date

testlog-verbose:
	@date
	@timeout 90 /usr/bin/time nice ./check.sh </dev/null >test.log.`ts` 2>&1
	@date

testlog testlog-quiet:
	@timeout 90 /usr/bin/time nice ./check.sh </dev/null | grep -v 'PASS \*\*\*$$' >test.log.`ts` 2>&1
	@date
