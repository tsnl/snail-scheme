;; Query: what is true of a library's name, which the Outline language
;; holds as its parts. Two names are the same library when their parts
;; are; a name is written as its parts in parentheses; and the old
;; compiler knows a library by its parts joined with dots, in its keys
;; and messages.
(define-library (snail compiler outline names)
  (export
   same-library?
   library-key
   written-name)
  (import
   (snail core base)
   (snail compiler outline language))
  (begin

    ;; ---- Names ----

    (: same-library? (impl (Fn LibraryName LibraryName -> Bool)))
    (define (same-library? name other)
      (match name
        ((Nil) (null? other))
        ((Cons part rest)
         (match other
           ((Cons other-part other-rest)
            (and (string=? part other-part) (same-library? rest other-rest)))
           ((Nil) #f)))))

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

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-names)
    (import
     (snail stage0 testing))
    (begin
      (define (test-names)
        (expect (same-library? (list "a" "b") (list "a" "b")) #t)
        (expect (same-library? (list) (list)) #t)
        (expect (same-library? (list "a" "b") (list "a")) #f)
        (expect (same-library? (list "a") (list "a" "b")) #f)
        (expect (same-library? (list "a" "b") (list "a" "c")) #f)
        (expect (same-library? (list "a.b") (list "a" "b")) #f)
        (expect (library-key (list "snail" "core" "base")) "snail.core.base")
        (expect (library-key (list "a.b")) (library-key (list "a" "b")))
        (expect (library-key (list)) "")
        (expect (written-name (list "sample" "1")) "(sample 1)")
        (expect (written-name (list)) "()"))))
   (else)))
