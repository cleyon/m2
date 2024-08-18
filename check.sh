#!/bin/sh

# check script for GNU ed - The GNU line editor
# Copyright (C) 2006-2023 Antonio Diaz Diaz.
# This script is free software; you have unlimited permission
# to copy, distribute, and modify it.


# CATEGORY/SERIES/TESTNAME              (CATEGORY/SERIES is called test_id)
# ========================
# Run the *.m2 "scripts" and compare their output against the TESTNAME.out files,
# which contain the correct output.
#
# It is expected that m2 will succeed and exit with a zero status.  If
# that is not the case (i.e., you expect the test to fail and exit with
# a non-zero status), the expected code should be put in TESTNAME.exit


# FILE NAMING CONVENTION
# ======================
# User-specified config files:
# ----------------------------
# TESTNAME.disabled     If present, TESTNAME is not executed for testing.  OPT CONFIG
# TESTNAME.err          If present, expected m2 error text.  Default "".  CONFIG
# TESTNAME.exit         If present, expected m2 exit code.  Default 0.  CONFIG
# TESTNAME.out          If present, expected m2 standard output.  Default "".  CONFIG
#
# Temporary working files, deleted after run:
# -------------------------------------------
# TESTNAME.ur_err       m2 run standard error.
# TESTNAME.ur_exit      m2 run exit code.
# TESTNAME.ur_out       m2 run standard output.
# TESTNAME.want_err     Copy of desired error text, if any, default blank.
# TESTNAME.want_exit    Copy of desired exit code.


debug="false"   # "true"

LC_ALL=C
export LC_ALL
objdir=`pwd`
[ $debug = "true" ] && echo "objdir  is $objdir"
# test dir used to be parameter #1, but no longer
#testdir=`cd "$1" ; pwd`
testdir="`pwd`/tests"
[ $debug = "true" ] && echo "testdir is $testdir"
new_M2="${objdir}"/m2

framework_error()
{
    if [ $# -eq 0 ]; then
        echo "!!! Failure in testing framework" 1>&2
    else
        echo "!!! Failure in testing framework: $1" 1>&2
    fi
    exit 1
}

[ -f "${new_M2}" -a -x "${new_M2}" ] || framework_error "${new_M2}: Cannot execute"

# cat "${testdir}"/test.txt > test.txt || framework_error
fail=0

if [ -d tmp ] ; then rm -rf tmp ; fi
mkdir tmp
cd "${objdir}"/tmp || framework_error "Could not change directory to ${objdir}/tmp"
tmpdir=`pwd`
[ $debug = "true" ] && echo "tmpdir  is $tmpdir"


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
        run_test "${CATEGORY}" "${SERIES}" "${M2_FILE}" "${test_id}"
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
        if [ ! -f $M2_FILE ]; then
            framework_error "run_test: $M2_FILE does not exist!"
        fi
    fi

    TESTNAME=`echo "$M2_FILE" | sed 's,^.*/,,;s,\.m2$,,'`   # remove CATEGORY and ext
    [ $debug = "true" ] && echo "TESTNAME is $TESTNAME"
    printf "*** $test_id/$TESTNAME ... "

    [ -f ${TESTNAME}.disabled ] && { echo "SKIP - test disabled"; return; }
    [ -r "$M2_FILE" ] || { echo "SKIP - unreadable test file"; return; }
    [ -s "$M2_FILE" ] || { echo "SKIP - empty test file"; return; }

    rm -f ${TESTNAME}.ur_out ${TESTNAME}.ur_err ${TESTNAME}.ur_exit ${TESTNAME}.want_exit
    if [ -f ${TESTNAME}.exit ]; then
        cp ${TESTNAME}.exit ${TESTNAME}.want_exit
    else
        echo "0" >${TESTNAME}.want_exit
    fi
    if [ -f ${TESTNAME}.out ]; then
        cp ${TESTNAME}.out ${TESTNAME}.want_out
    else
        cp /dev/null ${TESTNAME}.want_out
    fi
    if [ -f ${TESTNAME}.err ]; then
        cp ${TESTNAME}.err ${TESTNAME}.want_err
    else
        cp /dev/null ${TESTNAME}.want_err
    fi

    "${new_M2}" $M2_FILE > ${TESTNAME}.ur_out 2> ${TESTNAME}.ur_err
    echo $? >${TESTNAME}.ur_exit

    if ! cmp -s ${TESTNAME}.ur_exit ${TESTNAME}.want_exit; then
        echo "FAIL - exit code"
        echo "    Exit code `cat ${TESTNAME}.ur_exit`;  wanted `cat ${TESTNAME}.want_exit`"
        fail=127
    fi
    if ! cmp -s ${TESTNAME}.ur_out ${TESTNAME}.want_out; then
        echo "FAIL - text output"
        echo "FILE $CATEGORY/$SERIES/$M2_FILE"
        echo ">>>  EXPECTED OUTPUT  >>>"
        cat ${TESTNAME}.want_out
        echo ">>>  ACTUAL OUTPUT  >>>"
        cat ${TESTNAME}.ur_out
        if [ -s ${TESTNAME}.ur_err ]; then
            echo ">>>  ERRORS  >>>"
            cat ${TESTNAME}.ur_err
        fi
        fail=127
    elif ! cmp -s ${TESTNAME}.ur_err ${TESTNAME}.want_err; then
        echo "FAIL - error messages"
        echo "FILE $CATEGORY/$SERIES/$M2_FILE"
        echo ">>>  EXPECTED ERRORS  >>>"
        cat ${TESTNAME}.want_err
        echo ">>>  ACTUAL ERRORS  >>>"
        cat ${TESTNAME}.ur_err
        fail=127
    else
        echo "PASS"
        rm -f ${TESTNAME}.ur_out ${TESTNAME}.ur_err
    fi
    rm -f ${TESTNAME}.ur_exit ${TESTNAME}.want_exit ${TESTNAME}.want_err ${TESTNAME}.want_out
}


test_something()
{
    testwhat=$1
    local slashes
    slashes=`echo $testwhat | tr -dc / | wc -c | tr -dc [0-9]`
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

#rm -f test.txt
if [ ${fail} -eq 0 ] ; then
    echo "!!! SUCCESS - tests completed successfully"
    cd "${objdir}" && rm -r tmp
else
    echo "!!! FAILURE - some tests failed."
fi
exit ${fail}
