;; Query: what `declare` knows of (snail core forms), the library without a
;; file: its builtin types, each with how many arguments it takes. The list is
;; the old compiler's, src/snail/shell/compiler/core.sld's
;; `builtin-types`, in its order, but for `fn`, which (snail core forms)
;; offers as a keyword: `(fn ...)` is Code, never a type's name. The
;; adapter compares the two. The builtin types a rule names by their
;; Globals: String, and Vector and U8, which make Bytes. And the classes of
;; another library the compiler knows by their Globals: Drop and Clone, of
;; (snail core base), the lifecycle classes, whose instances say how a
;; value of their type is dropped and cloned; a Drop instance makes its
;; type's values moved.
(define-library (snail compiler declare forms)
  (export
   forms-library
   builtin-types
   builtin-arity
   string-type
   vector-type
   u8-type
   drop-class
   clone-class)
  (import
   (snail core base)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler outline names) same-library?)
   (only (snail compiler expand language) Global))
  (begin

    ;; ---- Builtin types ----

    (: forms-library LibraryName)
    (define forms-library
      (list "snail" "core" "forms"))

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

    ;; ---- Known types ----

    (: string-type Global)
    (define string-type
      (Global forms-library "String" 0))

    (: vector-type Global)
    (define vector-type
      (Global forms-library "Vector" 0))

    (: u8-type Global)
    (define u8-type
      (Global forms-library "U8" 0))

    ;; ---- Known classes ----

    (: drop-class Global)
    (define drop-class
      (Global (list "snail" "core" "base") "Drop" 0))

    (: clone-class Global)
    (define clone-class
      (Global (list "snail" "core" "base") "Clone" 0))

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
        (expect (builtin-arity (Global forms-library "I64" 0)) (Some 0))
        (expect (builtin-arity (Global forms-library "Vector" 0)) (Some 1))
        (expect (builtin-arity (Global forms-library "FnMut" 0)) (Some 1))
        (expect (builtin-arity (Global forms-library "fn" 0)) (None))
        (expect (builtin-arity (Global forms-library "mut" 0)) (None))
        (expect (builtin-arity (Global (list "snail" "core" "base") "I64" 0)) (None))
        (expect (length builtin-types) 16)
        (expect
         (map (lambda (global) (builtin-arity global)) (list string-type vector-type u8-type))
         (list (Some 0) (Some 1) (Some 0)))
        (expect (map ::name (list drop-class clone-class)) (list "Drop" "Clone")))))
   (else)))
