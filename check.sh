#!/bin/sh

# check script for GNU ed - The GNU line editor
# Copyright (C) 2006-2023 Antonio Diaz Diaz.
# This script is free software; you have unlimited permission
# to copy, distribute, and modify it.
#
#
# CATEGORY/SERIES/TESTNAME              (CATEGORY/SERIES is called test_id)
# ========================
# Run the *.m2 "scripts" and compare their output against the TESTNAME.out files,
# which contain the correct output.
#
# It is expected that m2 will succeed and exit with a zero status.  If
# that is not the case (i.e., you expect the test to fail and exit with
# a non-zero status), the expected code should be put in TESTNAME.exit
#
#
# FILE NAMING CONVENTION
# ======================
# User-specified config files:
# ----------------------------
# TESTNAME.disabled         If present, TESTNAME is not executed for testing
# TESTNAME.err              If present, expected m2 error text.  Default ""
# TESTNAME.exit             If present, expected m2 exit code.  Default 0
# TESTNAME.out              Expected m2 standard output.  Required to exist even if empty
#                           This catches random .m2 files being interpreted as tests, and
#                           also requires a test to positively specify "no output expected".
# TESTNAME.sh               If present, this script will be invoked with sh to run the test.
# TESTNAME.showdiff         If present, show diff of expected/actual output on failure
#
# Temporary working files, deleted after test run:
# ------------------------------------------------
# TESTNAME.run_err          m2 run standard error
# TESTNAME.run_exit         m2 run exit code
# TESTNAME.run_out          m2 run standard output
# TESTNAME.expected_err     Copy of desired error text, if any, default blank
# TESTNAME.expected_exit    Copy of desired exit code
# TESTNAME.expected_out     Copy of desired output text, if any, default blank
#
#
# EXIT STATUS
# ===========
# 0     all tests passed
# 127   at least one test failed


# These two variables are user settable:
debug="false"		# set to "true" for extra messages
busybox_awk="false"	# set to "true" to invoke m2 as "busybox awk -f ..."


LC_ALL=C
export LC_ALL
rc=0
ntest=0
npass=0
nfail=0


