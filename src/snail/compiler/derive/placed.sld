;; Query: the files the build must place beside the program for one
;; derived library, as the old `library-links` answers them: each file the
;; library links, once for each digest, in the order the library first
;; names them. Files with the same bytes are one file, since the payload
;; asks its host for a file by its digest. It reads Derived, the latest
;; tree the integrator keeps of a library, whose LinkImports are Bound's.
(define-library (snail compiler derive placed)
  (export
   Placed
   placed-files)
  (import
   (snail core base)
   (snail compiler derive language))
  (begin

    ;; A file to place: the digest the payload names it by, and where the
    ;; build found it.
    (struct Placed
      ((digest String)
       (file String)))

    (: placed-files (impl (Fn Derived -> (List Placed))))
    (define (placed-files derived)
      (delete-duplicates (lambda (placed other) (string=? (::digest placed) (::digest other)))
                         (concatenate (map top-placed (derived-tops derived)))))

    (: derived-tops (impl (Fn Derived -> (List Top))))
    (define (derived-tops derived)
      (match derived
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
     (prefix (only (snail compiler bind language) Literal) bound-)
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
                                    (bound-Literal (expanded-UnitValue) loc)
                                    loc))
                            (None)
                            4))
                  (list (Placed "aa" "a.txt") (Placed "bb" "b.txt")))
          (expect (placed-files (Defined (list "a") (list) 1 loc)) (list))))))
   (else)))
