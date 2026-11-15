; Colors as (snail shell highlight) classifies text, with Zed's capture
; names. A keyword is one wherever it appears; tests/tree-sitter.mjs checks
; that this list is that library's `keywords`, which begin with the
; compiler's core forms. Patterns overlap only where they agree, so their
; order does not matter.

(line_comment) @comment
(block_comment) @comment
(datum_comment) @comment

(string) @string
(character) @string.special
(number) @number
(boolean) @boolean

["(" ")" "[" "]" "#u8("] @punctuation.bracket
"'" @punctuation.special

((symbol) @keyword
  (#any-of? @keyword
    "define" "lambda" "if" "begin" "let" "define-syntax" "syntax-rules" "quote"
    "declare" "record" "new" "enum" "type" "typeclass" "instance" "match" "●"
    "ann" "extern" "primitive" "effect" "handle" "expose" "case-id" "downcast"
    "artifact-files" "link-handle"
    "let*" "letrec" "cond" "case" "when" "unless" "and" "or" "do" "else"
    "define-library" "import" "export" "only" "except" "prefix" "rename"
    "cond-expand" "ctl" "∀" "⊨" "deriving" "host" "→" "!"
    "define-page-state" "define-record-type" "guard"))

; A type's name starts with a capital letter.
((symbol) @type
  (#match? @type "^[A-Z]"))

; The name a definition introduces, after `define`, `define-syntax` or
; `declare`, alone or at the head of the list that follows. The form's
; name is captured as the keyword it is, so this pattern and the keywords'
; agree on it.
(list
  .
  (symbol) @keyword
  .
  [
    ((symbol) @function (#not-match? @function "^[A-Z]"))
    (list . ((symbol) @function (#not-match? @function "^[A-Z]")))
  ]
  (#any-of? @keyword "define" "define-syntax" "declare"))
