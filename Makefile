.PHONY:	all callgraph-full callgraph-sane callgraph-io vars funcs lint tags check test m2

GOOD_M2=/Users/cleyon/bin-n.yuuko/m2
AWK=/usr/bin/awk
GAWK=/usr/local/bin/gawk
MAWK=/usr/local/bin/mawk
NAWK=/usr/bin/nawk
CALLGRAPH=~/repos.cp/github.com/koknat/callGraph/callGraph
CALLGRAPH_SANE_IGNORE_REGEXP=(rm_quotes|assert_(valid_env_var_name|sym_unprotected|(cmd_name|sym|seq)_(valid_name|okay_to_define))|chomp|end_program|dbg|tmpdir|uuid|build_subsep|find_closing_brace|hex_digits|load_init_files|initialize|initialize_debugging|strictp|flush_stdout|error|currently_active_p|dbg_print|warn|integerp|calc3_eval|randint|print_stderr|first|last|chop|qsort)
CALLGRAPH_IO_IGNORE_REGEXP=(_c3_advance|_c3_calculate_function|_c3_calculate_function2|_c3_expr|_c3_factor|_c3_factor2|_c3_factor3|_c3_rel|_c3_term|_less_than|_ord_init|assert_ncmd_okay_to_define|assert_nseq_okay_to_define|assert_nseq_valid_name|assert_nsym_defined|assert_nsym_okay_to_define|assert_nsym_unprotected|assert_nsym_valid_name|assert_valid_env_var_name|build_prog_cmdline|builtin_array|builtin_case|builtin_default|builtin_define|builtin_divert|builtin_dump|builtin_else|builtin_error|builtin_exit|builtin_for|builtin_if|builtin_ignore|builtin_include|builtin_incr|builtin_input|builtin_local|builtin_longdef|builtin_newcmd|builtin_next|builtin_nelse|builtin_nif|builtin_read|builtin_readarray|builtin_readonly|builtin_sequence|builtin_shell|builtin_typeout|builtin_undefine|builtin_undivert|calc3_eval|chomp|chop|currently_active_p|dbg|dbg_get_level|dbg_print|dbg_set_level|debugp|default_shell|do_qq|double_underscores_p|emptyp|end_program|env_var_name_valid_p|error|exec_prog_cmdline|expand_braces|find_closing_brace|first|flag_1false_p|flag_1true_p|flag_allfalse_p|flag_alltrue_p|flag_anyfalse_p|flag_anytrue_p|flag_set_clear|flush_stdout|format_message|hex_digits|initialize|integerp|isalpha|isdigit|isspace|last|load_init_files|lower_namespace|ltrim|max|ncmd_defined_p|ncmd_definition_pp|ncmd_destroy|ncmd_ll_read|ncmd_ll_write|ncmd_valid_p|nnam_dump_nnamtab|nnam_ll_in|nnam_ll_read|nnam_ll_write|nnam_lookup|nnam_parse|nnam_purge|nnam_valid_strict_regexp_p|nnam_valid_with_strict_as|nseq_defined_p|nseq_definition_pp|nseq_destroy|nseq_ll_incr|nseq_ll_read|nseq_ll_write|nseq_valid_p|nstk_top|nstk_pop|nstk_push|nsym_create|nsym_defined_p|nsym_delayed_define_now|nsym_delayed_p|nsym_delayed_symbol|nsym_destroy|nsym_dump_nseqtab|nsym_dump_nsymtab|nsym_fetch|nsym_increment|nsym_info_defined_lev_p|nsym_ll_fiat|nsym_ll_in|nsym_ll_protected|nsym_ll_read|nsym_ll_write|nsym_protected_p|nsym_purge|nsym_store|nsym_system_p|nsym_true_p|nsym_valid_p|path_exists_p|print_stderr|qsort|raise_namespace|randint|restore_context|rm_quotes|round|rtrim|run_latest_tests|save_context|setup_prog_paths|strictp|swap|sym_definition_pp|tmpdir|undivert_all|uuid|warn|with_trailing_slash)

all:
	@echo "Say what now?"

callgraph-full:
	$(CALLGRAPH) m2 -language awk

callgraph callgraph-sane:
	$(CALLGRAPH) m2 -language awk -ignore '$(CALLGRAPH_SAVE_IGNORE_REGEXP)'

callgraph-io:
	$(CALLGRAPH) m2 -language awk -ignore '$(CALLGRAPH_IO_IGNORE_REGEXP)'

gm2:
	sed '1s,$(AWK),$(GAWK),' m2 > $@
	chmod +x $@

mm2:
	sed '1s,$(AWK),$(MAWK),' m2 > $@
	chmod +x $@

nm2:
	sed '1s,$(AWK),$(NAWK),' m2 > $@
	chmod +x $@

funcs:
	@rm -f awkfuncs.out
	grep '^function' m2 | sed 's/(.*//' | awk '{print $$2}' | sort >awkfuncs.out

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
