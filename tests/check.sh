#!/bin/sh

# check script for GNU ed - The GNU line editor
# Copyright (C) 2006-2023 Antonio Diaz Diaz.
#
# This script is free software; you have unlimited permission
# to copy, distribute, and modify it.

LC_ALL=C
export LC_ALL
objdir=`pwd`
testdir=`cd "$1" ; pwd`
new_M2="${objdir}"/m2
framework_failure() { echo "Failure in testing framework" ; exit 1 ; }

if [ ! -f "${new_M2}" ] || [ ! -x "${new_M2}" ] ; then
	echo "${new_M2}: Cannot execute"
	exit 1
fi

if [ -d tmp ] ; then rm -rf tmp ; fi
mkdir tmp
cd "${objdir}"/tmp || framework_failure
tmpdir=`pwd`

# cat "${testdir}"/test.txt > test.txt || framework_failure
fail=0

# printf "testing ed-%s...\n" "$2"

# Run the .m2 "scripts" and compare their output against the .target files,
# which contain the correct output.
# The .m2 scripts should exit with zero status.

# echo cwd     is `pwd`
# echo objdir  is $objdir
# echo testdir is $testdir
# echo tmpdir  is $tmpdir
for dir in "${testdir}"/[A-Z]*; do
        cd $dir
        for nnn in ???; do
                cd $nnn
                [ -f test.disabled ] && continue
                for i in *.m2 ; do
                        # echo cwd is `pwd`
                        # echo path is "$dir/$nnn/$i"
                        # base=`echo "$i" | sed 's,^.*/,,;s,\.ed$,,'`	# remove dir and ext
                        # echo base is $base
                        rm -f test.out test.err
                        if "${new_M2}" $i > test.out 2> test.err; then
                                [ ! -s test.err ] && rm -f test.err
                        	if cmp -s test.out test.target; then
					rm -f test.out
                                else
                        		# mv -f out.o ${base}.o
                        		echo "*** Test output incorrect: $dir/$nnn/test.out ***"
                        		fail=127
                        	fi
                        else
				# mv -f out.log ${base}.log
                        	echo "*** Test exited abnormally: $dir/$nnn/$i ***"
                        	fail=127
                        fi
                done
                cd ..
        done
        cd ..
done

rm -f test.txt

if [ ${fail} -eq 0 ] ; then
	echo "Tests completed successfully."
	cd "${objdir}" && rm -r tmp
else
	echo "Tests failed."
fi
exit ${fail}
