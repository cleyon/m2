@c  Stealth side note using undivert
To whom it may concern:
@longdef text
Just kidding!  I'm actually running away with all the money
and the boss's wife, off to Mexico!  So long, suckers!
@endlong
@divert 8
@text@
@divert
Goodbye, cruel world, I cannot bear the slings and arrows...
@undivert 8 confession
Signing off...
@shell CLONE
cat >confession.clone <<EOF
@text@
EOF
cmp -s confession.clone confession
if [ $? = 0 ]; then echo "GOOD-Equal"; else echo "BAD-Not equal"; fi
rm -f confession*
CLONE
