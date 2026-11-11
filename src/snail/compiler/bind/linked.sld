;; Query: the file each link of a library names, beside the file the link
;; is written in; but a link written in a producer program's printed copy
;; names a file beside the recipe the copy stands for, so a recipe names
;; files beside itself wherever its producer is printed. The integrator
;; reads the files this answers and `bind` looks their digests up by the
;; same answer, so the files read are the files looked up.
(define-library (snail compiler bind linked)
  (export
   linked-file
   named-files)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler expand language) Expanded)
   (snail compiler expand links)
   (snail compiler bind supply))
  (begin

    (: linked-file (impl (Fn (Option PrintedCopy) Link -> String)))
    (define (linked-file printed link)
      (beside (written-in printed (::written link)) (string-join (::path link) "/")))

    (: written-in (impl (Fn (Option PrintedCopy) Loc -> String)))
    (define (written-in printed loc)
      (match printed
        ((Some copy) (if (string=? (::file loc) (::copy copy)) (::recipe copy) (::file loc)))
        ((None) (::file loc))))

    ;; Each file the library's links name, once, in the order first named.
    (: named-files (impl (Fn (Option PrintedCopy) Expanded -> (List String))))
    (define (named-files printed expanded)
      (delete-duplicates string=?
                         (map (lambda (link) (linked-file printed link)) (linked-files expanded))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-linked)
    (import
     (snail compiler expand language)
     (snail stage0 testing))
    (begin
      (define (test-linked)
        (let ((printed (Some (PrintedCopy "build/p.sld" "lib/r.sld"))))
          (expect (linked-file (None) (link (list "d" "x.bin") "lib/main.sld"))
                  "lib/d/x.bin")
          (expect (linked-file printed (link (list "x.bin") "build/p.sld")) "lib/x.bin")
          (expect (linked-file printed (link (list "x.bin") "other/m.sld")) "other/x.bin")
          (expect (named-files (None) library) (list "lib/x.bin" "other/x.bin"))))

      (define (link path file)
        (Link path (Loc file 1 1)))

      (define loc (Loc "lib/main.sld" 1 1))

      (define (linked path file)
        (LinkedFile path (Loc file 1 1) loc))

      ;; A library that links lib/x.bin twice and other/x.bin once.
      (define library
        (Program (list (Statement (linked (list "x.bin") "lib/main.sld"))
                       (Statement (linked (list "x.bin") "other/m.sld"))
                       (Statement (linked (list "x.bin") "lib/main.sld")))
                 (None)
                 1))))
   (else)))
