;; Query: the texts the code `dispatch` writes puts into the running
;; program, which a program reads from the CastError a failed dispatch
;; raises: each type it expected as the old compiler writes a type
;; (`type->string`, src/snail/shell/compiler/core.sld), the place as it
;; writes a Loc (`loc->string`, src/snail/shell/compiler/read.sld), and the
;; method as its unique name.
;;
;; This query builds texts from names, which no decision may do. These
;; texts are display, as a message is: the running program shows them and
;; compares them, and the compiler never reads one back. A Global is
;; spelled as the old compiler's unique name: its library's parts joined
;; by dots, a colon and its name; a builtin of (snail core forms) by its
;; name alone. A type is spelled by its short name, the name alone. A
;; Global a macro's template wrote has a serial of its own, and the old
;; name holds the stamp of the macro's use, which no new pass has, so it is
;; spelled `name%serial`, as (snail compiler declare identities) spells it
;; in a TypeId's schema. The old short name is the text after the last
;; colon of the unique name; a name is data here, so a name that holds a
;; colon is spelled whole.
;;
;; A row's effects are written in the order of their unique names, as the
;; old compiler keeps a row's labels, which is not always the order of
;; their Globals that Declared keeps them in.
(define-library (snail compiler dispatch text)
  (export
   global-text
   type-text
   place-text
   member-text)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler outline names) same-library? library-key)
   (only (snail compiler expand language)
         Global
         Former
         Impl
         Dyn
         Contract
         FnContract
         FnMutContract
         FnOnceContract)
   (only (snail compiler declare language)
         Type
         Con
         Callable
         Code
         Row
         Var
         Arrow
         Effects
         TypeVariable
         Written
         Associated
         CallableArgument
         Own
         Member
         ClassMethod
         FieldReader)
   (only (snail compiler declare forms) forms-library))
  (begin

    ;; ---- Names ----

    ;; A Global as the old compiler's unique name spells it.
    (: global-text (impl (Fn Global -> String)))
    (define (global-text global)
      (if (and (same-library? (::library global) forms-library) (= (::serial global) 0))
          (::name global)
          (string-append (library-key (::library global)) ":" (short-text global))))

    ;; A Global by its name within its library.
    (: short-text (impl (Fn Global -> String)))
    (define (short-text global)
      (if (= (::serial global) 0)
          (::name global)
          (string-append (::name global) "%" (i64->string (::serial global)))))

    ;; The method a dispatched call names: a class's method by its unique
    ;; name, or a field class's reader by its label's path.
    (: member-text (impl (Fn Member -> String)))
    (define (member-text member)
      (match member
        ((ClassMethod global) (global-text global))
        ((FieldReader label) (string-append "::" label))))

    ;; ---- Places ----

    ;; A place in line 0 is its file as a whole.
    (: place-text (impl (Fn Loc -> String)))
    (define (place-text loc)
      (if (= (::line loc) 0)
          (::file loc)
          (string-append (::file loc)
                         ":"
                         (i64->string (::line loc))
                         ":"
                         (i64->string (::column loc)))))

    ;; ---- Types ----

    (: type-text (impl (Fn Type -> String)))
    (define (type-text type)
      (match type
        ((Con global (Nil)) (short-text global))
        ((Con global arguments)
         (string-append "(" (short-text global) (types-text arguments) ")"))
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
       (map (lambda (global) (string-append " " (short-text global)))
            (list-sort (lambda (global other) (string<? (global-text global) (global-text other)))
                       (distinct-globals labels)))))

    (: distinct-globals (impl (Fn (List Global) -> (List Global))))
    (define (distinct-globals labels)
      (delete-duplicates (lambda (global other) (string=? (global-text global) (global-text other)))
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
     (snail stage0 testing))
    (begin
      (define (test-text)
        (test-names)
        (test-places)
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

      ;; A unique name, a builtin's name alone, and a serial's spelling; a
      ;; field class's reader by its path.
      (define (test-names)
        (expect (global-text (Global base "+" 0)) "snail.core.base:+")
        (expect (global-text (Global forms-library "I64" 0)) "I64")
        (expect (global-text (Global main "combine" 4)) "main:combine%4")
        (expect (member-text (ClassMethod (Global main "combine" 0))) "main:combine")
        (expect (member-text (FieldReader "x")) "::x"))

      ;; Read off `loc->string`.
      (define (test-places)
        (expect (place-text (Loc "t.sld" 3 7)) "t.sld:3:7")
        (expect (place-text (Loc "t.sld" 0 0)) "t.sld"))

      ;; Read off `type->string` (build/dispatch-runs/old-texts.scm prints
      ;; the old texts); a serial and a name with a colon are spelled as
      ;; this query says, where the old prints `Box%m.12` and `b`.
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
