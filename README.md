# trans

Quick and dirty deobfuscator for JavaScript code processed with [Javascript-obfuscator](https://github.com/javascript-obfuscator/javascript-obfuscator).

```
Usage:
trans.sh [-h] [{-|+}D] [-C=configfile] [{-|+}F] -i=infile
        [-c=[cond]] [-t=transfile [-o=[outfile]] [{-|+}M]]

        Arguments may be given in any order, any number of times.

        -h      Display this help text and exit.

        -C      Specify a config file which is just a shell file that
                is sourced to set internal variables that represent
                command-line switches:

                DEBUG=0|1
                PS4=string       Set the debugging prefix string
                                 Default: "$0 \$LINENO: "
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
trans.sh -i=xcsim_1.3_enc.js -c='/^function *simulator *()/' -o=xcsim_1.3.js
```

The code is deobfuscated in these main steps:

- Call [js-beautify](https://github.com/beautify-web/js-beautify) to
  convert the source code from a one-liner to multi-line.
- Call trans.js, a javascript program (using node.js) that extracts
  the deobfuscating functions present within the source code itself
  and run that for every invocation within the code to obtain the
  clear-text strings that replace the invocations.
- If a transfile is specified, instructions are rendered to replace
  identifiers from the first column in the .trans file with the
  corresponding strings in the second column.  Hash comments and empty
  lines are ignored. Columns are separated by space-type characters
  per shell rules (one or more of SPC or TAB). This allows for
  discrete identifier replacement, since those names cannot be
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
- If an outfile was specified, apply auto-generated patch to preserve any
  changes made in the outfile (rejects due to conflicts may have to be
  resolved by the user).

## Dependencies:

- GNU bash, sed, grep, patch, diffutils, coreutils (cat, cut, sort, uniq, dirname)
- node.js (apt install nodejs, tested with 18.13)
- js-beautify (apt install node-js-beautify, tested with 1.14)
- perl (standard with Linux installations)
- inotifywait (apt install inotify-tools, optional if you want automatic reprocessing)

## TO-DO:

- Maybe rewrite the shell/sed part in Perl, but computers are fast now.
