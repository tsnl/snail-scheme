;; Query: the libraries an outline imports, which the integrator loads
;; before it. Each is where its name is written, which is where a library
;; that cannot be found, or that leads back to one still loading, is
;; reported, as the old expander reports it.
(define-library (snail compiler outline imports)
  (export
   Imported
   imported-libraries)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler outline language))
  (begin

    ;; ---- Imported libraries ----

    ;; A library an import set names, under its modifiers, and where its
    ;; name is written.
    (struct Imported
      ((library LibraryName)
       (loc Loc)))

    ;; One for each import set, in the order written. A generated library
    ;; imports nothing itself: its recipe's imports are its producer
    ;; program's, which is outlined in turn.
    (: imported-libraries (impl (Fn Outline -> (List Imported))))
    (define (imported-libraries outline)
      (match outline
        ((Defined _ imports _ _ _) (map imported imports))
        ((Generated _ _ _ _) (Nil))
        ((Program _ _ imports _) (map imported imports))))

    (: imported (impl (Fn Import -> Imported)))
    (define (imported import)
      (match import
        ((Whole library loc) (Imported library loc))
        ((Only inner _ _) (imported inner))
        ((Except inner _ _) (imported inner))
        ((Prefix inner _ _) (imported inner))
        ((Rename inner _ _) (imported inner))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-imports)
    (import
     (only (snail compiler read language) Ident)
     (snail stage0 testing))
    (begin
      (define (test-imports)
        (define (at column)
          (Loc "t.sld" 1 column))
        (let* ((a (Whole (list "a") (at 2)))
               (modified (Rename (Prefix (Except (Only a (list) (at 5)) (list) (at 4)) "p" (at 3))
                                 (list)
                                 (at 1)))
               (imports (list (Whole (list "b" "c") (at 9)) modified)))
          (expect (imported-libraries (Program (list) (None) imports (list)))
                  (list (Imported (list "b" "c") (at 9)) (Imported (list "a") (at 2))))
          (expect (imported-libraries (Defined (list "d") imports (list) (list) (at 7)))
                  (list (Imported (list "b" "c") (at 9)) (Imported (list "a") (at 2))))
          (expect (imported-libraries (Defined (list "d") (list) (list) (list) (at 7))) (list))
          (expect (imported-libraries (Generated (list "g") (list) (Ident "e" (at 8)) (at 7)))
                  (list))))))
   (else)))
