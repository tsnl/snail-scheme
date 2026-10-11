# Reading command-line options

`(snail-scheme options)` constructs one specification record for parsing,
validation, defaults, and generated usage and help:

```scheme
(make-args-spec declarations program [help-text])
(parse-options specification arguments)
(parse-options-prefix specification arguments)
(options-usage specification)
(options-help specification)
```

Write declarations as one quoted list. Each entry is
`(type (name ...) description [metavar])`: the type occupies the head position,
and the second field is always a nonempty list of alias strings, including
their dashes. The first spelling is the result key; all aliases update that
same value. Short names have one character after `-`, and long names begin
with `--`. Names must be unique and exclude `--` and `=`. Descriptions are
strings; an optional metavar string names the operand in usage and help,
defaulting to `VALUE`.

`make-args-spec` takes that list first, a nonempty program name string second,
and an optional longer help string third. It validates declarations and alias
uniqueness and returns an `<args-spec>` record. Configuration strings are
copied into private option records and an alias index; later mutation of the
supplied data does not change the specification. `args-spec?` tests for this
record type. Both parsers reuse it and create fresh results for each call.

Four types determine arity, defaults, and how each occurrence changes the value:

| Type | Operand | Default | Result |
| --- | --- | --- | --- |
| `flag` | None | `#f` | `#t` when present |
| `counter` | None | `0` | Count of occurrences |
| `key-val` | One string | `#f` | Last supplied value |
| `key-val-list` | One string | `()` | All supplied values, latest first |

Pass argument strings without the executable name. Both parsers return an
`<args>` record. `args-posargs` returns positionals in input order.
`args-options` returns an alist containing every declared option, in
specification order, keyed by its first alias. `args-ref` looks up a canonical
key and raises an error for an undeclared key. The library also exports
`make-args`, which takes positionals and that alist, and `args?`.

```scheme
(import (scheme base) (scheme process-context) (scheme write)
        (snail-scheme options))

(define specification
  (make-args-spec
   '((key-val-list ("--file" "-f") "Read files." "FILE")
     (key-val ("-o" "--output") "Write a file." "FILE")
     (counter ("-v" "--verbose") "Increase verbosity.")
     (flag ("-h" "--help") "Show help."))
   "app" "Read input files and write the result."))
(define args (parse-options specification (cdr (command-line))))

(if (args-ref args "-h")
    (display (options-help specification))
    (begin
      (write (args-posargs args)) (newline)
      (write (args-options args)) (newline)))
```

For `app -vvv input.scm --file a -fb --output old -onew`, the output is:

```scheme
("input.scm")
(("--file" "b" "a") ("-o" . "new") ("-v" . 3) ("-h" . #f))
```

`(args-ref args "--file")` returns `("b" "a")`; its car is the last value.
`(args-ref args "-o")` already returns the last value, `"new"`.
Counter aliases such as `-vv --verbose` add to the same count.

`options-usage` generates a concise invocation line, using each option's first
alias and adding metavars for value-taking options. Counters and repeated-value
options carry an ellipsis after their closing bracket. For this specification:

```text
usage: app [--file FILE]... [-o FILE] [-v]... [-h] [--] [ARGUMENT ...]
```

`options-help` includes that line, the optional longer help text, and each
option's complete alias list, metavar, and description. An empty declaration
list omits the Options section. Positional requirements remain the caller's
responsibility, so generated usage uses the generic `[ARGUMENT ...]` suffix.

Short options can be clustered. Zero-argument options continue through the
cluster; a value option consumes the rest of that token or the next argument.
For example, `-vvoresult.txt` counts `-v` twice and supplies `"result.txt"` to
`-o`. Long values can be attached as `--file=result.txt`. They split at the first
`=`, so `--file=a=b` supplies `"a=b"`. Empty strings are valid values.
Separate values are consumed literally, even if they resemble another option,
except for the exact delimiter `--`. Use `--file=--` to supply that string.

`parse-options` accepts options after positionals. `parse-options-prefix` stops
at the first positional and includes it and its entire literal suffix in
`args-posargs`. Both consume `--` and permanently switch to positional-only
mode. Every later token stays literal, including later `--` and option-looking
strings. A bare `-` is positional. An empty string is positional unless consumed
as an option value. The parsers do not mutate input or specification lists;
the positional suffix may remain shared with the input. Each parse creates
fresh option entries so results from separate parses remain independent.

Unknown options, missing operands, and values attached to zero-argument options
raise Scheme errors containing generated help. Every occurrence is validated,
including a missing operand after a previous valid occurrence. Long-name
abbreviations are not supported.

Help flags are ordinary declared flags; the caller owns display and exit.
Applications also own value conversion and required positionals. The Snail CLI
uses prefix parsing to preserve script arguments.
Its `-I` option uses `key-val-list`, giving the last supplied directory priority.
The library performs no I/O.
