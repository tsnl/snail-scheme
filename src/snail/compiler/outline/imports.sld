;; Query: the libraries an outline imports, which the integrator loads
;; before it. Each is at its import set, where a library that cannot be
;; found, or that leads back to one still loading, is reported.
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

    ;; A library an import set names, under its modifiers, and where the
    ;; whole set is written.
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
      (Imported (modified-library import) (import-loc import)))

    (: modified-library (impl (Fn Import -> LibraryName)))
    (define (modified-library import)
      (match import
        ((Whole library _) library)
        ((Only inner _ _) (modified-library inner))
        ((Except inner _ _) (modified-library inner))
        ((Prefix inner _ _) (modified-library inner))
        ((Rename inner _ _) (modified-library inner))))

    (: import-loc (impl (Fn Import -> Loc)))
    (define (import-loc import)
      (match import
        ((Whole _ loc) loc)
        ((Only _ _ loc) loc)
        ((Except _ _ loc) loc)
        ((Prefix _ _ loc) loc)
        ((Rename _ _ loc) loc)))

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
                  (list (Imported (list "b" "c") (at 9)) (Imported (list "a") (at 1))))
          (expect (imported-libraries (Defined (list "d") imports (list) (list) (at 7)))
                  (list (Imported (list "b" "c") (at 9)) (Imported (list "a") (at 1))))
          (expect (imported-libraries (Defined (list "d") (list) (list) (list) (at 7))) (list))
          (expect (imported-libraries (Generated (list "g") (list) (Ident "e" (at 8)) (at 7)))
                  (list))))))
   (else)))
