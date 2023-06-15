# trans

Quick and dirty deobfuscator for JavaScript code processed with [Javascript-obfuscator](https://github.com/javascript-obfuscator/javascript-obfuscator).

```
Usage:
./trans.sh [-d] infile [cond] > outfile

        -d      Debug: display all commands (set -x).

        lines before cond will not be in the output, in order to remove
        the obfuscator's functions. cond could be a line number, or a
        regexp (including slashes: it's a sed address).
        Default: "1" (from the first line)
Example:
./trans.sh xcsim_1.3_enc.js '/^function *simulator *()/' > xcsim_1.3.js
```

The code is deobfuscated in these main steps:

- Call [js-beautify](https://github.com/beautify-web/js-beautify) to
  convert the source code from a one-liner to multi-line.
- Call trans.js, a javascript program (using node.js) that extracts
  the deobfuscating functions present within the source code itself
  and run that for every invocation within the code to obtain the
  clear-text strings that replace the invocations.
- If an &lt;infile&gt;.trans file is found, instructions are rendered
  to replace identifiers from the first column in the .trans file with
  the corresponding strings in the second column.  Hash comments and
  empty lines are ignored. Columns are separated by space-type
  characters per shell rules (one or more of SPC or TAB). This allows
  for discrete identifier replacement, since those names cannot be
  recovered automatically.
  - For convenience and to improve readability of this discrete
    translation file, the second column can be suffixed with
    parenthesys or comma (`'('`, `')'` or `','` characters). These
	characters will be ignored, but are useful to help distinguish
	between identifiers that denote either plain variable names,
	function names or parameter names. Example:

```
# A comment

_0x123abc some_variable

# Not so sure about these names:
_0xdef456 find_max(
_0xa1b2c3 param_a,
_0xd4e5f6 param_b)
_0x7a8b9c local_var

_0x0d1e2f another_var
```

- From a sed script generated by the previous two steps, execute the
  string replacements and other minor deobfuscations: deobfuscate boolean
  and integer literals, recover dot notation, put some
  comma-sepparated expressions in a one-per-line fashion and remove
  the embedded deobfuscator.
- Again call [js-beautify](https://github.com/beautify-web/js-beautify) to
  re-indent the resulting source code and decode xNN character literals.
  
Dependencies: 

- GNU bash, sed, grep, coreutils (cat, cut, sort, uniq, stat, dirname, basename)
- node.js (apt install nodejs, tested with 18.13)
- js-beautify (apt install node-js-beautify, tested with 1.14)
- perl (standard with Linux installations)

TO-DO:

- Maybe rewrite the shell/sed part in Perl, but computers are fast now.