framework_error()
{
    if [ $# -eq 0 ]; then
        echo "!!! Failure in testing framework" 1>&2
    else
        echo "!!! Failure in testing framework: $1" 1>&2
    fi
    exit 1
}


summarize_tests()
{
    printf "!!! SUMMARY - %d total tests: %d passed (%.1f%%), %d failed (%.1f%%)\n" \
           $ntest $npass `echo "scale=3; $npass*100/$ntest" | bc` \
                  $nfail `echo "scale=3; $nfail*100/$ntest" | bc`
}


objdir=`pwd`
[ $debug = "true" ] && echo "objdir  is $objdir"
new_M2="${objdir}"/m2
if [ $busybox_awk = "true" ]; then
    busybox awk -f $new_M2 /dev/null >/dev/null 2>&1
    [ $? -eq 0 ] || framework_error "Error executing \"busybox awk -f $new_M2\""
else
    [ -f "${new_M2}" -a -x "${new_M2}" ] || framework_error "${new_M2}: Cannot execute"
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
    local CATEGORY=$1

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
    local CATEGORY=$1
    local SERIES=$2

    [ -d $SERIES ] || framework_error "$SERIES is not a directory"
    cd $SERIES
    local test_id=`echo $CATEGORY/$SERIES | sed "s,${testdir}/,,"`
    if [ -f test.disabled ]; then
        echo "*** $test_id ... Series disabled, skipping"
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
    local CATEGORY=$1
    local SERIES=$2
    local M2_FILE=$3

    local test_id=`echo $CATEGORY/$SERIES | sed "s,${testdir}/,,"`
    local TESTNAME

    if [ ! -f $M2_FILE ]; then
        M2_FILE="${M2_FILE}.m2"
        [ -f $M2_FILE ] || { framework_error "run_test: $M2_FILE does not exist!"; return; }
    fi

    TESTNAME=`echo "$M2_FILE" | sed 's,^.*/,,;s,\.m2$,,'`   # remove CATEGORY and ext
    [ $debug = "true" ] && echo "TESTNAME is $TESTNAME"

    printf "*** $test_id/$TESTNAME ... "

    [ -f ${TESTNAME}.disabled ] && { echo "SKIP - Test disabled"; return; }
    [ -s "$M2_FILE" ] || { echo "SKIP - Empty test file"; return; }

    rm -f ${TESTNAME}.expected_out ${TESTNAME}.expected_err ${TESTNAME}.expected_exit
    rm -f ${TESTNAME}.run_out      ${TESTNAME}.run_err      ${TESTNAME}.run_exit
    trap 'rm -f ${TESTNAME}.expected_out ${TESTNAME}.expected_err ${TESTNAME}.expected_exit ${TESTNAME}.run_out ${TESTNAME}.run_err ${TESTNAME}.run_exit; summarize_tests; exit' \
         1 2 3 15
    ntest=$(expr $ntest + 1)

    if [ ! -r "$M2_FILE" ]; then
        echo "FAIL - Unreadable test file"
        nfail=$(expr $nfail + 1)
        rc=127
        return
    fi
    if [ ! -f ${TESTNAME}.out ]; then
        echo "FAIL - ${TESTNAME}.out does not exist!"
        nfail=$(expr $nfail + 1)
        rc=127
        return
    fi

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

    if [ -r ${TESTNAME}.sh ]; then
        # Since we set up stdout and stderr here,
        # don't try to change them in TESTNAME.sh
        /bin/sh ${TESTNAME}.sh "$new_M2" "$M2_FILE" > ${TESTNAME}.run_out 2> ${TESTNAME}.run_err
    elif [ $busybox_awk = "true" ]; then
        busybox awk -f $new_M2 $M2_FILE > ${TESTNAME}.run_out 2> ${TESTNAME}.run_err
    else
        $new_M2 $M2_FILE > ${TESTNAME}.run_out 2> ${TESTNAME}.run_err
    fi
    echo $? >${TESTNAME}.run_exit

    if ! cmp -s ${TESTNAME}.run_exit ${TESTNAME}.expected_exit; then
        echo "FAIL - Unexpected exit code"
        echo "    Exit code `cat ${TESTNAME}.run_exit`;  wanted `cat ${TESTNAME}.expected_exit`"
        nfail=$(expr $nfail + 1)
        rc=127
    fi
    if ! cmp -s ${TESTNAME}.run_out ${TESTNAME}.expected_out; then
        echo "FAIL - Unexpected output"
        echo "    (file $CATEGORY/$SERIES/$M2_FILE)"
        nfail=$(expr $nfail + 1)
        if [ -f ${TESTNAME}.showdiff ]; then
            echo ">>> DIFF EXPECTED/ACTUAL OUTPUT TEXT <<<"
            echo diff -c ${TESTNAME}.expected_out ${TESTNAME}.run_out
            diff -c ${TESTNAME}.expected_out ${TESTNAME}.run_out
        else
            echo ">>> EXPECTED OUTPUT TEXT <<<"
            cat ${TESTNAME}.expected_out
            echo ">>> ACTUAL OUTPUT TEXT <<<"
            cat ${TESTNAME}.run_out
        fi
        if [ -s ${TESTNAME}.run_err ]; then
            echo ">>> ERRORS <<<"
            cat ${TESTNAME}.run_err
        fi
        rc=127
    elif ! cmp -s ${TESTNAME}.run_err ${TESTNAME}.expected_err; then
        echo "FAIL - Unexpected error messages"
        echo "    (file $CATEGORY/$SERIES/$M2_FILE)"
        nfail=$(expr $nfail + 1)
        echo ">>> EXPECTED ERRORS <<<"
        cat ${TESTNAME}.expected_err
        echo ">>> ACTUAL ERRORS <<<"
        cat ${TESTNAME}.run_err
        rc=127
    else
        echo "PASS"
        npass=$(expr $npass + 1)
        rm -f ${TESTNAME}.run_out ${TESTNAME}.run_err
    fi

    # Retain ${TESTNAME}.{run_out,run_err} for further investigation
    rm -f ${TESTNAME}.expected_out ${TESTNAME}.expected_err ${TESTNAME}.expected_exit
    rm -f                                                   ${TESTNAME}.run_exit 
}


test_something()
{
    local slashes
    # Consolidate, remove trailing, then count slashes
    testwhat=`echo "$1" | tr -s /`
    testwhat=${testwhat%/}
    slashes=`echo "$testwhat" | tr -dc / | wc -c | tr -dc [0-9]`
    [ $debug = "true" ] && echo "slashes=$slashes"

    local category
    local series
    local file
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

 
[ $debug = "true" ] && echo "cwd     is `pwd`"
[ $debug = "true" ] && echo "I see $# arguments"
case $# in
    0) test_all_categories ;;
    1) test_something $1 ;;
    *) framework_error "Invocation error: Bad # parameters" ;;
esac


if [ ${rc} -eq 0 ] ; then
    echo "!!! SUCCESS - Tests completed successfully"
else
    echo "!!! FAILURE - Some tests failed"
fi

summarize_tests
exit ${rc}
