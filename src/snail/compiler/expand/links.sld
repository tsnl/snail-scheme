;; Query: the files a library links, each a `link-handle` form's names
;; relative to the file the form is written in, in the order written.
(define-library (snail compiler expand links)
  (export
   Link
   linked-files)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler expand language)
   (snail compiler expand subexpressions))
  (begin

    ;; A linked file's names, and where the form naming it is written.
    (struct Link
      ((path (List String))
       (written Loc)))

    (: linked-files (impl (Fn Expanded -> (List Link))))
    (define (linked-files expanded)
      (concatenate (map (lambda (expr)
                          (match expr
                            ((LinkedFile path written _) (list (Link path written)))
                            (_ (Nil))))
                        (library-expressions expanded))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-links)
    (import

     (snail stage0 testing))
    (begin
      (define (test-links)
        (expect (linked-files library)
                (list (Link (list "data" "x.bin") (Loc "a/t.sld" 2 3))
                      (Link (list "data" "x.bin") (Loc "a/t.sld" 2 3)))))

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
          loc))
      ))
   (else)))
