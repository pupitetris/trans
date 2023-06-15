#!/bin/bash

# Convert from Chrome's "Copy all as cURL" output to a working dump
# script that is easy to filter and run.

INPUT=${1:--}

sed 's/^curl \('\''https\?:\/\/[^\/]\+\/\)\([^'\'']\+\)'\''/[ -e '\''\2'\'' ] || ( mkdir -p $(dirname '\''\2'\''); curl \1\2'\'' -o '\''\2'\''/;
: start
N
s/\s\+\\\n\s\+\+/ /
T
s/--compressed *;\?$/--compressed )/
t
b start
' "$INPUT"

