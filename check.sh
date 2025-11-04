#!/bin/sh

# check.sh - run m2 test suite
#
# DESCRIPTION
# ===========
# Run the *.m2 scripts in the "tests" subdirectory.  For each test,
# compare m2 output against the contents of TESTNAME.out, which contains
# the expected output.  Error messages and exit codes are also checked.
#
# USAGE
# =====
#       $ check.sh                              # Run all tests in "tests" subdirectory
#       $ check.sh CATEGORY                     # Run all tests in all series in CATEGORY
#       $ check.sh CATEGORY/SERIES              # Run all tests in SERIES
#       $ check.sh CATEGORY/SERIES/TESTNAME     # Run one specific test, file TESTNAME.m2
#
# CATEGORY/SERIES/TESTNAME
# ========================
# Tests are separated into broad CATEGORIES which cover all major system
# commands and functions, such as: file include/paste, comment handling,
# diversions, subshell handling, defining new new commands, etc.
# Categories are short names in all caps.
#
# Each category is divided into a SERIES of tests, identified by a
# three-digit number, starting at either 000 or 001 depending on the
# test writer's temperament and/or phase of moon.  The tests in a series
# should relate to a similar theme exercise one specific functional
# component.  For example, one series might include a few checks for
# when a command when supplied with too few, correct number, or too many
# arguments.  Another series might test undefined or anomalous behavior.
#
# TESTNAME is the base file name for the test, which has an .m2 extension.
#
# EXIT CODE
# =========
# It is expected that m2 will succeed and exit with a zero status.  If
# that is not the case (i.e., you expect the test to fail and exit with
# a non-zero status), the expected code must be put in TESTNAME.exit.
# If you expect error messages to be be printed, they must go into
# TESTNAME.err (NB - *not* TESTNAME.out!)  The test will fail if errors
# occur and these files are missing or empty.
#
# FILE NAMING CONVENTION
# ======================
# User-specified config files:
# ----------------------------
# TESTNAME.disabled         If present, TESTNAME is not executed for testing.
# TESTNAME.err              If present, expected m2 error text.  Default "".
# TESTNAME.exit             If present, expected m2 exit code.  Default 0.
# TESTNAME.m2               m2 input file
# TESTNAME.out              Expected m2 standard output.  Required to exist even if empty.
#                           This catches random .m2 files being interpreted as tests, and
#                           also requires a test to positively specify "no output expected".
# TESTNAME.sh               If present, this script will be invoked with sh to run the test.
# TESTNAME.showdiff         If present, show diff of expected/actual output on failure.
#                           (Diff file is always created, this just controls what is shown.)
#
# Temporary working files, deleted after test run:
# ------------------------------------------------
# TESTNAME.run_diff         Diff of expected output vs run output, if different
# TESTNAME.run_err          m2 run standard error
# TESTNAME.run_exit         m2 run exit code
# TESTNAME.run_out          m2 run standard output
# TESTNAME.expected_err     Copy of desired error text, if any, default blank
# TESTNAME.expected_exit    Copy of desired exit code
# TESTNAME.expected_out     Copy of desired output text, if any, default blank
#
# TEST OUTPUT
# ===========
# Framework control messages begin with "!!!", followed by a KEYWORD and info:
#       !!! START - Starting test runs
# Test ids and results are shown on lines beginning and ending with "***":
#       *** NEWCMD/004/simple ... PASS ***
# Exit status codes and data streams are shown in sections whose titles appear
#       >>> LIKE THIS <<<
#
# EXIT STATUS
# ===========
# 0     all tests passed
# 1     interrupted by signal
# 127   at least one test failed
#
# ORIGINAL CODE & AUTHOR
# ======================
# check script for GNU ed - The GNU line editor
# Copyright (C) 2006-2023 Antonio Diaz Diaz.
# This script is free software; you have unlimited permission
# to copy, distribute, and modify it.
#
# USER CONFIGURABLE SETTINGS
# ==========================
# These two variables are user-settable:
debug="false"		# set to "true" for extra messages
busybox_awk="false"	# set to "true" to invoke m2 as "busybox awk -f ..."
gawk_trad="false"       # set to "true" to invoke m2 as "gawk --traditional"
mawk_trad="false"       # set to "true" to invoke m2 as "mawk -W traditional"

