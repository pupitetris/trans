#!/bin/bash

# Debugging:
#set -x

function usage {
    {
	cat <<EOF
Usage:
$0 [-d] infile [cond] [outfile]

	-d	Debug: display all commands (set -x).

	lines before cond will not be in the output, in order to remove
	the obfuscator's functions. cond could be a line number, or a
	regexp (including slashes: it's a sed address).
	Default: "1" (from the first line)

	outfile if specified will send output to this file. If the
	file already exists, a patch will first be generated between
	the last direct output of the infile's deobfuscation and the
	outfile, to preserve any changes made on the output after the
	last run. Then, the translation will be performed and the
	patch will be reapplied.

Example:
$0 xcsim_1.3_enc.js '/^function *simulator *()/' xcsim_1.3.js
EOF
    } >&2
    exit 1
}

# Exit if any command appart from tests fails.
set -o errexit
  
# For debugging:
PS4="$0 \$LINENO: "

DEBUG=$1
if [ "$DEBUG" = "-d" ]; then
    shift
    set -x
fi

INPUT=$1
[ -z "$INPUT" ] && usage
shift

COND=$1
if [ -z "$COND" ]; then
    COND=1
else
    shift
fi

if [ ! -e "$INPUT" ]; then
    <"$INPUT" # reminder: we are using errexit
fi

OUTFILE=$1
if [ -z "$OUTFILE" ]; then
    OUTFILE=-
else
    shift
fi

INPUT_BEAU=$INPUT-b
if [ $(stat -c %Y "$INPUT") -gt 0$(stat -c %Y "$INPUT_BEAU" 2>/dev/null) ]; then
    # apt install node-js-beautify
    js-beautify --file "$INPUT" --outfile "$INPUT_BEAU"
fi

base=$(dirname "$0")

{
    echo "$COND,\${"
    echo "# Obfuscated strings:"

    sed 's/a0_0x1993('\''\([^'\'']\+\)'\'', \?'\''\([^'\'']\+\)'\''/\n@@@\t\1\t\2\n/g' "$INPUT_BEAU" |
	grep ^@@@ | cut -c5- | sort --key=1,3 --general-numeric-sort | uniq |
	node "$base"/trans.js "$INPUT_BEAU"

    if [ -e "$INPUT".trans ]; then
	echo "# Manual symbol translations:"
	sed -n 's/^\s+//;s/\s+$//;s/#.*//;s/[(,)]\+$//;/./p' "$INPUT".trans |
	    while read hex newname; do
		echo 's/\([^0-9a-zA-Z_]\)'$hex'/\1'$newname'/g'
	    done
    fi

    cat <<EOF
# Deobfuscation:
# Transform from ['string'] index notation to .string dot notation:
s/\[(\?'\([^']\+\)')\?\]/.\1/g
# Indent comma-separated assigns:
s/, *\([].0-9_a-zA-Z[]\+ \+= \+\)/,\n\t\1/g
# Easier to read booleans:
s/!0x0\([^0-9a-f]\|$\)/true\1/g
s/!0x1\([^0-9a-f]\|$\)/false\1/g
s/!\!\[\]/true/g
s/!\[\]/false/g
# Character literals: (now done by js-beautify)
# s/\x20/ /g
p
}
EOF

} > "$INPUT"-sed


# Preserve changes in the final outfile in a patch
if [ ! "x$OUTFILE" = "x-" ]; then
    if [ -e "$OUTFILE"-trans ]; then
	diff -u "$OUTFILE"-trans "$OUTFILE" > "$OUTFILE".patch || true
    fi
    exec 1>"$OUTFILE"-trans
fi

# And afterwards pass perl to replace hex literals with decimal literals.
sed -n -f "$INPUT"-sed "$INPUT_BEAU" |
    perl -pe 's/([^_a-zA-Z0-9])0x([0-9a-f]+)/$1.hex($2)/eg' |
    js-beautify --file - --good-stuff --unescape-strings --break-chained-methods --end-with-newline

# Reapply patch to recover changes
if [ ! "x$OUTFILE" = "x-" ]; then
    if [ -e "$OUTFILE".patch ]; then
	patch -b -o "$OUTFILE" "$OUTFILE"-trans < "$OUTFILE".patch >&2 || true
    else
	cp -f "$OUTFILE"-trans "$OUTFILE"
    fi
fi
