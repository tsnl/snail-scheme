# Reading command-line options

`(snail-scheme options)` uses one specification for parsing, validation,
defaults, and generated help:

```scheme
(option names type description [metavar])
(parse-options specification arguments [usage])
(parse-options-prefix specification arguments [usage])
(options-help specification usage)
```

A specification is a list of `option` descriptors. `names` is one string or a
list of alias strings, including their dashes. The first spelling is the result
key; all aliases update that same value. Short names have one character after
`-`, and long names begin with `--`. Names must be unique and exclude `--` and
`=`. Descriptions are strings; an optional metavar string names the operand in
help, defaulting to `VALUE`.

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
  (list (option '("--file" "-f") 'key-val-list "Read files." "FILE")
        (option '("--output" "-o") 'key-val "Write a file." "FILE")
        (option '("-v" "--verbose") 'counter "Increase verbosity.")
        (option '("-h" "--help") 'flag "Show help.")))
(define usage "usage: app [OPTIONS] [FILE ...]")
(define args (parse-options specification (cdr (command-line)) usage))

(if (args-ref args "-h")
    (display (options-help specification usage))
    (begin
      (write (args-posargs args)) (newline)
      (write (args-options args)) (newline)))
```

For `app -vvv input.scm --file a -fb --output old -onew`, the output is:

```scheme
("input.scm")
(("--file" "b" "a") ("--output" . "new") ("-v" . 3) ("-h" . #f))
```

`(args-ref args "--file")` returns `("b" "a")`; its car is the last value.
`(args-ref args "--output")` already returns the last value, `"new"`.
Counter aliases such as `-vv --verbose` add to the same count.

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
raise Scheme errors containing generated help. The optional usage string
appears before that help. Every occurrence is validated, including a missing
operand after a previous valid occurrence. Long-name abbreviations are not
supported.

`options-help` returns a string containing usage text, aliases, operand metavars,
and descriptions. Help flags are ordinary declared flags; the caller owns
display and exit. Applications also own value conversion and required
positionals. The Snail CLI uses prefix parsing to preserve script arguments.
Its `-I` option uses `key-val-list`, giving the last supplied directory priority.
The library performs no I/O.
