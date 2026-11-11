;; Expanding a loaded program: each library in the order loading found
;; them, each after every library it imports, the program last. Each is
;; handed the offers of the libraries its imports reach. The first
;; library that derives an instance, by a `deriving` clause naming
;; Serialize or Deserialize, needs the implicit libraries `derive` writes
;; instances with, (snail core primitive) and (snail shell wire), with
;; what they import: they are loaded then, if no library loaded them, and
;; expanded before the library that derives, where the old compiler puts
;; them. A program that reaches a generated library is not expanded,
;; since its producer has not yet printed the library's body.
(define-library (snail compiler integrate expand)
  (export
   ExpandedFile
   ProgramExpansion
   ExpandedAll
   WaitingFor
   expand-loaded)
  (import
   (snail core base)
   (snail core io)
   (snail compiler source)
   (snail compiler outline language)
   (snail compiler outline imports)
   (snail compiler outline names)
   (only (snail compiler expand language) Expanded)
   (only (snail compiler expand offer) Offered Expansion)
   (snail compiler expand pass)
   (snail compiler expand derives)
   (snail compiler integrate walk)
   (snail compiler integrate load))
  (begin

    ;; ---- Expansions ----

    ;; One library's file, its name, the libraries it imports, and its
    ;; expansion.
    (struct ExpandedFile
      ((file String)
       (library LibraryName)
       (imports (List LibraryName))
       (expansion Expansion)))

    (enum ProgramExpansion
      (ExpandedAll
       ((files (List ExpandedFile))))
      (WaitingFor
       ((libraries (List LibraryName)))))

    (: expand-loaded
       (impl (Fn (List String) Loaded -> (Result ProgramExpansion (List Feedback)) ! fs)))
    (define (expand-loaded directories loaded)
      (match (::waiting loaded)
        ((Cons _ _) (Ok (WaitingFor (::waiting loaded))))
        ((Nil)
         (result-let* ((expanded (expanded-files directories (::files loaded) (Nil) #f)))
           (Ok (ExpandedAll (reverse (::first expanded))))))))

    ;; The files expanded, latest first, after `done`, and whether the
    ;; implicit libraries are in. A library the implicit libraries brought
    ;; in early is not expanded again where loading put it.
    (: expanded-files
       (impl (Fn (List String) (List Outlined) (List ExpandedFile) Bool
                 -> (Result (Pair (List ExpandedFile) Bool) (List Feedback))
                 !
                 fs)))
    (define (expanded-files directories files done implicit?)
      (match files
        ((Nil) (Ok (Pair done implicit?)))
        ((Cons outlined rest)
         (if (expanded? done outlined)
             (expanded-files directories rest done implicit?)
             (result-let* ((file (expanded-file done outlined))
                           (with-implicit (implicit-before directories file done implicit?)))
               (expanded-files directories
                               rest
                               (Cons file (::first with-implicit))
                               (::second with-implicit)))))))

    ;; `done` with the implicit libraries, when `file` is the first to
    ;; derive.
    (: implicit-before
       (impl (Fn (List String) ExpandedFile (List ExpandedFile) Bool
                 -> (Result (Pair (List ExpandedFile) Bool) (List Feedback))
                 !
                 fs)))
    (define (implicit-before directories file done implicit?)
      (match (if implicit? (None) (first-derivation (::expanded (::expansion file))))
        ((Some loc)
         (result-let* ((loaded (load-libraries directories implicit-libraries loc))
                       (expanded (expanded-files directories
                                                 (filter (lambda (outlined)
                                                           (not (expanded? done outlined)))
                                                         (::files loaded))
                                                 done
                                                 #t)))
           (Ok (Pair (::first expanded) #t))))
        ((None) (Ok (Pair done implicit?)))))

    (: implicit-libraries (List LibraryName))
    (define implicit-libraries
      (list (list "snail" "core" "forms")
            (list "snail" "core" "primitive")
            (list "snail" "shell" "wire")))

    (: expanded? (impl (Fn (List ExpandedFile) Outlined -> Bool)))
    (define (expanded? done outlined)
      (any? (lambda (file) (same-library? (::library file) (outlined-name outlined))) done))

    ;; ---- One library ----

    (: expanded-file
       (impl (Fn (List ExpandedFile) Outlined -> (Result ExpandedFile (List Feedback)))))
    (define (expanded-file done outlined)
      (let ((imports (map ::library (imported-libraries (::outline outlined)))))
        (match (::outline outlined)
          ((Written library)
           (result-let* ((expansion (expand library (closure-offers done imports))))
             (Ok (ExpandedFile (::file outlined) (outlined-name outlined) imports expansion))))
          ((Generated name _ _ loc)
           (fail loc
                 (string-append "a generated library is expanded once printed: "
                                (written-name name)))))))

    (: outlined-name (impl (Fn Outlined -> LibraryName)))
    (define (outlined-name outlined)
      (match (::outline outlined)
        ((Written (Defined name _ _ _ _)) name)
        ((Written (Program _ _ _ _)) (list "main"))
        ((Generated name _ _ _) name)))

    ;; The offers of the libraries `imports` reach, each once, in the
    ;; order first reached. Every one is done, since loading put each
    ;; library after those it imports; (snail core forms) has no file.
    (: closure-offers (impl (Fn (List ExpandedFile) (List LibraryName) -> (List Offered))))
    (define (closure-offers done imports)
      (map (lambda (file) (Offered (::library file) (::offer (::expansion file))))
           (reached done imports (Nil))))

    (: reached
       (impl
        (Fn (List ExpandedFile) (List LibraryName) (List ExpandedFile) -> (List ExpandedFile))))
    (define (reached done names found)
      (match names
        ((Nil) found)
        ((Cons name rest)
         (if (any? (lambda (file) (same-library? (::library file) name)) found)
             (reached done rest found)
             (match (find (lambda (file) (same-library? (::library file) name)) done)
               ((Some file)
                (reached done rest (reached done (::imports file) (append found (list file)))))
               ((None) (reached done rest found)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-expand-loaded)
    (import
     (only (chibi filesystem) create-directory*)
     (prefix (snail compiler expand language) expanded-)
     (snail stage0 testing))
    (begin
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-expand-loaded directory)
        (create-directory* (string-append directory "/sample"))
        (for-each
         (lambda (file) (write-file (string-append directory "/" (::first file)) (::second file)))
         (list (Pair "sample/lib.sld"
                     "(define-library (sample lib) (import (snail core forms)) (export x)\n  (begin (define x 1)))")
               (Pair "sample/user.sld"
                     "(define-library (sample user) (import (snail core forms) (sample lib)) (export y)\n  (begin (define y x)))")
               (Pair "sample/made.sld"
                     "(generate-library (sample made) (import (sample lib)) (unit))")
               (Pair "main.sld" "(import (snail core forms) (sample user))\ny")
               (Pair "waiting.sld" "(import (sample made))")))
        (match (expanded-at directory "main.sld")
          ((Ok (ExpandedAll files))
           (expect (map ::library files)
                   (list (list "sample" "lib") (list "sample" "user") (list "main")))
           (expect (::expanded (::expansion (list-ref files 2)))
                   (expanded-Program (list)
                                     (Some (expanded-TopRef (expanded-TopGlobal
                                                             (expanded-Global (list "sample" "user")
                                                                              "y"
                                                                              0))
                                                            (Loc
                                                             (string-append directory "/main.sld")
                                                             2
                                                             1)))
                                     1)))
          (other (expect other "an expanded program")))
        (match (expanded-at directory "waiting.sld")
          ((Ok (WaitingFor libraries)) (expect libraries (list (list "sample" "made"))))
          (other (expect other "a program waiting for (sample made)"))))

      (define (expanded-at directory file)
        (match (load-program (list directory) (string-append directory "/" file))
          ((Ok loaded) (expand-loaded (list directory) loaded))
          ((Err feedback) (Err feedback))))))
   (else)))
