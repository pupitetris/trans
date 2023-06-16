#!/bin/bash

#set -x

function usage {
    local LEVEL=${1:-1}

    cat >&2 <<EOF
Usage:
$0 [-h] [{-|+}D] [-C=configfile] [{+|-}F]
        -i=infile [-c=[cond]] [-t=transfile] [-o=[outfile]]

        Arguments may be given in any order, any number of times.

        -h      Display this help text and exit.

        -C      Specify a config file which is just a shell file that
                is sourced to set internal variables that represent
                command-line switches:

                DEBUG=0|1        Set to 1 to enable debugging
                PS4=string       Set the debugging prefix string
                                 Default: "$0 \$LINENO: "
                FORCED=0|1       Set to 1 to enable forced execution.
                INPUT=infile
                COND=string
                TRANSFILE=transfile
                OUTPUT=outfile

                Settings in the config file will be overriden by
                subsequent command-line arguments.

        -D      Debug: display all commands (set -x).
        +D      Turn off debugging (default)

        -F      Force execution of all stages, don't compare mod stats.
        +F      Turn off forced execution.

        -i      input javascript file with the obfuscated code. Optional
                if specified from the config file.

        -c      lines before cond will not be in the output, in order to
                remove the obfuscator's functions. cond could be a line
                number, or a regexp (including slashes: it's a sed address).
                Default: "1" (from the first line)

        -t      transfile, if specified, instructions are rendered to replace
                identifiers from the first column in the transfile with the
                corresponding strings in the second column. See README.md
                for format.

        -o      outfile if specified will send output to this file. If the
                file already exists, a patch will first be generated between
                the last direct output of the infile's deobfuscation and the
                outfile, to preserve any changes made on the output after the
                last run. Then, the translation will be performed and the
                patch will be reapplied. Default: use stdout, no patching.

Example:
$0 xcsim_1.3_enc.js '/^function *simulator *()/' xcsim_1.3.js
EOF
    exit $LEVEL
}

function die {
    echo "$0" "$*" >&2
    exit 1
}

function debugging {
    if [ "$1" = 1 ]; then
	set -x
	DEBUG=1
    else
	DEBUG=0
	set +x
    fi
}

# For debugging output:
PS4="$0 \$LINENO: "

# Exit if any command appart from tests fails.
set -o errexit
  
# Cmd-line arg processing

[ -z "$1" ] && usage

COND_DEFAULT=1 # Write output from first line.
OUTPUT_DEFAULT=- # Write output to stdout.

DEBUG=0 # Default: no debug.
FORCED=0
COND=$COND_DEFAULT
OUTPUT=$OUTPUT_DEFAULT
TRANSFILE= # Default: don't use a transfile.

while [ ! -z "$1" ]; do
    ARG="$1"
    shift
    case ${ARG%%=*} in
	-h) usage 0 ;;
	-d) debugging 1 ;;
	+d) debugging 0 ;;
	-F) FORCED=1 ;;
	+F) FORCED=0 ;;
	-C)
	    CONFIG_FILE=${ARG:3}
	    [ -z "$CONFIG_FILE" ] && die "-C: Missing config file"
	    source "$CONFIG_FILE"
	    debugging $DEBUG
	    ;;
	-i)
	    INPUT=${ARG:3}
	    [ -z "$INPUT" ] && die "-i: Missing infile"
	    ;;
	-c)
	    COND=${ARG:3}
	    [ -z "$COND" ] && COND=$COND_DEFAULT
	    ;;
	-t)
	    TRANSFILE=${ARG:3}
	    ;;
	-o)
	    OUTPUT=${ARG:3}
	    [ -z "$OUTPUT" ] && OUTPUT=$OUTPUT_DEFAULT
	    ;;
	*)
	    die "Unrecognized option \"$ARG\""
    esac
done
    
# End of arg processing.

[ -z "$INPUT" ] && die "Missing infile"
if [ ! -e "$INPUT" ]; then
    <"$INPUT" # reminder: we are using errexit
fi

if [ ! -z "$TRANSFILE" -a ! -e "$TRANSFILE" ]; then
    <"$TRANSFILE"
fi

INPUT_BEAU=$INPUT-b
[ $DEBUG = 0 ] && JS_BEAUTIFY_QUIET=--quiet

if [ "$FORCED" = 1 -o \
     $(stat -c %Y "$INPUT") -gt 0$(stat -c %Y "$INPUT_BEAU" 2>/dev/null) ]; then

    touch "$INPUT_BEAU"
    # apt install node-js-beautify
    js-beautify $JS_BEAUTIFY_QUIET --file "$INPUT" --outfile "$INPUT_BEAU" >&2

    DO_INITIAL_STAGE=1

    {
	cat <<EOF
$COND,\${
# Obfuscated strings:
EOF

	base=$(dirname "$0")
	sed 's/a0_0x1993('\''\([^'\'']\+\)'\'', \?'\''\([^'\'']\+\)'\''/\n@@@\t\1\t\2\n/g' "$INPUT_BEAU" |
	    grep ^@@@ | cut -c5- | sort --key=1,3 --general-numeric-sort | uniq |
	    node "$base"/trans.js "$INPUT_BEAU"

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
    } > "$INPUT"-sed1
fi

if [ ! -z "$TRANSFILE" ]; then
    {
	echo "# Manual symbol translations:"
	sed -n 's/^\s+//;s/\s+$//;s/#.*//;s/[(,)]\+$//;/./p' "$TRANSFILE" |
	    while read hex newname; do
		echo 's/\([^0-9a-zA-Z_]\)'$hex'/\1'$newname'/g'
	    done
    } > "$INPUT"-sed2
fi

# Preserve changes to the final outfile in a patch
if [ "x$OUTPUT" != "x-" ]; then
    if [ -e "$OUTPUT"-trans2 ]; then
	diff -u "$OUTPUT"-trans2 "$OUTPUT" > "$OUTPUT".patch || true
    fi
    exec 1>"$OUTPUT"-trans2
fi


function initial_stage() {
    if [ -z "$DO_INITIAL_STAGE" ]; then
	cat "$OUTPUT"-trans1
	return
    fi

    # Call sed and afterwards pass perl to replace hex literals
    # with decimal literals. Finally reindent.
    sed -n -f "$INPUT"-sed1 "$INPUT_BEAU" |
	perl -pe 's/([^_a-zA-Z0-9])0x([0-9a-f]+)/$1.hex($2)/eg' |
	js-beautify --file - --good-stuff --unescape-strings \
		    --break-chained-methods --end-with-newline |
	tee "$OUTPUT"-trans1
}

function final_stage() {
    if [ -z "$TRANSFILE" ]; then
	cat
    else
	sed -f "$INPUT"-sed2
    fi

    # Reapply patch to recover changes
    if [ "x$OUTPUT" != "x-" ]; then
	if [ -e "$OUTPUT".patch ]; then
	    patch -b -o "$OUTPUT" "$OUTPUT"-trans2 < "$OUTPUT".patch >&2 || true
	else
	    cp -f "$OUTPUT"-trans2 "$OUTPUT"
	fi
    fi
}

initial_stage | final_stage
