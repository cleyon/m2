#!/bin/sh

# check script for GNU ed - The GNU line editor
# Copyright (C) 2006-2023 Antonio Diaz Diaz.
# This script is free software; you have unlimited permission
# to copy, distribute, and modify it.


# CATEGORY/SERIES/TESTNAME              (CATEGORY/SERIES is called test_id)
#
# Run the *.m2 "scripts" and compare their output against the TESTNAME.target files,
# which contain the correct output.
#
# It is expected that m2 will succeed and exit with a zero status.  If
# that is not the case (i.e., you expect the test to fail and exit with
# a non-zero status), the expected code should be put in TESTNAME.exit

LC_ALL=C
export LC_ALL
objdir=`pwd`
#echo objdir  is $objdir
# test dir used to be parameter #1, but no longer
#testdir=`cd "$1" ; pwd`
testdir="`pwd`/tests"
#echo testdir is $testdir
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
#echo tmpdir  is $tmpdir


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
        #echo cwd is `pwd`
        #echo path is "$CATEGORY/$SERIES/$M2_FILE"
        test_file "${CATEGORY}" "${SERIES}" "${M2_FILE}" "${test_id}"
    done
    cd ..
}


test_file()
{
    local CATEGORY=$1
    local SERIES=$2
    local M2_FILE=$3
    local test_id=`echo $CATEGORY/$SERIES | sed "s,${testdir}/,,"`
    local TESTNAME

    if [ ! -f $M2_FILE ]; then
        M2_FILE="${M2_FILE}.m2"
        if [ ! -f $M2_FILE ]; then
            framework_error "test_file: $M2_FILE does not exist!"
        fi
    fi

    TESTNAME=`echo "$M2_FILE" | sed 's,^.*/,,;s,\.m2$,,'`   # remove CATEGORY and ext
    #echo TESTNAME is $TESTNAME
    printf "*** $test_id/$TESTNAME ... "

    [ -f ${TESTNAME}.disabled ] && { echo "SKIP (test disabled)"; return; }
    [ -r "$M2_FILE" ] || { echo "SKIP (unreadable test file)"; return; }
    [ -s "$M2_FILE" ] || { echo "SKIP (empty test file)"; return; }
    [ -f ${TESTNAME}.target ] || framework_error "$TESTNAME.target does not exist"

    rm -f ${TESTNAME}.out ${TESTNAME}.err ${TESTNAME}.code ${TESTNAME}.want_code
    if [ -f ${TESTNAME}.exit ]; then
        cp ${TESTNAME}.exit ${TESTNAME}.want_code
    else
        echo "0" >${TESTNAME}.want_code
    fi

    "${new_M2}" $M2_FILE > ${TESTNAME}.out 2> ${TESTNAME}.err
    echo $? >${TESTNAME}.code

    if ! cmp -s ${TESTNAME}.code ${TESTNAME}.want_code; then
        echo "Incorrect exit code"
        echo "    Exit code `cat ${TESTNAME}.code`;  wanted `cat ${TESTNAME}.want_code`"
        fail=127
    fi
    if ! cmp -s ${TESTNAME}.out ${TESTNAME}.target; then
        echo "Incorrect text output"
        echo "    $CATEGORY/$SERIES/$M2_FILE"
        echo ">>>  EXPECTED OUTPUT  >>>"
        cat ${TESTNAME}.target
        echo ">>>  ACTUAL OUTPUT  >>>"
        cat ${TESTNAME}.out
        if [ -s ${TESTNAME}.err ]; then
            echo ">>>  ERRORS  >>>"
            cat ${TESTNAME}.err
        fi
        fail=127
    else
        echo "OK"
        rm -f ${TESTNAME}.out ${TESTNAME}.err
    fi
    rm -f ${TESTNAME}.code ${TESTNAME}.want_code
}


test_this()
{
    testwhat=$1
    local slashes
    slashes=`echo $testwhat | tr -dc / | wc -c | tr -dc [0-9]`
    #echo "slashes=$slashes"

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
           test_file $category $series $file
           cd ../../..
           ;;
        *) framework_error "Invocation error: Bad # slashes" ;;
    esac
}

 
#echo cwd     is `pwd`
case $# in
    0) test_all_categories ;;
    1) test_this $2 ;;
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
