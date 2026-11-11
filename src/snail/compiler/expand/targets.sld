;; Query: the targets a library asks for, each the target an
;; `artifact-files` form names, in the order written, once each.
(define-library (snail compiler expand targets)
  (export
   requested-targets)
  (import
   (snail core base)
   (snail compiler expand language)
   (snail compiler expand subexpressions))
  (begin

    (: requested-targets (impl (Fn Expanded -> (List String))))
    (define (requested-targets expanded)
      (delete-duplicates string=?
                         (concatenate (map (lambda (expr)
                                             (match expr
                                               ((ArtifactFiles target _ _ _ _) (list target))
                                               (_ (Nil))))
                                           (library-expressions expanded)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-targets)
    (import
     (snail compiler source)
     (snail stage0 testing))
    (begin
      (define (test-targets)
        (expect (requested-targets library) (list "site")))

      (define loc (Loc "t.sld" 1 1))

      (define a (list "a"))

      (define (global name)
        (Global a name 0))


      (define link (LinkedFile (list "data" "x.bin") (Loc "a/t.sld" 2 3) loc))

      (define files
        (ArtifactFiles "site"
                       (TopRef (TopGlobal (global "f")) loc)
                       link
                       (Literal (UnitValue) loc)
                       loc))

      ;; A library whose definition links a file inside a request for the
      ;; files of "site", twice, and whose program body asks again.
      (define library
        (Defined a
          (list (Define (global "x") (Lambda (list) (Call files (list files) loc) loc) loc)
                (InstanceScope (list)
                               (list
                                (Statement (Call (TopRef (TopGlobal (global "g")) loc) (list) loc)))
                               loc))
          1
          loc))
      ))
   (else)))