#
##      Noli me tangere
#
LC_ALL=C
export LC_ALL
rc=0
ntest=0
npass=0
nskip=0
nfail=0


framework_error()
{
    if [ $# -eq 0 ]; then
        echo "!!! ERROR - Failure in testing framework"
    else
        echo "!!! ERROR - Failure in testing framework: $*"
    fi
    exit 1
}


cat_or_nodata()
{
    local file
    file="$1"
    [ ! -f "$file" ] && framework_error "Expected file '$file' does not exist"
    [ -s "$file" ] && cat "$file" || echo "[NO_DATA]"
}


summarize_tests()
{
    local pass_pct
    local skip_pct
    local fail_pct
    local intr_pct
    local intr
    local chk
    local plural
    pass_pct=0.0
    skip_pct=0.0
    fail_pct=0.0
    intr_pct=0.0
    intr="false"
    chk=$(expr $npass + $nskip + $nfail - $ntest)
    if [ $chk -eq -1 ]; then
        intr="true"
    elif [ $chk -ne 0 ]; then
        framework_error "npass+nskip+nfail-ntest = ${chk}"
    fi

    if [ $ntest -ne 0 ]; then
        pass_pct=`echo "scale=3; $npass*100/$ntest" | bc`
        skip_pct=`echo "scale=3; $nskip*100/$ntest" | bc`
        fail_pct=`echo "scale=3; $nfail*100/$ntest" | bc`
        if [ $intr = "true" ]; then
            intr_pct=`echo "scale=3; 1*100/$ntest" | bc`
        fi
    fi

    [ $ntest -ne 1 ] && plural="s" || plural=""
    printf "!!! SUMMARY - %d test%s:\n" $ntest $plural
    [ $npass -gt 0 ]   && printf "!!!     %3d passed (%.1f%%)\n"  $npass $pass_pct
    [ $nfail -gt 0 ]   && printf "!!!     %3d failed (%.1f%%)\n"  $nfail $fail_pct
    [ $nskip -gt 0 ]   && printf "!!!     %3d skipped (%.1f%%)\n" $nskip $skip_pct
    [ $intr = "true" ] && printf "!!!     %3d interrupted (%.1f%%)\n"  1 $intr_pct
}


# Check if we can run M2.  The *actual* test invocation is performed in
# function run_test() below.
objdir=`pwd`
[ $debug = "true" ] && echo "objdir  is $objdir"
new_M2="${objdir}"/m2
if [ $busybox_awk = "true" ]; then
    busybox awk -f $new_M2 /dev/null >/dev/null 2>&1
    [ $? -eq 0 ] || framework_error "Error executing \"busybox awk -f $new_M2\""
elif [ $gawk_trad = "true" ]; then
    gawk --traditional -f $new_M2 /dev/null >/dev/null 2>&1
    [ $? -eq 0 ] || framework_error "Error executing \"gawk --traditional -f $new_M2\""
elif [ $mawk_trad = "true" ]; then
    mawk -W traditional -f $new_M2 /dev/null >/dev/null 2>&1
    [ $? -eq 0 ] || framework_error "Error executing \"mawk -W traditional -f $new_M2\""
else
    [ -f "${new_M2}" -a -x "${new_M2}" ] || framework_error "Error executing \"${new_M2}\""
fi

testdir="`pwd`/tests"
[ -d $testdir ] || framework_error "$testdir is not a directory"
[ $debug = "true" ] && echo "testdir is $testdir"


test_all_categories()
{
    cd "$testdir"
    for CATEGORY in [A-Z]*; do
        test_category "${CATEGORY}"
    done
    cd ..
}


test_category()
{
    local CATEGORY
    CATEGORY="$1"
    [ -d $CATEGORY ] || framework_error "$CATEGORY is not a directory"
    cd "$CATEGORY"
    for SERIES in ???; do
        [ "$SERIES" = "???" ] && continue # if no numbered subdirectories
        test_series "${CATEGORY}" "${SERIES}"
    done
    cd ..
}


test_series()
{
    local CATEGORY
    local SERIES
    local test_id
    CATEGORY="$1"
    SERIES="$2"

    [ -d $SERIES ] || framework_error "$SERIES is not a directory"
    cd $SERIES
    test_id=`echo $CATEGORY/$SERIES | sed "s,${testdir}/,,"`
    if [ -f test.disabled ]; then
        echo "*** $test_id ... Series disabled, skipping ***"
        cd ..
        return
    fi
    for M2_FILE in *.m2 ; do
        [ $debug = "true" ] && echo "cwd is `pwd`"
        [ $debug = "true" ] && echo "path is \"$CATEGORY/$SERIES/$M2_FILE\""
        run_test "${CATEGORY}" "${SERIES}" "${M2_FILE}"
    done
    cd ..
}


run_test()
{
    local CATEGORY
    local SERIES
    local M2_FILE
    local fail
    local test_id
    local diderr
    local TESTNAME

    CATEGORY="$1"
    SERIES="$2"
    M2_FILE="$3"
    fail=0
    test_id=`echo $CATEGORY/$SERIES | sed "s,${testdir}/,,"`
    diderr=0

    if [ ! -f $M2_FILE ]; then
        M2_FILE="${M2_FILE}.m2"
        [ -f $M2_FILE ] || { framework_error "run_test: $M2_FILE does not exist!"; return; }
    fi

    TESTNAME=`echo "$M2_FILE" | sed 's,^.*/,,;s,\.m2$,,'`   # remove CATEGORY and ext
    [ $debug = "true" ] && echo "TESTNAME is $TESTNAME"
    printf "*** $test_id/$TESTNAME ... "
    ntest=$(expr $ntest + 1)

    if [ ! -s "$M2_FILE" ]; then
        echo "SKIP - Empty test file ***"
        nskip=$(expr $nskip + 1)
        return
    fi
    if [ -f ${TESTNAME}.disabled ]; then
        echo "SKIP - Test disabled ***"
        nskip=$(expr $nskip + 1)
        return
    fi

    rm -f ${TESTNAME}.expected_* ${TESTNAME}.run_*
    trap 'echo; echo "!!! INTERRUPT - Aborting"; rm -f ${TESTNAME}.expected_* ${TESTNAME}.run_*; summarize_tests; echo "!!! END - `date`"; exit 1' 1 2 3 15

    if [ ! -r "$M2_FILE" ]; then
        echo "FAIL - Unreadable test file ***"
        nfail=$(expr $nfail + 1)
        rc=127
        return
    fi
    if [ ! -f ${TESTNAME}.out ]; then
        echo "FAIL - ${TESTNAME}.out does not exist ***"
        nfail=$(expr $nfail + 1)
        rc=127
        return
    fi

    #
    ##  Stash any expected error output and exit code
    #
    cp ${TESTNAME}.out ${TESTNAME}.expected_out
    if [ -f ${TESTNAME}.exit ]; then
        cp ${TESTNAME}.exit ${TESTNAME}.expected_exit
    else
        echo "0" >${TESTNAME}.expected_exit
    fi
    if [ -f ${TESTNAME}.err ]; then
        cp ${TESTNAME}.err ${TESTNAME}.expected_err
    else
        cp /dev/null ${TESTNAME}.expected_err
    fi

    #
    ##  Run the test here
    #
    if [ -r ${TESTNAME}.sh ]; then
        # Since we set up stdout and stderr here,
        # don't try to change them in TESTNAME.sh
        /bin/sh ${TESTNAME}.sh "$new_M2" "$M2_FILE" > ${TESTNAME}.run_out 2> ${TESTNAME}.run_err
    elif [ $busybox_awk = "true" ]; then
        busybox awk -f $new_M2 $M2_FILE > ${TESTNAME}.run_out 2> ${TESTNAME}.run_err
    elif [ $gawk_trad = "true" ]; then
        gawk --traditional -f $new_M2 $M2_FILE > ${TESTNAME}.run_out 2> ${TESTNAME}.run_err
    elif [ $mawk_trad = "true" ]; then
        mawk -W traditional -f $new_M2 $M2_FILE > ${TESTNAME}.run_out 2> ${TESTNAME}.run_err
    else
        $new_M2 $M2_FILE > ${TESTNAME}.run_out 2> ${TESTNAME}.run_err
    fi
    echo $? >${TESTNAME}.run_exit

    #
    ##  Check error messages
    #
    if ! cmp -s ${TESTNAME}.run_err ${TESTNAME}.expected_err; then
        echo "FAIL - Unexpected error messages ***"
        echo "    (file $CATEGORY/$SERIES/$M2_FILE)"
        fail=$(expr $fail + 1)
        echo ">>> EXPECTED ERRORS <<<"
        cat_or_nodata ${TESTNAME}.expected_err
        echo ">>> ACTUAL ERRORS <<<"
        cat_or_nodata ${TESTNAME}.run_err
        diderr=1
        rc=127
    fi
    #
    ##  Check exit code
    #
    if ! cmp -s ${TESTNAME}.run_exit ${TESTNAME}.expected_exit; then
        echo "FAIL - Unexpected exit code ***"
        echo "    (file $CATEGORY/$SERIES/$M2_FILE)"
        fail=$(expr $fail + 1)
        echo ">>> EXPECTED EXIT CODE <<<"
        cat_or_nodata ${TESTNAME}.expected_exit
        echo ">>> ACTUAL EXIT CODE <<<"
        cat_or_nodata ${TESTNAME}.run_exit
        rc=127
    fi
    #
    ##  Check actual output
    #
    if ! cmp -s ${TESTNAME}.run_out ${TESTNAME}.expected_out; then
        echo "FAIL - Unexpected output ***"
        echo "    (file $CATEGORY/$SERIES/$M2_FILE)"
        fail=$(expr $fail + 1)
        # Always create diff file
        diff -c ${TESTNAME}.expected_out ${TESTNAME}.run_out > ${TESTNAME}.run_diff

        if [ -f ${TESTNAME}.showdiff ]; then
            echo ">>> DIFF EXPECTED/ACTUAL OUTPUT TEXT <<<"
            echo diff -c ${TESTNAME}.expected_out ${TESTNAME}.run_out
            cat_or_nodata ${TESTNAME}.run_diff
        else
            echo ">>> EXPECTED OUTPUT TEXT <<<"
            cat_or_nodata ${TESTNAME}.expected_out
            echo ">>> ACTUAL OUTPUT TEXT <<<"
            cat_or_nodata ${TESTNAME}.run_out
        fi
        if [ $diderr -eq 0 -a -s ${TESTNAME}.run_err ]; then
            echo ">>> ERRORS <<<"
            cat_or_nodata ${TESTNAME}.run_err
        fi
        rc=127
    fi
    if [ $fail -eq 0 ]; then
        echo "PASS ***"
        npass=$(expr $npass + 1)
        rm -f ${TESTNAME}.run_*
    else
        nfail=$(expr $nfail + 1)
        # Retain ${TESTNAME}.run_* for further investigation
    fi
    rm -f ${TESTNAME}.expected_*
}


test_something()
{
    local slashes
    local category
    local series
    local file

    # Consolidate, remove trailing, then count slashes
    testwhat=`echo "$1" | tr -s /`
    testwhat=${testwhat%/}
    slashes=`echo "$testwhat" | tr -dc / | wc -c | tr -dc [0-9]`
    [ $debug = "true" ] && echo "slashes=$slashes"


    case $slashes in
        0) category=$testwhat
           cd "$testdir"
           test_category $category
           cd ..
           ;;
        1) category=`echo $testwhat | awk -F/ '{ print $1 }'`
           series=`echo $testwhat | awk -F/ '{ print $2 }'`
           cd "$testdir/$category"
           test_series $category $series
           cd ../..
           ;;
        2) category=`echo $testwhat | awk -F/ '{ print $1 }'`
           series=`echo $testwhat | awk -F/ '{ print $2 }'`
           cd "$testdir/$category/$series"
           file=`echo $testwhat | awk -F/ '{ print $3 }'`
           run_test $category $series $file
           cd ../../..
           ;;
        *) framework_error "Invocation error: Bad # slashes" ;;
    esac
}


if [ $debug = "true" ]; then
    echo "cwd     is `pwd`"
    echo "I see $# arguments"
fi
echo "!!! BEGIN - `date`"
case $# in
    0) echo "!!! START - Starting test runs"
       test_all_categories ;;
    1) echo "!!! START - Starting test runs"
       test_something $1 ;;
    *) framework_error "Invocation error: Bad # parameters" ;;
esac
echo   "!!! STOP - Stopping test runs"

if [ ${rc} -eq 0 ] ; then
    echo "!!! SUCCESS - All tests completed successfully"
elif [ $nfail -eq $ntest ]; then
    echo "!!! DISASTER - All tests failed"
else
    echo "!!! FAILURE - Some tests failed"
fi

summarize_tests
echo "!!! END - `date`"
exit ${rc}
