;; Compiling a loaded program: each library in the order loading found
;; them, each after every library it imports, the program last. Each is
;; taken through the passes before the next starts, so a problem is
;; reported for the earliest library that has one, as the old compiler
;; reports it: expanded, handed the offers of the libraries its imports
;; reach; bound, as (snail compiler integrate bind) says, with the files of
;; the targets the caller supplied; and derived, handed the offers of the
;; implicit libraries. The first library that derives an instance, by a
;; `deriving` clause naming Serialize or Deserialize, needs those
;; libraries, (snail core primitive) and (snail shell wire), with what
;; they import: they are loaded then, if no library loaded them, and
;; compiled after that library's expansion and before it is bound, where
;; the old compiler loads them, as it reaches the clause. A program that
;; reaches a generated library is not compiled, since its producer has
;; not yet printed the library's body, and one stops at the first library
;; that asks for a target the caller did not supply, which it waits for.
;; The integrator keeps, of each library, its offer, which expanding the
;; libraries that import it reads; the files the build must place beside
;; the program for it, which it asks of the library bound; and its latest
;; tree, the library derived.
(define-library (snail compiler integrate compile)
  (export
   CompiledFile
   ProgramCompilation
   CompiledAll
   WaitingForLibraries
   WaitingForTargets
   compile-loaded)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (snail compiler outline language)
   (snail compiler outline imports)
   (snail compiler outline names)
   (only (snail compiler expand offer) Offered Expansion Offer)
   (snail compiler expand pass)
   (snail compiler expand derives)
   (only (snail compiler expand targets) TargetRequest)
   (only (snail compiler bind supply) TargetFile)
   (snail compiler bind pass)
   (snail compiler bind placed)
   (only (snail compiler derive language) Derived)
   (snail compiler derive pass)
   (snail compiler integrate walk)
   (snail compiler integrate load)
   (snail compiler integrate bind))
  (begin

    ;; ---- Compilations ----

    ;; One library's file, its name, the libraries it imports, what it
    ;; offers, the files to place beside the program for it, and the
    ;; library derived.
    (struct CompiledFile
      ((file String)
       (library LibraryName)
       (imports (List LibraryName))
       (offer Offer)
       (placed (List Placed))
       (derived Derived)))

    ;; Every library compiled, in order; or the generated libraries the
    ;; program waits for, before anything is compiled; or the targets the
    ;; first library that asks for one it was not supplied waits for.
    (enum ProgramCompilation
      (CompiledAll
       ((files (List CompiledFile))))
      (WaitingForLibraries
       ((libraries (List LibraryName))))
      (WaitingForTargets
       ((requests (List TargetRequest)))))

    ;; `targets` holds the files of each target the caller supplies, by
    ;; target.
    (: compile-loaded
       (impl (Fn (List String) (Table (List TargetFile)) Loaded
                 -> (Result ProgramCompilation (List Feedback))
                 !
                 fs)))
    (define (compile-loaded directories targets loaded)
      (match (::waiting loaded)
        ((Cons _ _) (Ok (WaitingForLibraries (::waiting loaded))))
        ((Nil)
         (result-let* ((run
                        (compiled-files directories targets (::files loaded) (Running (Nil) #f))))
           (Ok (match run
                 ((Running done _) (CompiledAll (reverse done)))
                 ((Waiting requests) (WaitingForTargets requests))))))))

    ;; ---- The loop ----

    ;; How far the loop is: the files done, latest first, and whether the
    ;; implicit libraries are in; or the targets the library it stopped
    ;; at waits for.
    (enum Run
      (Running
       ((done (List CompiledFile))
        (implicit? Bool)))
      (Waiting
       ((requests (List TargetRequest)))))

    ;; `run` with each of `files` compiled in turn. A library the implicit
    ;; libraries brought in early is not compiled again where loading put
    ;; it.
    (: compiled-files
       (impl (Fn (List String) (Table (List TargetFile)) (List Outlined) Run
                 -> (Result Run (List Feedback))
                 !
                 fs)))
    (define (compiled-files directories targets files run)
      (match (Pair files run)
        ((Pair (Cons outlined rest) (Running done implicit?))
         (if (compiled? done outlined)
             (compiled-files directories targets rest run)
             (result-let* ((next (library-run directories targets outlined done implicit?)))
               (compiled-files directories targets rest next))))
        (_ (Ok run))))

    ;; One library expanded; then the implicit libraries, when it is the
    ;; first to derive; then the library bound and derived.
    (: library-run
       (impl (Fn (List String) (Table (List TargetFile)) Outlined (List CompiledFile) Bool
                 -> (Result Run (List Feedback))
                 !
                 fs)))
    (define (library-run directories targets outlined done implicit?)
      (let ((imports (map ::library (imported-libraries (::outline outlined)))))
        (result-let* ((expansion (library-expansion done outlined imports))
                      (before (implicit-before directories targets expansion done implicit?)))
          (match before
            ((Running earlier implicit?)
             (derived-run targets outlined imports expansion earlier implicit?))
            ((Waiting _) (Ok before))))))

    ;; The run with the library bound and derived after `earlier`, or
    ;; waiting for the targets it asks for.
    (: derived-run
       (impl
        (Fn (Table (List TargetFile)) Outlined (List LibraryName) Expansion (List CompiledFile) Bool
            -> (Result Run (List Feedback))
            !
            fs)))
    (define (derived-run targets outlined imports expansion earlier implicit?)
      (result-let* ((outcome (bind-expanded outlined (::expanded expansion) targets)))
        (match outcome
          ((WantsTargets requests) (Ok (Waiting requests)))
          ((BoundLibrary bound)
           (result-let* ((derived (derive bound (implicit-offers earlier))))
             (Ok (Running (Cons (CompiledFile (::file outlined)
                                              (outlined-name outlined)
                                              imports
                                              (::offer expansion)
                                              (placed-files bound)
                                              derived)
                                earlier)
                          implicit?)))))))

    ;; `done` with the implicit libraries, when the library `expansion`
    ;; holds is the first to derive.
    (: implicit-before
       (impl (Fn (List String) (Table (List TargetFile)) Expansion (List CompiledFile) Bool
                 -> (Result Run (List Feedback))
                 !
                 fs)))
    (define (implicit-before directories targets expansion done implicit?)
      (match (if implicit? (None) (first-derivation (::expanded expansion)))
        ((Some loc)
         (result-let* ((loaded (load-libraries directories implicit-libraries loc)))
           (compiled-files directories
                           targets
                           (filter (lambda (outlined) (not (compiled? done outlined)))
                                   (::files loaded))
                           (Running done #t))))
        ((None) (Ok (Running done implicit?)))))

    (: implicit-libraries (List LibraryName))
    (define implicit-libraries
      (list (list "snail" "core" "forms")
            (list "snail" "core" "primitive")
            (list "snail" "shell" "wire")))

    ;; The offers of the implicit libraries done so far, in the order the
    ;; old expander loads them. (snail core forms) has no file and offers
    ;; `derive` nothing it uses: only its keywords, whose forms `derive`
    ;; writes as nodes.
    (: implicit-offers (impl (Fn (List CompiledFile) -> (List Offered))))
    (define (implicit-offers done)
      (concatenate (map (lambda (name)
                          (match (find (lambda (file) (same-library? (::library file) name)) done)
                            ((Some file) (list (Offered name (::offer file))))
                            ((None) (Nil))))
                        implicit-libraries)))

    (: compiled? (impl (Fn (List CompiledFile) Outlined -> Bool)))
    (define (compiled? done outlined)
      (any? (lambda (file) (same-library? (::library file) (outlined-name outlined))) done))

    ;; ---- One library ----

    (: library-expansion
       (impl
        (Fn (List CompiledFile) Outlined (List LibraryName) -> (Result Expansion (List Feedback)))))
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
    (: closure-offers (impl (Fn (List CompiledFile) (List LibraryName) -> (List Offered))))
    (define (closure-offers done imports)
      (map (lambda (file) (Offered (::library file) (::offer file)))
           (reached done imports (Nil))))

    (: reached
       (impl
        (Fn (List CompiledFile) (List LibraryName) (List CompiledFile) -> (List CompiledFile))))
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
     test-compile-loaded)
    (import
     (only (chibi filesystem) create-directory*)
     (prefix (snail compiler expand language) expanded-)
     (prefix (only (snail compiler bind language) Call TopRef) bound-)
     (prefix (only (snail compiler derive language) Program LinkImport Struct TopInstance) derived-)
     (snail stage0 testing))
    (begin
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-compile-loaded directory)
        (create-directory* (string-append directory "/sample"))
        (create-directory* (string-append directory "/data"))
        (create-directory* (string-append directory "/snail/core"))
        (create-directory* (string-append directory "/snail/shell"))
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
               (Pair "snail/core/primitive.sld"
                     "(define-library (snail core primitive) (import (snail core forms)) (export unit)\n  (begin (primitive unit (impl (Fn -> Unit)))))")
               (Pair "snail/shell/wire.sld"
                     "(define-library (snail shell wire) (import (snail core forms)) (export Serialize encode encode-case-id)\n  (begin (typeclass (Serialize T) (: encode (impl (Fn T I64 -> Unit)))) (define (encode-case-id e i) e)))")
               (Pair "main.sld" "(import (snail core forms) (sample user))\ny")
               (Pair "linking.sld" "(import (snail core forms))\n(link-handle \"data/x.txt\")")
               (Pair "deriving.sld"
                     "(import (snail core forms))\n(struct Unit-like () (deriving Serialize))")
               (Pair "data/x.txt" "abc")
               (Pair "waiting.sld" "(import (sample made))")
               (Pair "asking.sld" "(import (sample asks))")
               (Pair "missing.sld" "(import (snail core forms))\n(link-handle \"data/y.txt\")")))
        (match (compiled-at directory "main.sld")
          ((Ok (CompiledAll files))
           (expect (map ::library files)
                   (list (list "sample" "lib") (list "sample" "user") (list "main")))
           (expect (::derived (list-ref files 2))
                   (derived-Program (list)
                                    (Some (bound-TopRef (expanded-TopGlobal
                                                         (expanded-Global (list "sample" "user")
                                                                          "y"
                                                                          0))
                                                        (Loc (string-append directory "/main.sld")
                                                             2
                                                             1)))
                                    1)))
          (other (expect other "a compiled program")))
        (test-bound directory)
        (test-derived directory)
        (match (compiled-at directory "waiting.sld")
          ((Ok (WaitingForLibraries libraries)) (expect libraries (list (list "sample" "made"))))
          (other (expect other "a program waiting for (sample made)")))
        (match (compiled-at directory "asking.sld")
          ((Ok (WaitingForTargets requests))
           (expect (map ::target requests) (list "site")))
          (other (expect other "a program waiting for the target site")))
        (match (compiled-at directory "missing.sld")
          ((Err (Cons feedback (Nil)))
           (expect (::message feedback)
                   (string-append "the library main links data/y.txt, but there is no file at "
                                  directory
                                  "/data/y.txt")))
          (other (expect other "a program whose linked file is missing"))))

      ;; Each library is bound once it expands: the program's linked file
      ;; is its handle's import, and its statement a call of the handle;
      ;; the file to place beside the program is kept with the library.
      (define (test-bound directory)
        (match (compiled-at directory "linking.sld")
          ((Ok (CompiledAll files))
           (let* ((main (string-append directory "/linking.sld"))
                  (handle (expanded-Global (list "main") "link-handle" 1))
                  (use (Loc main 2 1)))
             (expect (::placed (list-ref files 0))
                     (list
                      (Placed "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                              (string-append directory "/data/x.txt"))))
             (expect (::derived (list-ref files 0))
                     (derived-Program
                      (list (derived-LinkImport handle
                                                (list "data" "x.txt")
                                                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                                                (string-append directory "/data/x.txt")
                                                (Loc main 2 14)))
                      (Some (bound-Call (bound-TopRef (expanded-TopGlobal handle) use) (list) use))
                      2))))
          (other (expect other "a program that links a file"))))

      ;; A library that derives brings the implicit libraries in before it
      ;; is bound, and is derived with their offers: its struct is followed
      ;; by the instance.
      (define (test-derived directory)
        (match (compiled-at directory "deriving.sld")
          ((Ok (CompiledAll files))
           (expect (map ::library files)
                   (list (list "snail" "core" "primitive")
                         (list "snail" "shell" "wire")
                         (list "main")))
           (match (::derived (list-ref files 2))
             ((derived-Program (Cons (derived-Struct _ _ _ #f _ _ _)
                                     (Cons (derived-TopInstance instance) (Nil)))
                               (None)
                               _)
              (expect (::class instance)
                      (expanded-ClassGlobal (expanded-Global (list "snail" "shell" "wire")
                                                             "Serialize"
                                                             0))))
             (other (expect other "a struct and its derived instance"))))
          (other (expect other "a program that derives an instance"))))

      (define (compiled-at directory file)
        (match (load-program (list directory) (string-append directory "/" file))
          ((Ok loaded) (compile-loaded (list directory) empty-table loaded))
          ((Err feedback) (Err feedback))))))
   (else)))
