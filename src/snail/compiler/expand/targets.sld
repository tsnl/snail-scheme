;; Query: the targets a library asks for, each the target an
;; `artifact-files` form names, in the order written, once each, at the
;; first form that names it.
(define-library (snail compiler expand targets)
  (export
   TargetRequest
   requested-targets)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler expand language)
   (snail compiler expand subexpressions))
  (begin

    ;; A target a library asks for the files of, where it first asks.
    (struct TargetRequest
      ((target String)
       (loc Loc)))

    (: requested-targets (impl (Fn Expanded -> (List TargetRequest))))
    (define (requested-targets expanded)
      (delete-duplicates (lambda (request other) (string=? (::target request) (::target other)))
                         (concatenate (map (lambda (expr)
                                             (match expr
                                               ((ArtifactFiles target _ _ _ loc)
                                                (list (TargetRequest target loc)))
                                               (_ (Nil))))
                                           (library-expressions expanded)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-targets)
    (import
     (only (snail compiler names globals) Global TopGlobal)
     (only (snail compiler literals constant) UnitValue)
     (snail stage0 testing))
    (begin
      (define (test-targets)
        (expect (requested-targets library)
                (list (TargetRequest "site" (Loc "t.sld" 2 1))
                      (TargetRequest "docs" (Loc "t.sld" 4 1)))))

      (define loc (Loc "t.sld" 1 1))

      (define a (list "a"))

      (define (global name)
        (Global a name 0))

      (define link (LinkedFile (list "data" "x.bin") (Loc "a/t.sld" 2 3) loc))

      (define (files target at)
        (ArtifactFiles target
                       (TopRef (TopGlobal (global "f")) loc)
                       link
                       (Literal (UnitValue) loc)
                       at))

      ;; A library whose definition asks for the files of "site" twice,
      ;; then for those of "docs", and whose statement asks for "site"
      ;; again.
      (define library
        (Defined a
          (list (Define (global "x")
                  (Lambda (list)
                          (Call (files "site" (Loc "t.sld" 2 1))
                                (list (files "site" (Loc "t.sld" 3 1))
                                      (files "docs" (Loc "t.sld" 4 1)))
                                loc)
                          loc)
                  loc)
                (InstanceScope (list) (list (Statement (files "site" (Loc "t.sld" 5 1)))) loc))
          1
          loc))))
   (else)))
