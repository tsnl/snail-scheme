;; Expanding and binding a loaded program: each library in the order
;; loading found them, each after every library it imports, the program
;; last. Each is expanded, handed the offers of the libraries its imports
;; reach, then bound, as (snail compiler integrate bind) says, with the
;; files of the targets the caller supplied. The first library that
;; derives an instance, by a `deriving` clause naming Serialize or
;; Deserialize, needs the implicit libraries `derive` writes instances
;; with, (snail core primitive) and (snail shell wire), with what they
;; import: they are loaded then, if no library loaded them, and expanded
;; and bound after that library's expansion and before it is bound, where
;; the old compiler loads them, as it reaches the clause. A program that
;; reaches a generated library is not expanded, since its producer has
;; not yet printed the library's body, and one stops at the first library
;; that asks for a target the caller did not supply, which it waits for.
(define-library (snail compiler integrate expand)
  (export
   ExpandedFile
   ProgramExpansion
   ExpandedAll
   WaitingFor
   WaitingForTargets
   expand-loaded)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (snail compiler outline language)
   (snail compiler outline imports)
   (snail compiler outline names)
   (only (snail compiler expand language) Expanded)
   (only (snail compiler expand offer) Offered Expansion)
   (snail compiler expand pass)
   (snail compiler expand derives)
   (only (snail compiler expand targets) TargetRequest)
   (only (snail compiler bind language) Bound)
   (only (snail compiler bind supply) TargetFile)
   (snail compiler integrate walk)
   (snail compiler integrate load)
   (snail compiler integrate bind))
  (begin

    ;; ---- Expansions ----

    ;; One library's file, its name, the libraries it imports, its
    ;; expansion, and the library bound.
    (struct ExpandedFile
      ((file String)
       (library LibraryName)
       (imports (List LibraryName))
       (expansion Expansion)
       (bound Bound)))

    ;; Every library expanded and bound, in order; or the generated
    ;; libraries the program waits for, before anything expands; or the
    ;; targets the first library that asks for one it was not supplied
    ;; waits for.
    (enum ProgramExpansion
      (ExpandedAll
       ((files (List ExpandedFile))))
      (WaitingFor
       ((libraries (List LibraryName))))
      (WaitingForTargets
       ((requests (List TargetRequest)))))

    ;; `targets` holds the files of each target the caller supplies, by
    ;; target.
    (: expand-loaded
       (impl (Fn (List String) (Table (List TargetFile)) Loaded
                 -> (Result ProgramExpansion (List Feedback))
                 !
                 fs)))
    (define (expand-loaded directories targets loaded)
      (match (::waiting loaded)
        ((Cons _ _) (Ok (WaitingFor (::waiting loaded))))
        ((Nil)
         (result-let* ((run
                        (expanded-files directories targets (::files loaded) (Running (Nil) #f))))
           (Ok (match run
                 ((Running done _) (ExpandedAll (reverse done)))
                 ((Waiting requests) (WaitingForTargets requests))))))))

    ;; ---- The loop ----

    ;; How far the loop is: the files done, latest first, and whether the
    ;; implicit libraries are in; or the targets the library it stopped
    ;; at waits for.
    (enum Run
      (Running
       ((done (List ExpandedFile))
        (implicit? Bool)))
      (Waiting
       ((requests (List TargetRequest)))))

    ;; `run` with each of `files` expanded and bound in turn. A library the
    ;; implicit libraries brought in early is not expanded again where
    ;; loading put it.
    (: expanded-files
       (impl (Fn (List String) (Table (List TargetFile)) (List Outlined) Run
                 -> (Result Run (List Feedback))
                 !
                 fs)))
    (define (expanded-files directories targets files run)
      (match (Pair files run)
        ((Pair (Cons outlined rest) (Running done implicit?))
         (if (expanded? done outlined)
             (expanded-files directories targets rest run)
             (result-let* ((next (library-run directories targets outlined done implicit?)))
               (expanded-files directories targets rest next))))
        (_ (Ok run))))

    ;; One library expanded; then the implicit libraries, when it is the
    ;; first to derive; then the library bound.
    (: library-run
       (impl (Fn (List String) (Table (List TargetFile)) Outlined (List ExpandedFile) Bool
                 -> (Result Run (List Feedback))
                 !
                 fs)))
    (define (library-run directories targets outlined done implicit?)
      (let ((imports (map ::library (imported-libraries (::outline outlined)))))
        (result-let* ((expansion (library-expansion done outlined imports))
                      (before (implicit-before directories targets expansion done implicit?)))
          (match before
            ((Running earlier implicit?)
             (bound-run targets outlined imports expansion earlier implicit?))
            ((Waiting _) (Ok before))))))

    ;; The run with the library bound after `earlier`, or waiting for the
    ;; targets it asks for.
    (: bound-run
       (impl
        (Fn (Table (List TargetFile)) Outlined (List LibraryName) Expansion (List ExpandedFile) Bool
            -> (Result Run (List Feedback))
            !
            fs)))
    (define (bound-run targets outlined imports expansion earlier implicit?)
      (let ((name (outlined-name outlined)))
        (result-let* ((outcome (bind-expanded outlined name (::expanded expansion) targets)))
          (Ok (match outcome
                ((BoundLibrary bound)
                 (Running
                  (Cons (ExpandedFile (::file outlined) name imports expansion bound) earlier)
                  implicit?))
                ((WantsTargets requests) (Waiting requests)))))))

    ;; `done` with the implicit libraries, when the library `expansion`
    ;; holds is the first to derive.
    (: implicit-before
       (impl (Fn (List String) (Table (List TargetFile)) Expansion (List ExpandedFile) Bool
                 -> (Result Run (List Feedback))
                 !
                 fs)))
    (define (implicit-before directories targets expansion done implicit?)
      (match (if implicit? (None) (first-derivation (::expanded expansion)))
        ((Some loc)
         (result-let* ((loaded (load-libraries directories implicit-libraries loc)))
           (expanded-files directories
                           targets
                           (filter (lambda (outlined) (not (expanded? done outlined)))
                                   (::files loaded))
                           (Running done #t))))
        ((None) (Ok (Running done implicit?)))))

    (: implicit-libraries (List LibraryName))
    (define implicit-libraries
      (list (list "snail" "core" "forms")
            (list "snail" "core" "primitive")
            (list "snail" "shell" "wire")))

    (: expanded? (impl (Fn (List ExpandedFile) Outlined -> Bool)))
    (define (expanded? done outlined)
      (any? (lambda (file) (same-library? (::library file) (outlined-name outlined))) done))

    ;; ---- One library ----

    (: library-expansion
       (impl
        (Fn (List ExpandedFile) Outlined (List LibraryName) -> (Result Expansion (List Feedback)))))
    (define (library-expansion done outlined imports)
      (match (::outline outlined)
        ((Written library) (expand library (closure-offers done imports)))
        ((Generated name _ _ loc)
         (fail loc
               (string-append "a generated library is expanded once printed: "
                              (written-name name))))))

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
     (prefix (only (snail compiler bind language) Program LinkImport Call TopRef) bound-)
     (snail stage0 testing))
    (begin
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-expand-loaded directory)
        (create-directory* (string-append directory "/sample"))
        (create-directory* (string-append directory "/data"))
        (for-each
         (lambda (file) (write-file (string-append directory "/" (::first file)) (::second file)))
         (list (Pair "sample/lib.sld"
                     "(define-library (sample lib) (import (snail core forms)) (export x)\n  (begin (define x 1)))")
               (Pair "sample/user.sld"
                     "(define-library (sample user) (import (snail core forms) (sample lib)) (export y)\n  (begin (define y x)))")
               (Pair "sample/made.sld"
                     "(generate-library (sample made) (import (sample lib)) (unit))")
               (Pair "sample/asks.sld"
                     "(define-library (sample asks) (import (snail core forms)) (export z)\n  (begin (define z (artifact-files \"site\" 1 2 3))))")
               (Pair "main.sld" "(import (snail core forms) (sample user))\ny")
               (Pair "linking.sld" "(import (snail core forms))\n(link-handle \"data/x.txt\")")
               (Pair "data/x.txt" "abc")
               (Pair "waiting.sld" "(import (sample made))")
               (Pair "asking.sld" "(import (sample asks))")
               (Pair "missing.sld" "(import (snail core forms))\n(link-handle \"data/y.txt\")")))
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
        (test-bound directory)
        (match (expanded-at directory "waiting.sld")
          ((Ok (WaitingFor libraries)) (expect libraries (list (list "sample" "made"))))
          (other (expect other "a program waiting for (sample made)")))
        (match (expanded-at directory "asking.sld")
          ((Ok (WaitingForTargets requests))
           (expect (map ::target requests) (list "site")))
          (other (expect other "a program waiting for the target site")))
        (match (expanded-at directory "missing.sld")
          ((Err (Cons feedback (Nil)))
           (expect (::message feedback)
                   (string-append "the library main links data/y.txt, but there is no file at "
                                  directory
                                  "/data/y.txt")))
          (other (expect other "a program whose linked file is missing"))))

      ;; Each library is bound once it expands: the program's linked file
      ;; is its handle's import, and its statement a call of the handle.
      (define (test-bound directory)
        (match (expanded-at directory "linking.sld")
          ((Ok (ExpandedAll files))
           (let* ((main (string-append directory "/linking.sld"))
                  (handle (expanded-Global (list "main") "link-handle" 1))
                  (use (Loc main 2 1)))
             (expect (::bound (list-ref files 0))
                     (bound-Program
                      (list (bound-LinkImport handle
                                              (list "data" "x.txt")
                                              "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                                              (string-append directory "/data/x.txt")
                                              (Loc main 2 14)))
                      (Some (bound-Call (bound-TopRef (expanded-TopGlobal handle) use) (list) use))
                      2))))
          (other (expect other "a program that links a file"))))

      (define (expanded-at directory file)
        (match (load-program (list directory) (string-append directory "/" file))
          ((Ok loaded) (expand-loaded (list directory) empty-table loaded))
          ((Err feedback) (Err feedback))))))
   (else)))
