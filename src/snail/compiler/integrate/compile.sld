;; Compiling a program: loaded, then each library in the order loading
;; found them, each after every library it imports, the program last.
;; Each is taken through the passes before the next starts, so a problem
;; is reported for the earliest library that has one, as the old compiler
;; reports it: expanded, handed the offers of the libraries its imports
;; reach; bound, as (snail compiler integrate bind) says, with the files of
;; the targets the caller supplied; derived, handed the offers of the
;; implicit libraries; declared, handed what the libraries its imports
;; reach offer its declaration, and, when it derives an instance, what
;; (snail shell wire) and the libraries wire's imports reach offer, since
;; a derived instance names wire's classes; dispatched, handed the same
;; offers and the listing of every library compiled before it, in order,
;; since instances are global; and cohered, handed that listing too. The
;; first library that derives an instance, by a `deriving` clause naming
;; Serialize or Deserialize, needs the implicit libraries, (snail core
;; primitive) and (snail shell wire), with what they import: they are
;; loaded then, if no library loaded them, and compiled after that
;; library's expansion and before it is bound, where the old compiler
;; loads them, as it reaches the clause. A program that reaches a
;; generated library whose producer's output is not there is not
;; compiled: it waits for the producers, all of them, before anything is
;; compiled. One stops at the first library that asks for a target the
;; caller did not supply, which it waits for. The integrator keeps, of
;; each library, what it offers the expansion and the declaration of the
;; libraries that import it; the files the build must place beside the
;; program for it, which it asks of the library bound; its latest tree,
;; the library dispatched; and its listing, every instance it declares.
(define-library (snail compiler integrate compile)
  (export
   CompiledFile
   ProgramCompilation
   CompiledAll
   WaitingForProducers
   WaitingForTargets
   compile-program)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (snail compiler outline language)
   (snail compiler outline imports)
   (snail compiler names libraries)
   (only (snail compiler expand offer) Offered Expansion Offer)
   (snail compiler expand pass)
   (snail compiler expand derives)
   (only (snail compiler expand targets) TargetRequest)
   (only (snail compiler bind supply) TargetFile)
   (snail compiler bind pass)
   (snail compiler bind placed)
   (snail compiler derive pass)
   (only (snail compiler declare offer) DeclaredLibrary Declarations)
   (snail compiler declare pass)
   (only (snail compiler dispatch language) Dispatched)
   (only (snail compiler dispatch listing) Listed library-instances)
   (snail compiler dispatch pass)
   (snail compiler cohere pass)
   (snail compiler integrate walk)
   (snail compiler integrate load)
   (snail compiler integrate bind))
  (begin

    ;; ---- Compilations ----

    ;; One library's file, its name, the libraries it imports, what it
    ;; offers their expansion, the files to place beside the program for
    ;; it, the library dispatched, what it offers their declaration, and
    ;; its instances.
    (struct CompiledFile
      ((file String)
       (library LibraryName)
       (imports (List LibraryName))
       (offer Offer)
       (placed (List Placed))
       (dispatched Dispatched)
       (declarations Declarations)
       (listing (List Listed))))

    ;; Every library compiled, in order; or the producers of the generated
    ;; libraries whose outputs are not there, in the order reached, before
    ;; anything is compiled; or the targets the first library that asks
    ;; for one it was not supplied waits for.
    (enum ProgramCompilation
      (CompiledAll
       ((files (List CompiledFile))))
      (WaitingForProducers
       ((producers (List Producer))))
      (WaitingForTargets
       ((requests (List TargetRequest)))))

    ;; What the caller supplies a compile: the directories libraries are
    ;; found in, in order; the directory each producer's output is read
    ;; from, GENERATED/KEY.syntax; and the files of each target it has
    ;; made, by target.
    (struct Build
      ((directories (List String))
       (generated String)
       (targets (Table (List TargetFile)))))

    ;; The program at `path`, compiled.
    (: compile-program
       (impl (Fn (List String) String (Table (List TargetFile)) String
                 -> (Result ProgramCompilation (List Feedback))
                 !
                 fs)))
    (define (compile-program directories generated targets path)
      (result-let* ((loaded (load-program directories generated path)))
        (match loaded
          ((Unproduced producers) (Ok (WaitingForProducers producers)))
          ((Complete files)
           (result-let* ((run (compiled-files (Build directories generated targets)
                                              files
                                              (Running (Nil) #f))))
             (Ok (match run
                   ((Running done _) (CompiledAll (reverse done)))
                   ((StoppedForProducers producers) (WaitingForProducers producers))
                   ((StoppedForTargets requests) (WaitingForTargets requests)))))))))

    ;; ---- The loop ----

    ;; How far the loop is: the files done, latest first, and whether the
    ;; implicit libraries are in; or the producers the implicit libraries
    ;; wait for, when loading them reaches one; or the targets the library
    ;; it stopped at waits for.
    (enum Run
      (Running
       ((done (List CompiledFile))
        (implicit? Bool)))
      (StoppedForProducers
       ((producers (List Producer))))
      (StoppedForTargets
       ((requests (List TargetRequest)))))

    ;; `run` with each of `files` compiled in turn. A library the implicit
    ;; libraries brought in early is not compiled again where loading put
    ;; it.
    (: compiled-files
       (impl (Fn Build (List LoadedFile) Run -> (Result Run (List Feedback)) ! fs)))
    (define (compiled-files build files run)
      (match (Pair files run)
        ((Pair (Cons loaded rest) (Running done implicit?))
         (if (compiled? done loaded)
             (compiled-files build rest run)
             (result-let* ((next (library-run build loaded done implicit?)))
               (compiled-files build rest next))))
        (_ (Ok run))))

    ;; One library expanded; then the implicit libraries, when it is the
    ;; first to derive; then the library bound, derived, declared,
    ;; dispatched and cohered.
    (: library-run
       (impl (Fn Build LoadedFile (List CompiledFile) Bool -> (Result Run (List Feedback)) ! fs)))
    (define (library-run build loaded done implicit?)
      (let ((imports (map ::library (library-imports (::library loaded)))))
        (result-let* ((expansion (expand (::library loaded) (closure-offers done imports)))
                      (before (implicit-before build expansion done implicit?)))
          (match before
            ((Running earlier implicit?)
             (declared-run (::targets build) loaded imports expansion earlier implicit?))
            (_ (Ok before))))))

    ;; The run with the library bound, derived, declared, dispatched and
    ;; cohered after `earlier`, or waiting for the targets it asks for.
    (: declared-run
       (impl
        (Fn (Table (List TargetFile))
            LoadedFile
            (List LibraryName)
            Expansion
            (List CompiledFile)
            Bool
            -> (Result Run (List Feedback))
            !
            fs)))
    (define (declared-run targets loaded imports expansion earlier implicit?)
      (result-let* ((outcome (bind-expanded loaded (::expanded expansion) targets)))
        (match outcome
          ((WantsTargets requests) (Ok (StoppedForTargets requests)))
          ((BoundLibrary bound)
           (let ((closure (closure-declarations earlier (declaration-imports expansion imports)))
                 (instances (listings earlier)))
             (result-let* ((derived (derive bound (implicit-offers earlier)))
                           (declared (declare derived closure))
                           (dispatched (dispatch (::declared declared) closure instances))
                           (cohered (cohere dispatched instances)))
               (Ok (Running (Cons (CompiledFile (::file loaded)
                                                (loaded-name loaded)
                                                imports
                                                (::offer expansion)
                                                (placed-files bound)
                                                dispatched
                                                (::declarations declared)
                                                (library-instances dispatched))
                                  earlier)
                            implicit?))))))))

    ;; Every instance of the libraries done, `done` latest first, in the
    ;; program's order.
    (: listings (impl (Fn (List CompiledFile) -> (List Listed))))
    (define (listings done)
      (concatenate (map ::listing (reverse done))))

    ;; The libraries whose closure a library's declaration is handed: its
    ;; imports, and (snail shell wire) when it derives an instance.
    (: declaration-imports (impl (Fn Expansion (List LibraryName) -> (List LibraryName))))
    (define (declaration-imports expansion imports)
      (match (first-derivation (::expanded expansion))
        ((Some _) (append imports (list wire-library)))
        ((None) imports)))

    ;; `done` with the implicit libraries, when the library `expansion`
    ;; holds is the first to derive. They load with nothing loading, since
    ;; no library they reach is generated.
    (: implicit-before
       (impl (Fn Build Expansion (List CompiledFile) Bool -> (Result Run (List Feedback)) ! fs)))
    (define (implicit-before build expansion done implicit?)
      (match (if implicit? (None) (first-derivation (::expanded expansion)))
        ((Some loc)
         (result-let* ((loaded
                        (load-libraries (::directories build)
                                        (::generated build)
                                        implicit-libraries
                                        loc)))
           (match loaded
             ((Complete files)
              (compiled-files build
                              (filter (lambda (file) (not (compiled? done file))) files)
                              (Running done #t)))
             ((Unproduced producers) (Ok (StoppedForProducers producers))))))
        ((None) (Ok (Running done implicit?)))))

    (: wire-library LibraryName)
    (define wire-library
      (list "snail" "shell" "wire"))

    (: implicit-libraries (List LibraryName))
    (define implicit-libraries
      (list forms-library primitive-library wire-library))

    ;; The offers of the implicit libraries done so far, in the order the
    ;; old expander loads them. (snail core forms) has no file and offers
    ;; `derive` nothing it uses: only its keywords, whose forms `derive`
    ;; writes as nodes.
    (: implicit-offers (impl (Fn (List CompiledFile) -> (List Offered))))
    (define (implicit-offers done)
      (concatenate (map (lambda (name)
                          (match (compiled-named done name)
                            ((Some file) (list (Offered name (::offer file))))
                            ((None) (Nil))))
                        implicit-libraries)))

    (: compiled? (impl (Fn (List CompiledFile) LoadedFile -> Bool)))
    (define (compiled? done loaded)
      (match (compiled-named done (loaded-name loaded))
        ((Some _) #t)
        ((None) #f)))

    (: compiled-named (impl (Fn (List CompiledFile) LibraryName -> (Option CompiledFile))))
    (define (compiled-named done name)
      (find (lambda (file) (same-library? (::library file) name)) done))

    ;; ---- Closures ----

    ;; The offers of the libraries `imports` reach, as `reached-offers`
    ;; says. Every one is done, since loading put each library after those
    ;; it imports; (snail core forms) has no file.
    (: closure-offers (impl (Fn (List CompiledFile) (List LibraryName) -> (List Offered))))
    (define (closure-offers done imports)
      (reached-offers
       (map (lambda (file) (OfferingLibrary (::library file) (::imports file) (::offer file)))
            done)
       imports))

    ;; What the libraries `imports` reach offer their importers'
    ;; declaration, each once.
    (: closure-declarations
       (impl (Fn (List CompiledFile) (List LibraryName) -> (List Declarations))))
    (define (closure-declarations done imports)
      (map ::declarations (closure-files done imports)))

    (: closure-files (impl (Fn (List CompiledFile) (List LibraryName) -> (List CompiledFile))))
    (define (closure-files done imports)
      (concatenate (map (lambda (name)
                          (match (compiled-named done name)
                            ((Some file) (list file))
                            ((None) (Nil))))
                        (reached-libraries
                         (map (lambda (file) (Importer (::library file) (::imports file)))
                              done)
                         imports))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-compile)
    (import
     (only (scheme base) apply bytevector write-bytevector close-port)
     (only (scheme file) open-binary-output-file)
     (only (chibi filesystem) create-directory* delete-file-hierarchy)
     (only (snail compiler names globals) Global TopGlobal ClassGlobal)
     (prefix (only (snail compiler declare language) Call TopRef) declared-)
     (prefix
      (only (snail compiler dispatch language) Program LinkImport TopData TopInstance Statement)
      dispatched-)
     (snail stage0 testing))
    (begin
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-compile directory)
        (create-directory* (string-append directory "/sample"))
        (if (file-exists? (string-append directory "/generated"))
            (delete-file-hierarchy (string-append directory "/generated"))
            (unit))
        (create-directory* (string-append directory "/generated"))
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
               (Pair "waiting.sld" "(import (sample made) (sample broken))\nm")
               (Pair "sample/broken.sld" "(define-library (sample broken) (begin (bogus)))")
               (Pair "using.sld" "(import (sample made))\nm")
               (Pair "asking.sld" "(import (sample asks))")
               (Pair "missing.sld" "(import (snail core forms))\n(link-handle \"data/y.txt\")")
               (Pair "sample/probes.sld"
                     "(define-library (sample probes) (import (snail core forms)) (export Probe probe)\n  (begin (typeclass (Probe T) (: probe (impl (Fn T -> I64)))) (instance (Probe I64) (define (probe x) 1))))")
               (Pair "overlapping.sld"
                     "(import (snail core forms) (sample probes))\n(instance (Probe I64) (define (probe x) 2))")))
        (match (compiled-at directory "main.sld")
          ((Ok (CompiledAll files))
           (expect (map ::library files)
                   (list (list "sample" "lib") (list "sample" "user") (list "main")))
           (expect (::dispatched (list-ref files 2))
                   (dispatched-Program (list (dispatched-Statement
                                              (declared-TopRef (TopGlobal
                                                                (Global
                                                                 (list "sample" "user")
                                                                 "y"
                                                                 0))
                                                               (Loc
                                                                (string-append directory
                                                                               "/main.sld")
                                                                2
                                                                1))))
                                       1)))
          (other (expect other "a compiled program")))
        (test-bound directory)
        (test-derived directory)
        (test-generated directory)
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
          (other (expect other "a program whose linked file is missing")))
        ;; Each library is cohered with the instances of those before it.
        (match (compiled-at directory "overlapping.sld")
          ((Err (Cons feedback (Nil)))
           (expect feedback
                   (Feedback (Loc (string-append directory "/overlapping.sld") 2 1)
                             "this instance overlaps another instance of the class on its input types")))
          (other (expect other "a program whose instance overlaps an earlier library's"))))

      ;; Each library is bound once it expands: the program's linked file
      ;; is its handle's import, and its statement a call of the handle;
      ;; the file to place beside the program is kept with the library.
      (define (test-bound directory)
        (match (compiled-at directory "linking.sld")
          ((Ok (CompiledAll files))
           (let* ((main (string-append directory "/linking.sld"))
                  (handle (Global (list "main") "link-handle" 1))
                  (use (Loc main 2 1)))
             (expect (::placed (list-ref files 0))
                     (list
                      (Placed "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                              (string-append directory "/data/x.txt"))))
             (expect (::dispatched (list-ref files 0))
                     (dispatched-Program
                      (list (dispatched-LinkImport handle
                                                   (list "data" "x.txt")
                                                   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                                                   (string-append directory "/data/x.txt")
                                                   (Loc main 2 14))
                            (dispatched-Statement
                             (declared-Call (declared-TopRef (TopGlobal handle) use)
                                            (list)
                                            use)))
                      2))))
          (other (expect other "a program that links a file"))))

      ;; A library that derives brings the implicit libraries in before it
      ;; is bound, and is derived with their offers: its struct is followed
      ;; by the instance, which is declared with wire's offer of its class;
      ;; the library's listing holds the instance alone, since the struct
      ;; has no field.
      (define (test-derived directory)
        (match (compiled-at directory "deriving.sld")
          ((Ok (CompiledAll files))
           (expect (map ::library files)
                   (list (list "snail" "core" "primitive")
                         (list "snail" "shell" "wire")
                         (list "main")))
           (match (::dispatched (list-ref files 2))
             ((dispatched-Program (Cons (dispatched-TopData data)
                                        (Cons (dispatched-TopInstance instance) (Nil)))
                                  _)
              (expect (::class instance)
                      (ClassGlobal (Global (list "snail" "shell" "wire")
                                           "Serialize"
                                           0))))
             (other (expect other "a struct and its derived instance")))
           (expect (length (::listing (list-ref files 2))) 1))
          (other (expect other "a program that derives an instance"))))

      ;; A program that reaches a generated library whose output is not
      ;; there waits for its producer before anything is compiled, even a
      ;; library with a problem; once the output is there, the library it
      ;; declares is compiled in its place, in its recipe's file.
      (define (test-generated directory)
        (match (compiled-at directory "waiting.sld")
          ((Ok (WaitingForProducers (Cons producer (Nil))))
           (expect (::library producer) (list "sample" "made"))
           (expect (::loading producer) (list "sample.made"))
           ;; (define-library (sample made) (export m) (import (snail core
           ;; forms)) (begin (define m 7))), as a producer encodes it.
           (write-output directory
                         producer
                         (list 0 5
                               1 14 100 101 102 105 110 101 45 108 105 98 114 97 114 121
                               0 2 1 6 115 97 109 112 108 101 1 4 109 97 100 101
                               0 2 1 6 101 120 112 111 114 116 1 1 109
                               0 2 1 6 105 109 112 111 114 116
                               0 3 1 5 115 110 97 105 108 1 4 99 111 114 101 1 5 102 111 114 109 115
                               0 2 1 5 98 101 103 105 110
                               0 3 1 6 100 101 102 105 110 101 1 1 109 2 1 55))
           (match (compiled-at directory "using.sld")
             ((Ok (CompiledAll files))
              (expect (map (lambda (file) (Pair (::file file) (::library file))) files)
                      (list
                       (Pair (string-append directory "/sample/made.sld") (list "sample" "made"))
                       (Pair (string-append directory "/using.sld") (list "main")))))
             (other (expect other "a program whose generated library is compiled"))))
          (other (expect other "a program waiting for (sample made)"))))

      ;; Writes `codes` as the output of `producer`, as its producer would.
      (define (write-output directory producer codes)
        (let ((port (open-binary-output-file
                     (string-append directory "/generated/" (::key producer) ".syntax"))))
          (write-bytevector (apply bytevector codes) port)
          (close-port port)))

      (define (compiled-at directory file)
        (compile-program (list directory)
                         (string-append directory "/generated")
                         empty-table
                         (string-append directory "/" file)))))
   (else)))
