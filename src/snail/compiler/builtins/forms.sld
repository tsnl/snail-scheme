;; What the compiler knows by name of (snail core forms), the one library
;; without a file: the keywords of the core forms; its builtin types, each
;; with how many arguments it takes; and its builtin effects, which no
;; handler implements: `mut`, which the compiler itself performs, and
;; `host`, the effect of code that may run anything the host implements.
;; The lists are the old compiler's, src/snail/shell/compiler/core.sld's
;; `core-keywords`, `builtin-types` and builtin effects, in its order, but
;; that `fn` is a keyword and no type: `(fn ...)` is Code, never a type's
;; name. The adapter compares them. `expand` offers each under its name,
;; and `declare` checks a type's arguments by its arity. A rule names some
;; builtins by their Globals: String, and Vector and U8, which make Bytes;
;; Any, the type every erased value has; Unit and I32; and the effect
;; `mut`. The types they name are (snail compiler types builtins)'s.
(define-library (snail compiler builtins forms)
  (export
   keywords
   builtin-types
   builtin-arity
   builtin-effects
   any-global
   string-global
   vector-global
   u8-global
   unit-global
   i32-global
   mut-global)
  (import
   (snail core base)
   (snail compiler names libraries)
   (only (snail compiler names globals) Global))
  (begin

    ;; ---- Keywords ----

    (: keywords (List String))
    (define keywords
      (list "define"
            "lambda"
            "fn"
            "if"
            "begin"
            "let"
            "define-syntax"
            "syntax-rules"
            "quote"
            ":"
            "struct"
            "enum"
            "type"
            "typeclass"
            "instance"
            "define-instance-set"
            "with-instances"
            "match"
            "ann"
            "extern"
            "primitive"
            "effect"
            "handle"
            "expose"
            "case-id"
            "type-convert"
            "try-convert"
            "type-test"
            "artifact-files"
            "link-handle"))

    ;; ---- Builtin types ----

    ;; Each builtin type's name, and how many arguments it takes.
    (: builtin-types (List (Pair String I64)))
    (define builtin-types
      (list (Pair "Any" 0)
            (Pair "Borrow" 1)
            (Pair "Funcref" 0)
            (Pair "U8" 0)
            (Pair "I32" 0)
            (Pair "I64" 0)
            (Pair "F32" 0)
            (Pair "F64" 0)
            (Pair "Bool" 0)
            (Pair "Char" 0)
            (Pair "Unit" 0)
            (Pair "String" 0)
            (Pair "Array" 1)
            (Pair "Vector" 1)
            (Pair "FnOnce" 1)
            (Pair "FnMut" 1)))

    ;; How many arguments a builtin type takes, or None for a Global that
    ;; is no builtin type.
    (: builtin-arity (impl (Fn Global -> (Option I64))))
    (define (builtin-arity global)
      (if (and (same-library? (::library global) forms-library) (= (::serial global) 0))
          (match (find (lambda (entry) (string=? (::first entry) (::name global))) builtin-types)
            ((Some entry) (Some (::second entry)))
            ((None) (None)))
          (None)))

    ;; ---- Builtin effects ----

    (: builtin-effects (List String))
    (define builtin-effects
      (list "mut" "host"))

    ;; ---- Builtins by name ----

    (: any-global Global)
    (define any-global
      (Global forms-library "Any" 0))

    (: string-global Global)
    (define string-global
      (Global forms-library "String" 0))

    (: vector-global Global)
    (define vector-global
      (Global forms-library "Vector" 0))

    (: u8-global Global)
    (define u8-global
      (Global forms-library "U8" 0))

    (: unit-global Global)
    (define unit-global
      (Global forms-library "Unit" 0))

    (: i32-global Global)
    (define i32-global
      (Global forms-library "I32" 0))

    (: mut-global Global)
    (define mut-global
      (Global forms-library "mut" 0))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-forms)
    (import
     (snail stage0 testing))
    (begin
      (define (test-forms)
        (test-arities)
        (test-names))

      (define (test-arities)
        (expect (builtin-arity (Global forms-library "I64" 0)) (Some 0))
        (expect (builtin-arity (Global forms-library "Vector" 0)) (Some 1))
        (expect (builtin-arity (Global forms-library "FnMut" 0)) (Some 1))
        (expect (builtin-arity (Global forms-library "fn" 0)) (None))
        (expect (builtin-arity (Global (list "snail" "core" "base") "I64" 0)) (None))
        (expect (map (lambda (global) (builtin-arity global))
                     (list any-global string-global vector-global u8-global unit-global i32-global))
                (list (Some 0) (Some 0) (Some 1) (Some 0) (Some 0) (Some 0)))
        (expect (builtin-arity mut-global) (None)))

      ;; Each name once: thirty keywords, sixteen types and two effects.
      (define (test-names)
        (let ((names (append keywords (append (map ::first builtin-types) builtin-effects))))
          (expect (map length (list keywords builtin-types builtin-effects)) (list 30 16 2))
          (expect (list-ref keywords 0) "define")
          (expect (list-ref keywords 29) "link-handle")
          (expect (length (delete-duplicates string=? names)) 48)))))
   (else)))
