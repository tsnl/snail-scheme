;; The entry milestone A's old facade calls in place of the old expander:
;; the program at a path compiled by the new passes, `read` to `cohere`,
;; and handed over in the old compiler's terms. It is given what the old
;; expander is: the directories libraries are found in, the directory a
;; producer's output is read from and printed to, the build's old Inputs
;; and the program's path. It answers one of:
;;
;; - the old program, `adapted-program`'s, with, for each library that
;;   records a run of items, its key and the files it links;
;; - or what the compile waits for, as the old compiler's requests, all of
;;   them at once: a GenerateInput for each producer whose output is not
;;   there, with the text its caller prints for it at GENERATED/KEY.sld,
;;   or an ArtifactInput for each target the first library that asks for
;;   one was not supplied, where it is asked for;
;; - and when the new passes refuse the program, it performs the old
;;   `fail`, with each problem converted, in order.
;;
;; The new integrator reads a producer's output only from
;; GENERATED/KEY.syntax, where the old compiler also looks in the Inputs,
;; which a project build fills; so each output the Inputs supply is first
;; written there, under the key the Inputs keep it by, which is the one
;; the integrator asks for. The old lookup also compares the producer's
;; text, which tells apart two producers whose keys collide; a key names
;; one output in the new compiler.
(define-library (snail compiler adapter compile)
  (export
   Adaptation
   Adapted
   Requesting
   PrintedProducer
   adapted-compile)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (only (snail compiler bind supply) TargetFile)
   (only (snail compiler expand targets) TargetRequest)
   (only (snail compiler integrate walk) Producer)
   (snail compiler integrate compile)
   (only (snail compiler adapter program) AdaptedProgram adapted-program)
   (only (snail compiler adapter source) loc->old feedback->old)
   (prefix (only (snail shell compiler read)
                 CompilerRequest
                 GenerateInput
                 ArtifactInput
                 Diagnostics
                 compile
                 fail)
           old:)
   (prefix (only (snail shell compiler inputs) Inputs Generated) old:))
  (begin

    ;; ---- Answers ----

    (enum Adaptation
      (Adapted
       ((program AdaptedProgram)))
      (Requesting
       ((requests (List old:CompilerRequest))
        (printed (List PrintedProducer)))))

    ;; A producer to print as the program at `path`, for its caller to run.
    (struct PrintedProducer
      ((path String)
       (text String)))

    ;; ---- The entry ----

    (: adapted-compile
       (impl (Fn (List String) String old:Inputs String -> Adaptation ! fs old:compile)))
    (define (adapted-compile directories generated inputs path)
      (write-supplied generated inputs)
      (match (compile-program directories generated (target-files inputs) path)
        ((Ok (CompiledAll files)) (Adapted (adapted-program files)))
        ((Ok (WaitingForProducers producers)) (producer-requests generated producers))
        ((Ok (WaitingForTargets requests)) (Requesting (map target-request requests) (Nil)))
        ((Err feedback) (failed feedback))))

    ;; Each producer's output the Inputs supply, at GENERATED/KEY.syntax.
    (: write-supplied (impl (Fn String old:Inputs -> Unit ! fs)))
    (define (write-supplied generated inputs)
      (let ((supplied (::generated inputs)))
        (for-each (lambda (key)
                    (match (table-ref supplied key)
                      ((Some output)
                       (write-bytes (string-append generated "/" key ".syntax") (::bytes output)))
                      ((None) (unit))))
                  (list-sort string<? (table-keys supplied)))))

    ;; Each target's files the Inputs supply, by target.
    (: target-files (impl (Fn old:Inputs -> (Table (List TargetFile)))))
    (define (target-files inputs)
      (let ((artifacts (::artifacts inputs)))
        (fold-left (lambda (table name)
                     (match (table-ref artifacts name)
                       ((Some files)
                        (table-set table
                                   name
                                   (map (lambda (file) (TargetFile (::first file) (::second file)))
                                        files)))
                       ((None) table)))
                   empty-table
                   (list-sort string<? (table-keys artifacts)))))

    (: producer-requests (impl (Fn String (List Producer) -> Adaptation)))
    (define (producer-requests generated producers)
      (Requesting (map (lambda (producer) (old:GenerateInput (::key producer))) producers)
                  (map (lambda (producer)
                         (PrintedProducer (string-append generated "/" (::key producer) ".sld")
                                          (::text producer)))
                       producers)))

    (: target-request (impl (Fn TargetRequest -> old:CompilerRequest)))
    (define (target-request request)
      (old:ArtifactInput (::target request) (loc->old (::loc request))))

    ;; Every pass that refuses a library says why, so a compile that fails
    ;; has a problem.
    (: failed (impl (Fn (List Feedback) -> Adaptation ! old:compile)))
    (define (failed feedback)
      (match (map feedback->old feedback)
        ((Cons first more) (absurd (old:fail (old:Diagnostics first more))))
        ((Nil) (panic "internal error: a compile failed with no problem"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-compile)
    (import
     (only (chibi filesystem) create-directory* delete-file-hierarchy)
     (prefix (only (snail shell compiler read)
                   Loc
                   SourceDiagnostic
                   Failed
                   compiling
                   diagnostics->list)
             old:)
     (prefix (only (snail shell compiler inputs) no-inputs) old:)
     (prefix (only (snail shell compiler expand) LinkedFile) old:)
     (only (snail compiler adapter program) AdaptedLibrary)
     (snail stage0 testing))
    (begin
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-compile directory)
        (create-directory* (string-append directory "/sample"))
        (create-directory* (string-append directory "/data"))
        (if (file-exists? (string-append directory "/generated"))
            (delete-file-hierarchy (string-append directory "/generated"))
            (unit))
        (create-directory* (string-append directory "/generated"))
        (for-each
         (lambda (file) (write-file (string-append directory "/" (::first file)) (::second file)))
         (list (Pair "sample/lib.sld"
                     "(define-library (sample lib) (import (snail core forms)) (export x)\n  (begin (define x 1)))")
               (Pair "sample/made.sld"
                     "(generate-library (sample made) (import (sample lib)) x)")
               (Pair "sample/asks.sld"
                     "(define-library (sample asks) (import (snail core forms)) (export z)\n  (begin (define z (artifact-files \"site\" 1 2 3))))")
               (Pair "data/x.txt" "abc")
               (Pair "compiling.sld"
                     "(import (snail core forms) (sample lib))\n(link-handle \"data/x.txt\")\nx")
               (Pair "failing.sld" "(import (snail core forms))\n(define a b)\n(define c d)")
               (Pair "producing.sld" "(import (sample made))\nm")
               (Pair "asking.sld" "(import (sample asks))")))
        (test-compiling directory)
        (test-failing directory)
        (test-producing directory)
        (test-asking directory))

      (define (adapted directory inputs name)
        (old:compiling (lambda ()
                         (adapted-compile (list directory)
                                          (string-append directory "/generated")
                                          inputs
                                          (string-append directory "/" name)))))

      ;; A program that compiles is its old program, with the key of each
      ;; library that records a run and the files it links.
      (define (test-compiling directory)
        (match (adapted directory old:no-inputs "compiling.sld")
          ((Ok (Adapted program))
           (expect (::libraries program)
                   (list (AdaptedLibrary "sample.lib" (list))
                         (AdaptedLibrary
                          "main"
                          (list (old:LinkedFile
                                 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                                 (string-append directory "/data/x.txt"))))))
           (expect (map ::first (::libraries (::program program))) (list "main" "sample.lib")))
          (other (expect other "a program adapted"))))

      ;; A program the new passes refuse fails the old compile with each
      ;; of its problems, in order.
      (define (test-failing directory)
        (let ((file (string-append directory "/failing.sld")))
          (match (adapted directory old:no-inputs "failing.sld")
            ((Err (old:Failed diagnostics))
             (expect (old:diagnostics->list diagnostics)
                     (list (old:SourceDiagnostic (old:Loc file 2 11) "unbound identifier b")
                           (old:SourceDiagnostic (old:Loc file 3 11) "unbound identifier d"))))
            (other (expect other "a compile that fails with two problems")))))

      ;; A program that reaches a generated library asks for its producer's
      ;; output and gives the text to print; once the Inputs supply the
      ;; output, it compiles.
      (define (test-producing directory)
        (match (adapted directory old:no-inputs "producing.sld")
          ((Ok (Requesting (Cons (old:GenerateInput key) (Nil))
                           (Cons (PrintedProducer path text) (Nil))))
           (expect path (string-append directory "/generated/" key ".sld"))
           (expect (substring text 0 25) "(generating \"sample.made\"")
           (let ((inputs (old:Inputs empty-table
                                     (table-set empty-table
                                                key
                                                (old:Generated
                                                 text
                                                 (generated-library-bytes
                                                  "(define-library (sample made) (import (snail core forms)) (export m) (begin (define m 1)))"))))))
             (match (adapted directory inputs "producing.sld")
               ((Ok (Adapted program))
                (expect (map ::key (::libraries program)) (list "sample.made" "main")))
               (other (expect other "a program adapted once its producer's output is supplied")))))
          (other (expect other "a program that waits for one producer"))))

      ;; A program that asks for a target's files asks for it where it is
      ;; asked for; once the Inputs supply its files, it compiles.
      (define (test-asking directory)
        (match (adapted directory old:no-inputs "asking.sld")
          ((Ok (Requesting (Cons (old:ArtifactInput "site" loc) (Nil)) (Nil)))
           (expect loc (old:Loc (string-append directory "/sample/asks.sld") 2 20))
           (match (adapted directory
                           (old:Inputs (table-set empty-table
                                                  "site"
                                                  (list
                                                   (Pair "index.html" (list->vector (list 65)))))
                                       empty-table)
                           "asking.sld")
             ((Ok (Adapted program))
              (expect (map ::key (::libraries program)) (list "sample.asks" "main")))
             (other (expect other "a program adapted once its target's files are supplied"))))
          (other (expect other "a program that waits for one target"))))))
   (else)))
