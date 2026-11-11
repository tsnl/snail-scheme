;; Import sets: a library's import sets become the names its top level
;; imports, each meaning what the library it names exports under that
;; name. The sets are read in order, each from its library's exports up
;; through its modifiers; `only`, `except` and `rename` first check that
;; every name they list is one the set they modify gives. A name two sets
;; give must mean the same declaration, or the imports conflict. The first
;; problem stops the imports, reported as the old expander reports it: an
;; unexported name where it is written, a conflict at the set that gives
;; the second meaning.
(define-library (snail compiler expand imports)
  (export
   imported-names)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (prefix (snail compiler outline language) outline-)
   (snail compiler expand marked)
   (snail compiler expand offer)
   (snail compiler expand scopes))
  (begin

    ;; ---- Imports ----

    ;; The names `imports` give, from the offers of the libraries they
    ;; name, (snail core forms)'s among them, each bound once.
    (: imported-names
       (impl (Fn (List outline-Import) (List Offered) -> (Result Bindings (List Feedback)))))
    (define (imported-names imports offers)
      (let loop ((imports imports)
                 (bindings empty-table))
        (match imports
          ((Nil) (Ok bindings))
          ((Cons import rest)
           (result-let* ((given (set-exports offers import))
                         (added (with-imports bindings given (set-loc import))))
             (loop rest added))))))

    ;; `bindings` with each of `given` bound, in order, unless its name
    ;; already means the same.
    (: with-imports (impl (Fn Bindings (List Export) Loc -> (Result Bindings (List Feedback)))))
    (define (with-imports bindings given loc)
      (match given
        ((Nil) (Ok bindings))
        ((Cons export rest)
         (result-let* ((added (with-import bindings export loc)))
           (with-imports added rest loc)))))

    (: with-import (impl (Fn Bindings Export Loc -> (Result Bindings (List Feedback)))))
    (define (with-import bindings export loc)
      (match (table-ref bindings (::name export))
        ((Some (Cons existing _))
         (if (same-meaning? (::meaning existing) (::meaning export))
             (Ok bindings)
             (fail loc (string-append "conflicting imports of " (::name export)))))
        (_ (Ok (table-set bindings
                          (::name export)
                          (list
                           (Binding (Identifier (::name export) (Nil)) (::meaning export))))))))

    ;; ---- Import sets ----

    ;; What a set gives, in its library's order of exports. A prefixed
    ;; name is the one name made by joining text here: it is the
    ;; identifier the importer writes, and its meaning stays the export's.
    (: set-exports
       (impl (Fn (List Offered) outline-Import -> (Result (List Export) (List Feedback)))))
    (define (set-exports offers import)
      (match import
        ((outline-Whole library _) (Ok (::exports (offer-of offers library))))
        ((outline-Only inner names _)
         (result-let* ((given (checked-exports offers inner names)))
           (Ok (filter (lambda (export) (listed? names (::name export))) given))))
        ((outline-Except inner names _)
         (result-let* ((given (checked-exports offers inner names)))
           (Ok (filter (lambda (export) (not (listed? names (::name export)))) given))))
        ((outline-Prefix inner prefix _)
         (result-let* ((given (set-exports offers inner)))
           (Ok (map (lambda (export)
                      (Export (string-append prefix (::name export)) (::meaning export)))
                    given))))
        ((outline-Rename inner renamings _)
         (result-let* ((given (checked-exports offers inner (map ::identifier renamings))))
           (Ok (map (lambda (export) (renamed renamings export)) given))))))

    ;; What `inner` gives, once each of `names` is found among it.
    (: checked-exports
       (impl (Fn (List Offered) outline-Import (List outline-Identifier)
                 -> (Result (List Export) (List Feedback)))))
    (define (checked-exports offers inner names)
      (result-let* ((given (set-exports offers inner))
                    (checked (map-results (lambda (name) (exported-name given name)) names)))
        (Ok given)))

    (: exported-name
       (impl (Fn (List Export) outline-Identifier -> (Result String (List Feedback)))))
    (define (exported-name given name)
      (if (any? (lambda (export) (string=? (::name export) (::name name))) given)
          (Ok (::name name))
          (fail (::loc name)
                (string-append "import names an identifier the library does not export: "
                               (::name name)))))

    (: listed? (impl (Fn (List outline-Identifier) String -> Bool)))
    (define (listed? names name)
      (any? (lambda (listed) (string=? (::name listed) name)) names))

    ;; An export under the name the first renaming of it gives.
    (: renamed (impl (Fn (List outline-Renaming) Export -> Export)))
    (define (renamed renamings export)
      (match (find (lambda (renaming) (string=? (::name (::identifier renaming)) (::name export)))
                   renamings)
        ((Some renaming) (Export (::name renaming) (::meaning export)))
        ((None) export)))

    ;; Where a set is written: a library at its name, a modifier at its
    ;; form.
    (: set-loc (impl (Fn outline-Import -> Loc)))
    (define (set-loc import)
      (match import
        ((outline-Whole _ loc) loc)
        ((outline-Only _ _ loc) loc)
        ((outline-Except _ _ loc) loc)
        ((outline-Prefix _ _ loc) loc)
        ((outline-Rename _ _ loc) loc)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-imports)
    (import
     (snail compiler expand language)
     (snail compiler expand forms)
     (snail stage0 testing))
    (begin
      (define (test-imports)
        (test-whole)
        (test-modifiers)
        (test-unexported)
        (test-conflicts))

      ;; ---- Helpers ----

      (define a (list "a"))
      (define b (list "b"))

      (define (at column)
        (Loc "t.sld" 1 column))

      (define (value library name)
        (Value (TopGlobal (Global library name 0))))

      (define (exports-of library names)
        (map (lambda (name) (Export name (value library name))) names))

      ;; (a) exports x, y and z; (b) exports (a)'s x and a w and a y of its
      ;; own.
      (define offers
        (list (Offered forms-library forms-offer)
              (Offered a
                       (Offer (exports-of a (list "x" "y" "z")) (TopScope empty-table empty-table)))
              (Offered b
                       (Offer (append (exports-of a (list "x")) (exports-of b (list "w" "y")))
                              (TopScope empty-table empty-table)))))

      (define (whole library column)
        (outline-Whole library (at column)))

      (define (named name column)
        (outline-Identifier name (at column)))

      ;; The names imported, each with what it means, in name order.
      (define (imported imports)
        (match (imported-names imports offers)
          ((Ok bindings)
           (Ok (map (lambda (name)
                      (match (table-ref bindings name)
                        ((Some (Cons binding (Nil)))
                         (Pair name (::meaning binding)))
                        (other (panic "a name not bound once"))))
                    (list-sort string<? (table-keys bindings)))))
          ((Err feedback) (Err feedback))))

      ;; ---- Cases ----

      ;; A library gives every name it exports; (snail core forms) its
      ;; keywords, types and effects.
      (define (test-whole)
        (expect (imported (list (whole a 1)))
                (Ok
                 (list (Pair "x" (value a "x")) (Pair "y" (value a "y")) (Pair "z" (value a "z")))))
        (expect (imported (list))
                (Ok (list)))
        (match (imported-names (list (whole forms-library 1)) offers)
          ((Ok bindings)
           (expect (table-ref bindings "if")
                   (Some (list (Binding (Identifier "if" (Nil)) (Keyword "if")))))
           (expect (table-count bindings) 48))
          ((Err feedback) (expect feedback "the forms imported"))))

      ;; Each modifier acts on what the set inside it gives.
      (define (test-modifiers)
        (expect
         (imported (list (outline-Only (whole a 2) (list (named "x" 3) (named "z" 4)) (at 1))))
         (Ok (list (Pair "x" (value a "x")) (Pair "z" (value a "z")))))
        (expect (imported (list (outline-Except (whole a 2) (list (named "x" 3)) (at 1))))
                (Ok (list (Pair "y" (value a "y")) (Pair "z" (value a "z")))))
        (expect
         (imported (list (outline-Prefix (outline-Only (whole a 3) (list (named "y" 4)) (at 2))
                                         "a:"
                                         (at 1))))
         (Ok (list (Pair "a:y" (value a "y")))))
        (expect (imported (list (outline-Rename (whole a 2)
                                                (list (outline-Renaming (named "x" 3) "ex")
                                                      (outline-Renaming (named "x" 4) "other")
                                                      (outline-Renaming (named "y" 5) "why"))
                                                (at 1))))
                (Ok (list (Pair "ex" (value a "x"))
                          (Pair "why" (value a "y"))
                          (Pair "z" (value a "z")))))
        (expect (imported (list (outline-Only (outline-Prefix (whole a 3) "p" (at 2))
                                              (list (named "px" 4))
                                              (at 1))))
                (Ok (list (Pair "px" (value a "x"))))))

      ;; A name a modifier lists must be one the set inside gives, checked
      ;; once that set is read, in the order the names are written.
      (define (test-unexported)
        (define (unexported column name)
          (fail (at column)
                (string-append "import names an identifier the library does not export: " name)))
        (expect
         (imported (list (outline-Only (whole a 2) (list (named "x" 3) (named "q" 4) (named "r" 5))
                                       (at 1))))
         (unexported 4 "q"))
        (expect (imported (list (outline-Except (whole a 2) (list (named "w" 3)) (at 1))))
                (unexported 3 "w"))
        (expect (imported (list (outline-Rename (whole a 2)
                                                (list (outline-Renaming (named "w" 3) "v"))
                                                (at 1))))
                (unexported 3 "w"))
        (expect (imported (list (outline-Only (outline-Only (whole a 3) (list (named "q" 4)) (at 2))
                                              (list (named "r" 5))
                                              (at 1))))
                (unexported 4 "q"))
        (expect (imported (list (outline-Only (outline-Prefix (whole a 3) "p" (at 2))
                                              (list (named "x" 4))
                                              (at 1))))
                (unexported 4 "x")))

      ;; Two sets may give a name that means one declaration, as (a) and
      ;; (b) both give (a)'s x; one that means two is a conflict, reported
      ;; at the later set.
      (define (test-conflicts)
        (expect (imported (list (whole a 1) (whole b 2)))
                (fail (at 2) "conflicting imports of y"))
        (expect
         (imported (list (whole a 1) (outline-Except (whole b 3) (list (named "y" 4)) (at 2))))
         (Ok (list (Pair "w" (value b "w"))
                   (Pair "x" (value a "x"))
                   (Pair "y" (value a "y"))
                   (Pair "z" (value a "z")))))
        (expect (imported (list (whole a 1) (outline-Rename (whole b 3)
                                                            (list
                                                             (outline-Renaming (named "w" 4) "z"))
                                                            (at 2))))
                (fail (at 2) "conflicting imports of z"))
        (expect (imported (list (whole b 1) (outline-Prefix (whole b 3) "" (at 2))))
                (Ok (list (Pair "w" (value b "w"))
                          (Pair "x" (value a "x"))
                          (Pair "y" (value b "y"))))))))
   (else)))
