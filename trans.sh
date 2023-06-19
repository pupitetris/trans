#!/bin/bash

#set -x

function usage {
    local LEVEL=${1:-1}

    cat >&2 <<EOF
Usage:
$0 [-h] [{-|+}D] [-C=configfile] [{-|+}F] -i=infile
        [-c=[cond]] [-t=transfile [-o=[outfile]] [{-|+}M]]

        Arguments may be given in any order, any number of times.

        -h      Display this help text and exit.

        -C      Specify a config file which is just a shell file that
                is sourced to set internal variables that represent
                command-line switches:

                DEBUG=0|1
                PS4=string       Set the debugging prefix string
                                 Default: "\$0 \\\$LINENO: "
                FORCED=0|1
                MONITOR=0|1
                INFILE=infile
                COND=string
                TRANSFILE=transfile
                OUTFILE=outfile

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

        -M      Stand by monitoring files, reprocess accordingly. If transfile
                is modified, regenerate discrete translator and reprocess. If
                outfile is modified, regenerate patch. Any reprocessing errors
                will stop monitoring and force an exit.
        +M      Disable monitoring.

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

DEBUG_DEFAULT=0
FORCED_DEFAULT=0
COND_DEFAULT=1 # Write output from first line.
MONITOR_DEFAULT=0
OUTFILE_DEFAULT=- # Write output to stdout.

DEBUG=$DEBUG_DEFAULT # Default: no debug.
FORCED=$FORCED_DEFAULT
COND=$COND_DEFAULT
TRANSFILE= # Default: don't use a transfile.
MONITOR=$MONITOR_DEFAULT
OUTFILE=$OUTFILE_DEFAULT

while [ ! -z "$1" ]; do
    ARG="$1"
    shift
    case "${ARG%%=*}" in
	-h) usage 0 ;;
	-D) debugging 1 ;;
	+D) debugging 0 ;;
	-F) FORCED=1 ;;
	+F) FORCED=0 ;;
	-M) MONITOR=1 ;;
	+M) MONITOR=0 ;;
	-C)
	    CONFIG_FILE=${ARG:3}
	    [ -z "$CONFIG_FILE" ] && die "-C: Missing config file"
	    source "$CONFIG_FILE"
	    debugging $DEBUG
	    ;;
	-i)
	    INFILE=${ARG:3}
	    [ -z "$INFILE" ] && die "-i: Missing infile"
	    ;;
	-c)
	    COND=${ARG:3}
	    [ -z "$COND" ] && COND=$COND_DEFAULT
	    ;;
	-t)
	    TRANSFILE=${ARG:3}
	    ;;
	-o)
	    OUTFILE=${ARG:3}
	    ;;
	*)
	    die "Unrecognized option \"$ARG\""
    esac
done
    
# Now canonize and validate configuration:

[ -z "$FORCED" ] && FORCED=$FORCED_DEFAULT

[ -z "$INFILE" ] && die "Missing infile parameter"
if [ ! -e "$INFILE" ]; then
    <"$INFILE" # reminder: we are using errexit
fi

if [ ! -z "$TRANSFILE" ]; then
    HAS_TRANSFILE=1
    if [ ! -e "$TRANSFILE" ]; then
	<"$TRANSFILE"
    fi
else
    HAS_TRANSFILE=0
fi

[ -z "$OUTFILE" ] && OUTFILE=$OUTFILE_DEFAULT
if [ "x$OUTFILE" != "x-" ]; then
    HAS_OUTFILE=1
else
    HAS_OUTFILE=0
fi

[ -z "$MONITOR" ] && MONITOR=$MONITOR_DEFAULT
if [ $MONITOR = 1 -a $HAS_TRANSFILE = 0 -a $HAS_OUTFILE = 0 ]; then
    die "Monitoring requested, but no transfile nor outfile specified"
fi

[ $DEBUG = 0 ] && JS_BEAUTIFY_QUIET=--quiet

# Path finding:

INDIR=$(dirname "$INFILE")/.trans
mkdir -p "$INDIR"
IN_PREFIX=$INDIR/$INFILE
INFILE_BEAU=$IN_PREFIX-b
INFILE_SED=$IN_PREFIX-sed
INFILE_TRANS=$IN_PREFIX-trans

if [ $HAS_OUTFILE = 1 ]; then
    OUTDIR=$(dirname "$OUTFILE")/.trans
    mkdir -p "$OUTDIR"
    OUT_PREFIX=$OUTDIR/$OUTFILE
    OUTFILE_TRANS=$OUT_PREFIX-trans\
    # Not a mistake since the patch is a product of the workflow:
    OUTFILE_PATCH=$OUTFILE.patch
