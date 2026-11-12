;; Query: the files a library links, each a `link-handle` form's names
;; relative to the file the form is written in, in the order written; and
;; when two of them are one file to the library.
(define-library (snail compiler expand links)
  (export
   Link
   linked-files
   same-link-path?)
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

    ;; Two links name one file of their library when their names are the
    ;; same, wherever each is written: the library has one handle for it.
    (: same-link-path? (impl (Fn (List String) (List String) -> Bool)))
    (define (same-link-path? path other)
      (and (= (length path) (length other))
           (every? (lambda (pair) (string=? (::first pair) (::second pair))) (zip path other))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-links)
    (import
     (only (snail compiler names globals) Global TopGlobal)
     (only (snail compiler literals constant) UnitValue)
     (snail stage0 testing))
    (begin
      (define (test-links)
        (expect (linked-files library)
                (list (Link (list "data" "x.bin") (Loc "a/t.sld" 2 3))
                      (Link (list "data" "x.bin") (Loc "a/t.sld" 2 3))))
        (expect (same-link-path? (list "data" "x.bin") (list "data" "x.bin")) #t)
        (expect (same-link-path? (list "data" "x.bin") (list "data")) #f)
        (expect (same-link-path? (list "x.bin") (list "data" "x.bin")) #f)
        (expect (same-link-path? (list "data" "x.bin") (list "data" "y.bin")) #f))

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
      ;; files of "site", twice, and whose statement calls g.
      (define library
        (Defined a
          (list (Define (global "x") (Lambda (list) (Call files (list files) loc) loc) loc)
                (InstanceScope (list)
                               (list
                                (Statement (Call (TopRef (TopGlobal (global "g")) loc) (list) loc)))
                               loc))
          1
          loc))))
   (else)))
