#!/bin/bash

# Debugging:
#set -x

function usage {
    {
	cat <<EOF
Usage:
$0 [-d] infile [cond] > outfile

	-d	Debug: display all commands (set -x).

	lines before cond will not be in the output, in order to remove
	the obfuscator's functions. cond could be a line number, or a
	regexp (including slashes: it's a sed address).
	Default: "1" (from the first line)
Example:
$0 xcsim_1.3_enc.js '/^function *simulator *()/' > xcsim_1.3.js
EOF
    } >&2
    exit 1
}

# Exit if any command appart from tests fails.
set -o errexit
  
DEBUG=$1
if [ "$DEBUG" = "-d" ]; then
    shift
    PS4="$0 \$LINENO: "
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
	grep -v '^\s*\(#\|$\)' "$INPUT".trans |
	    while read hex newname; do
		echo 's/\([^0-9a-zA-Z_]\)'$hex'/\1'$newname'/g'
	    done
    fi

    cat <<EOF
# Deobfuscation:
# Transform from ['string'] index notation to .string dot notation:
s/\[(\?'\([^']\+\)')\?\]/.\1/g
# Indent comma-separated assigns:
s/, *\([.0-9_a-zA-Z]\+ \+= \+\)/,\n\t\1/g
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

# And afterwards pass perl to replace hex literals with decimal literals.
sed -n -f "$INPUT"-sed "$INPUT_BEAU" |
    perl -pe 's/([^_a-zA-Z0-9])0x([0-9a-f]+)/$1.hex($2)/eg' |
    js-beautify --file - --good-stuff --unescape-strings --break-chained-methods --end-with-newline