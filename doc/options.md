# Reading command-line options

`(snail-scheme options)` exports one procedure:

```scheme
(parse-options declarations arguments [usage])
```

Pass an association list of literal option names and whether they require a
value: `#t` for one string operand, `#f` for a switch. Short names have one
character after `-`; long names begin with `--`. Declarations must have unique
names, exclude `--` and `=`, and use boolean values.

Pass argument strings without the executable name. The optional usage string
is included in errors. The procedure returns two values: option occurrences
as `(name . value)` pairs in input order, and the untouched positional suffix.
A switch's value is `#t`. Every occurrence is retained, including repetitions.

```scheme
(import (scheme base) (scheme process-context) (scheme write)
        (snail-scheme options))

(define declarations '(("-o" . #t) ("--verbose" . #f)))

(let-values (((options files)
              (parse-options declarations (cdr (command-line))
                             "usage: app [-o OUTPUT] [--verbose] FILE ...")))
  (write options) (newline)
  (write files) (newline))
```

`app --verbose -oresult.txt input.scm` returns
`(("--verbose" . #t) ("-o" . "result.txt"))` and `("input.scm")`.

Value options accept a separate operand, attached short operands such as
`-oresult.txt`, and long operands such as `--output=result.txt`. A long option
splits at its first `=`, so `--output=a=b` has value `"a=b"`.
Empty operands are valid. Separate operands are consumed literally, even when
they are `--` or begin with `-`.

Parsing stops at the first positional string or at `--`. The delimiter is
consumed; everything after it is positional. An empty string is positional.
Use `--` before positional strings beginning with `-`, including a bare `-`.
Unknown options, missing operands, and operands attached to switches raise
Scheme errors. Short switches use separate tokens: `-v -q`.

Applications own aliases, defaults, conversion, required arguments, and repetition
policy. Declare aliases separately and interpret them in application code.
The Snail CLI declares `-I` and reverses its collected directory values to give
the last supplied directory priority. The library performs no I/O or execution.
