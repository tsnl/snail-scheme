;; Query: the files the build must place beside the program for one bound
;; library, as the old `library-links` answers them: each file the library
;; links, once for each digest, in the order the library first names
;; them. Files with the same bytes are one file, since the payload asks
;; its host for a file by its digest. It reads Bound, the tree whose
;; LinkImports name the files: the integrator asks it once a library is
;; bound and keeps the answer with the library, whichever tree it keeps.
(define-library (snail compiler bind placed)
  (export
   Placed
   placed-files)
  (import
   (snail core base)
   (snail compiler bind language))
  (begin

    ;; A file to place: the digest the payload names it by, and where the
    ;; build found it.
    (struct Placed
      ((digest String)
       (file String)))

    (: placed-files (impl (Fn Bound -> (List Placed))))
    (define (placed-files bound)
      (delete-duplicates (lambda (placed other) (string=? (::digest placed) (::digest other)))
                         (concatenate (map top-placed (bound-tops bound)))))

    (: bound-tops (impl (Fn Bound -> (List Top))))
    (define (bound-tops bound)
      (match bound
        ((Defined _ tops _ _) tops)
        ((Program tops _ _) tops)))

    ;; A library's LinkImports are among its own tops, never inside an
    ;; InstanceScope.
    (: top-placed (impl (Fn Top -> (List Placed))))
    (define (top-placed top)
      (match top
        ((LinkImport _ _ digest file _) (list (Placed digest file)))
        (_ (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-placed)
    (import
     (snail compiler source)
     (prefix (snail compiler expand language) expanded-)
     (snail stage0 testing))
    (begin
      (define (test-placed)
        (let ((loc (Loc "a.sld" 1 1))
              (handle (lambda (serial) (expanded-Global (list "main") "link-handle" serial))))
          (expect (placed-files
                   (Program (list (LinkImport (handle 1) (list "a.txt") "aa" "a.txt" loc)
                                  (LinkImport (handle 2) (list "b.txt") "bb" "b.txt" loc)
                                  (LinkImport (handle 3) (list "copy.txt") "aa" "copy.txt" loc)
                                  (Define (expanded-Global (list "main") "x" 0)
                                    (Literal (expanded-UnitValue) loc)
                                    loc))
                            (None)
                            4))
                  (list (Placed "aa" "a.txt") (Placed "bb" "b.txt")))
          (expect (placed-files (Defined (list "a") (list) 1 loc)) (list))))))
   (else)))
