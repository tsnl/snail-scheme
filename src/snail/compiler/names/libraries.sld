;; What a library's name is, as every pass holds it: its parts in order,
;; `(snail core base)` being ("snail" "core" "base"), with an integer part
;; as its decimal text. Two names are the same library when their parts
;; are; names are ordered part by part; a name is written as its parts in
;; parentheses; and the old compiler knows a library by its parts joined
;; with dots, in its keys and messages.
;;
;; Some libraries the compiler names itself. Three have no file. A
;; program is no library, but its Globals need one, so every pass names
;; them of ("main"), as the old compiler names a program's definitions
;; `main:name`. (snail core forms) holds the core forms and builtins,
;; which (snail compiler builtins forms) lists. And ("prim") holds the
;; compiler's primitives, which (snail core primitive), a library with a
;; file, declares, and which no other library's forms can. Of the others,
;; (snail core base) holds what the compiler treats specially, which
;; (snail compiler builtins base) names.
(define-library (snail compiler names libraries)
  (export
   LibraryName
   same-library?
   library<?
   library-key
   written-name
   program-library
   forms-library
   prim-library
   primitive-library
   base-library)
  (import
   (snail core base))
  (begin

    ;; ---- Names ----

    (type LibraryName (List String))

    (: same-library? (impl (Fn LibraryName LibraryName -> Bool)))
    (define (same-library? name other)
      (match name
        ((Nil) (null? other))
        ((Cons part rest)
         (match other
           ((Cons other-part other-rest)
            (and (string=? part other-part) (same-library? rest other-rest)))
           ((Nil) #f)))))

    ;; Libraries in order: their parts compared in turn, a name before any
    ;; longer name it begins.
    (: library<? (impl (Fn LibraryName LibraryName -> Bool)))
    (define (library<? name other)
      (match (Pair name other)
        ((Pair (Nil) (Nil)) #f)
        ((Pair (Nil) _) #t)
        ((Pair _ (Nil)) #f)
        ((Pair (Cons part rest) (Cons other-part other-rest))
         (cond ((string<? part other-part) #t)
               ((string<? other-part part) #f)
               (else (library<? rest other-rest))))))

    ;; `(snail core base)` is "snail.core.base". The dotted text names no
    ;; library uniquely, since (a.b) and (a b) share it, so no decision
    ;; reads it but the comparison with the keys an old producer prints.
    (: library-key (impl (Fn LibraryName -> String)))
    (define (library-key name)
      (string-join name "."))

    ;; `(snail core base)` is "(snail core base)".
    (: written-name (impl (Fn LibraryName -> String)))
    (define (written-name name)
      (string-append "(" (string-join name " ") ")"))

    ;; ---- Libraries without a file ----

    ;; The library a program's Globals are of.
    (: program-library LibraryName)
    (define program-library
      (list "main"))

    (: forms-library LibraryName)
    (define forms-library
      (list "snail" "core" "forms"))

    ;; The library of the primitives' Globals, which no file may be found
    ;; as.
    (: prim-library LibraryName)
    (define prim-library
      (list "prim"))

    ;; ---- Libraries with a file ----

    ;; The library whose forms each declare a primitive, a Global of
    ;; ("prim"), and which `expand` reads as nothing else.
    (: primitive-library LibraryName)
    (define primitive-library
      (list "snail" "core" "primitive"))

    (: base-library LibraryName)
    (define base-library
      (list "snail" "core" "base"))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-libraries)
    (import
     (snail stage0 testing))
    (begin
      (define (test-libraries)
        (test-same)
        (test-order)
        (test-texts))

      (define (test-same)
        (expect (same-library? (list "a" "b") (list "a" "b")) #t)
        (expect (same-library? (list) (list)) #t)
        (expect (same-library? (list "a" "b") (list "a")) #f)
        (expect (same-library? (list "a") (list "a" "b")) #f)
        (expect (same-library? (list "a" "b") (list "a" "c")) #f)
        (expect (same-library? (list "a.b") (list "a" "b")) #f))

      ;; Part by part; a name before any longer one it begins.
      (define (test-order)
        (expect (library<? (list "a") (list "b")) #t)
        (expect (library<? (list "a") (list "a" "b")) #t)
        (expect (library<? (list "a" "b") (list "a")) #f)
        (expect (library<? (list "a" "b") (list "a" "c")) #t)
        (expect (library<? (list "a") (list "a")) #f)
        (expect (library<? (list) (list)) #f))

      (define (test-texts)
        (expect (library-key (list "snail" "core" "base")) "snail.core.base")
        (expect (library-key (list "a.b")) (library-key (list "a" "b")))
        (expect (library-key (list)) "")
        (expect (library-key program-library) "main")
        (expect (written-name (list "sample" "1")) "(sample 1)")
        (expect (written-name (list)) "()")
        (expect (written-name forms-library) "(snail core forms)"))))
   (else)))