fi

if [ $HAS_TRANSFILE = 1 ]; then
    TRANSDIR=$(dirname "$TRANSFILE")/.trans
    mkdir -p "$TRANSDIR"
    TRANS_PREFIX=$TRANSDIR/$TRANSFILE
    TRANSFILE_SED=$TRANS_PREFIX-sed
fi

DO_INITIAL_STAGE=0
if [ "$FORCED" = 1 -o ! -e "$INFILE_TRANS" -o "$INFILE" -nt "$INFILE_BEAU" ]; then

    touch "$INFILE_BEAU"
    # apt install node-js-beautify
    js-beautify $JS_BEAUTIFY_QUIET --file "$INFILE" --outfile "$INFILE_BEAU" >&2

    DO_INITIAL_STAGE=1

    {
	cat <<EOF
$COND,\${
# Obfuscated strings:
EOF

	base=$(dirname "$0")
	sed 's/a0_0x1993('\''\([^'\'']\+\)'\'', \?'\''\([^'\'']\+\)'\''/\n@@@\t\1\t\2\n/g' "$INFILE_BEAU" |
	    grep ^@@@ | cut -c5- | sort --key=1,3 --general-numeric-sort | uniq |
	    node "$base"/trans.js "$INFILE_BEAU"

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
# Other wierd values:
s/void 0x0/undefined/g
# Character literals: (now done by js-beautify)
# s/\x20/ /g
p
}
EOF
    } > "$INFILE_SED"
fi

function generate_discrete_translator() {
    if [ $FORCED = 1 -o "$TRANSFILE" -nt "$TRANSFILE_SED" ]; then
	sed -n '
	    1i# Manual symbol translations:
	    s/^\s+//
	    s/\s+$//
	    s/^#.*//
	    s/[(,)]\+$//
	    /./{
		s/^[^[:space:]]\+\s*$/& /
		s/^\([^[:space:]]\+\)\s\+\(.*\|$\)/s\/\\([^0-9a-zA-Z_]\\)\1\/\\1\2\/g/
		p
	    }' "$TRANSFILE" > "$TRANSFILE_SED"
	return 0
    fi
    return 1
}

# Preserve changes to the final outfile in a patch
function generate_patch() {
    if [ -e "$OUTFILE_TRANS" ]; then
	diff -u "$OUTFILE_TRANS" "$OUTFILE" > "$OUTFILE_PATCH" || true
    fi
}

function initial_stage() {
    if [ $DO_INITIAL_STAGE = 0 ]; then
	cat "$INFILE_TRANS"
	return
    fi

    # Call sed and afterwards pass perl to replace hex literals
    # with decimal literals. Finally reindent.
    sed -n -f "$INFILE_SED" "$INFILE_BEAU" |
	perl -pe 's/([^_a-zA-Z0-9])0x([0-9a-f]+)/$1.hex($2)/eg' |
	js-beautify --file - --good-stuff --unescape-strings \
		    --break-chained-methods --end-with-newline |
	tee "$INFILE_TRANS"
}

function final_stage() {
    if [ $HAS_TRANSFILE = 0 ]; then
	cat
    else
	sed -f "$TRANSFILE_SED"
    fi

    # Reapply patch to recover changes
    if [ $HAS_OUTFILE = 1 ]; then
	if [ -e "$OUTFILE_PATCH" ]; then
	    patch -b -o "$OUTFILE" "$OUTFILE_TRANS" < "$OUTFILE_PATCH" >&2
	else
	    cp -f "$OUTFILE_TRANS" "$OUTFILE"
	fi
    fi
}

if [ $HAS_TRANSFILE = 1 ]; then
    generate_discrete_translator || true
fi

if [ $HAS_OUTFILE = 1 ]; then
    generate_patch
    exec 1>&-
    exec 1>"$OUTFILE_TRANS"
fi

initial_stage | final_stage

function monitor() {
    {
	[ $HAS_TRANSFILE = 1 ] && echo $TRANSFILE
	[ $HAS_OUTFILE = 1 ] && echo $OUTFILE
    } | inotifywait --fromfile - --event MODIFY --quiet --format %w 2>&1
}

if [ $MONITOR = 1 ]; then
    while true; do
	file=$(monitor)
	echo "inotify $file" >&2
	case "$file" in
	    "$OUTFILE")
		generate_patch
		;;
	    "$TRANSFILE")
		generate_discrete_translator
		exec 1>&-
		exec 1>"$OUTFILE_TRANS"
		final_stage < "$INFILE_TRANS"
		;;
	    *)
		die "inotifywait error"
	esac
    done
fi
