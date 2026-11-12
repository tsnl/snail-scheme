;; The text a type is written as in the running program, as the old
;; compiler writes it (`type->string`, src/snail/shell/compiler/core.sld):
;; the texts a CastError holds, which a program shows and compares, and
;; the compiler never reads back. Each Global is spelled as (snail compiler
;; names spellings) says, a type by its short spelling.
;;
;; A row's effects are written in the order of their unique names, as the
;; old compiler keeps a row's labels, which is not always the order of
;; their Globals that a Type keeps them in. A tail that is a row is
;; written as the one row they make.
(define-library (snail compiler types text)
  (export
   type-text)
  (import
   (snail core base)
   (only (snail compiler names globals) Global)
   (only (snail compiler names spellings) global-spelling short-spelling)
   (snail compiler types type))
  (begin

    ;; ---- Types ----

    (: type-text (impl (Fn Type -> String)))
    (define (type-text type)
      (match type
        ((Con global (Nil)) (short-spelling global))
        ((Con global arguments)
         (string-append "(" (short-spelling global) (types-text arguments) ")"))
        ((Callable former contract arrow)
         (string-append "("
                        (former-text former)
                        " "
                        (arrow-text (contract-text contract) arrow)
                        ")"))
        ((Code arrow) (arrow-text "fn" arrow))
        ((Row effects) (string-append "{" (row-text effects) " }"))
        ((Var variable) (variable-text variable))))

    (: types-text (impl (Fn (List Type) -> String)))
    (define (types-text types)
      (string-concatenate (map (lambda (type) (string-append " " (type-text type))) types)))

    (: former-text (impl (Fn Former -> String)))
    (define (former-text former)
      (match former
        ((Impl) "impl")
        ((Dyn) "dyn")))

    (: contract-text (impl (Fn Contract -> String)))
    (define (contract-text contract)
      (match contract
        ((FnContract) "Fn")
        ((FnMutContract) "FnMut")
        ((FnOnceContract) "FnOnce")))

    ;; `(Fn A B -> R ! e)`, or `(fn ...)` for code.
    (: arrow-text (impl (Fn String Arrow -> String)))
    (define (arrow-text kind arrow)
      (string-append "("
                     kind
                     (types-text (::parameters arrow))
                     " -> "
                     (type-text (::result arrow))
                     (row-text (::effects arrow))
                     ")"))

    ;; ` ! a b tail`, nothing for a closed row of no effect. A tail that is
    ;; a row is written as the one row they make.
    (: row-text (impl (Fn Effects -> String)))
    (define (row-text effects)
      (let* ((parts (row-parts effects (Nil)))
             (labels (labels-text (::first parts))))
        (match (::second parts)
          ((None) (if (null? (::first parts)) "" (string-append " !" labels)))
          ((Some tail) (string-append " !" labels " " (type-text tail))))))

    ;; Every label of the row and the rows its tail holds, and the tail
    ;; that is no row, if any.
    (: row-parts (impl (Fn Effects (List Global) -> (Pair (List Global) (Option Type)))))
    (define (row-parts effects labels)
      (let ((all (append labels (::labels effects))))
        (match (::tail effects)
          ((Some (Row inner)) (row-parts inner all))
          (tail (Pair all tail)))))

    ;; Each effect once, by its short name, in the order of the unique
    ;; names.
    (: labels-text (impl (Fn (List Global) -> String)))
    (define (labels-text labels)
      (string-concatenate
       (map (lambda (global) (string-append " " (short-spelling global)))
            (list-sort
             (lambda (global other) (string<? (global-spelling global) (global-spelling other)))
             (distinct-globals labels)))))

    (: distinct-globals (impl (Fn (List Global) -> (List Global))))
    (define (distinct-globals labels)
      (delete-duplicates
       (lambda (global other) (string=? (global-spelling global) (global-spelling other)))
       labels))

    ;; A variable as the old compiler names the rigid variable it is.
    (: variable-text (impl (Fn TypeVariable -> String)))
    (define (variable-text variable)
      (match variable
        ((Written name) name)
        ((Associated number label) (string-append "$associated." (i64->string number) "." label))
        ((CallableArgument number) (string-append "$callable-argument." (i64->string number)))
        ((Own inner) (string-append "$method." (variable-text inner)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-text)
    (import
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-text)
        (test-types)
        (test-rows))

      (define main (list "main"))
      (define base (list "snail" "core" "base"))

      (define (builtin name)
        (Con (Global forms-library name 0) (list)))

      (define i64 (builtin "I64"))

      (define (closed labels)
        (Effects labels (None)))

      (define log (Global main "log" 0))
      (define console (Global (list "snail" "core" "io") "console" 0))

      (define (function former contract parameters effects)
        (Callable former contract (Arrow parameters i64 effects)))

      ;; Read off `type->string` (build/dispatch-runs/old-texts.scm prints
      ;; the old texts); a serial and a name with a colon are spelled as
      ;; (snail compiler names spellings) says, where the old prints `Box%m.12` and `b`.
      (define (test-types)
        (expect (type-text i64) "I64")
        (expect (type-text (Con (Global base "List" 0) (list i64))) "(List I64)")
        (expect (type-text (Con (Global base "Pair" 0) (list i64 (builtin "String"))))
                "(Pair I64 String)")
        (expect (type-text (function (Dyn) (FnContract) (list i64 i64) (closed (list))))
                "(dyn (Fn I64 I64 -> I64))")
        (expect (type-text (function (Dyn) (FnContract) (list) (closed (list))))
                "(dyn (Fn -> I64))")
        (expect (type-text (function (Dyn) (FnMutContract) (list i64) (closed (list))))
                "(dyn (FnMut I64 -> I64))")
        (expect (type-text (function (Dyn) (FnOnceContract) (list) (closed (list))))
                "(dyn (FnOnce -> I64))")
        (expect (type-text (function (Impl) (FnContract) (list i64) (closed (list))))
                "(impl (Fn I64 -> I64))")
        (expect (type-text (function (Impl) (FnMutContract) (list i64) (closed (list))))
                "(impl (FnMut I64 -> I64))")
        (expect (type-text (Code (Arrow (list i64) i64 (closed (list))))) "(fn I64 -> I64)")
        (expect (type-text (Var (Written "a"))) "a")
        (expect (type-text (Con (Global main "Box" 12) (list))) "Box%12")
        (expect (type-text (Con (Global main "a:b" 0) (list))) "a:b"))

      ;; A row's effects in the order of their unique names, a tail after
      ;; them, and a tail that is a row as the one row they make.
      (define (test-rows)
        (let ((e (Var (Written "e"))))
          (expect (type-text (function (Dyn) (FnContract) (list i64) (closed (list console log))))
                  "(dyn (Fn I64 -> I64 ! log console))")
          (expect (type-text (function (Dyn) (FnContract) (list i64) (Effects (list) (Some e))))
                  "(dyn (Fn I64 -> I64 ! e))")
          (expect (type-text (function (Dyn) (FnContract) (list i64) (Effects (list log) (Some e))))
                  "(dyn (Fn I64 -> I64 ! log e))")
          (expect (type-text (Row (closed (list log)))) "{ ! log }")
          (expect (type-text (Row (closed (list)))) "{ }")
          (expect (type-text (Row (Effects (list log)
                                           (Some (Row (Effects (list (Global main "io" 0))
                                                               (Some e)))))))
                  "{ ! io log e }")
          (expect (type-text (Row (closed (list (Global (list "a" "b") "y" 0)
                                                (Global (list "a-c") "x" 0)))))
                  "{ ! x y }")))))
   (else)))
