;; Loading beside the old compiler, for as long as both exist. The old
;; compiler loads a library as its expander reaches the library's import,
;; so its loading is judged against `expand-program`, in two ways, and the
;; producers it waits for against the old closure walk's.
;;
;; - The cases below, which each stop loading at one problem: the first
;;   problem the old expander reports is the loader's. tests/compiler.scm
;;   runs them.
;; - The order of a program's libraries beside the order the old expansion
;;   records them in, which tests/compare-compiler.sld runs, compiled, over
;;   the suites' programs.
;; - The producers loading waits for, beside the generated libraries the
;;   old `library-closure` reaches, which the old planner keys and prints
;;   as the old expander would: by library, key, the text printed and the
;;   libraries loading. tests/compare-compiler.sld runs it over the same
;;   programs.
;;
;; The comparisons read and write files, as the old functions they call do.
(define-library (snail compiler adapter load)
  (export
   LoadCase
   load-cases
   load-case-comparison
   OrderComparison
   SameOrder
   KnownOrder
   OtherOrder
   UncomparedOrder
   order-comparison
   ProducerComparison
   ProducersAlike
   ProducersDiffer
   UncomparedProducers
   producer-comparison
   old-expansion
   old-expansion-with)
  (import
   (snail core base)
   (snail core io)
   (snail compiler source)
   (snail compiler outline language)
   (snail compiler outline names)
   (snail compiler integrate walk)
   (snail compiler integrate load)
   (snail compiler adapter outline)
   (prefix (only (snail shell compiler read)
                 Loc
                 diagnostics->string
                 compile
                 compile-error
                 Stop
                 Failed
                 Requested
                 compiling)
           old:)
   (prefix (only (snail shell compiler expand)
                 ExpandedProgram
                 expand-program
                 empty-expansion
                 Reached
                 library-closure
                 program-imports)
           old:)
   (prefix (only (snail shell compiler inputs)
                 Inputs
                 no-inputs
                 producer-text
                 producer-key
                 print-producer
                 generating-stack
                 read-source-file)
           old:))
  (begin

    ;; ---- The old expansion ----

    ;; What the old expander makes of the program at `path`, supplied
    ;; nothing. It runs no producer program, and says so.
    (: old-expansion
       (impl (Fn (List String) String -> (Result old:ExpandedProgram old:Stop) ! fs)))
    (define (old-expansion directories path)
      (old-expansion-with directories old:no-inputs path))

    ;; The same, supplied `inputs`, such as the files of a target.
    (: old-expansion-with
       (impl (Fn (List String) old:Inputs String -> (Result old:ExpandedProgram old:Stop) ! fs)))
    (define (old-expansion-with directories inputs path)
      (old:compiling (lambda ()
                       (old:expand-program directories
                                           (lambda (loading forms) (no-producer path))
                                           inputs
                                           path
                                           old:empty-expansion))))

    (: no-producer (All (T) (impl (Fn String -> T ! old:compile))))
    (define (no-producer path)
      (old:compile-error (old:Loc path 0 0) "the comparison runs no producer"))

    ;; ---- Problems ----

    ;; A program, at `main` in a directory, that the files beside it make
    ;; fail to load. The files are named from the directory, which has a
    ;; `sample` directory; a program without text is not there.
    (struct LoadCase
      ((main String)
       (text (Option String))
       (files (List (Pair String String)))))

    (: load-cases (List LoadCase))
    (define load-cases
      (list (LoadCase "absent.sld" (None) (list))
            (LoadCase "missing.sld" (Some "(import (prefix (sample absent) p:))") (list))
            (LoadCase "holder.sld"
                      (Some "(import (sample holder))")
                      (list (Pair "sample/holder.sld"
                                  "(define-library (sample holder)\n  (import (rename (sample gone) (x y))))")))
            (LoadCase "self.sld"
                      (Some "(import (sample self))")
                      (list (Pair "sample/self.sld"
                                  "(define-library (sample self)\n  (import (only (sample self) x)))")))
            (LoadCase "ring.sld"
                      (Some "(import (sample ring-a))")
                      (list (Pair "sample/ring-a.sld"
                                  "(define-library (sample ring-a) (import (sample ring-b)))")
                            (Pair "sample/ring-b.sld"
                                  "(define-library (sample ring-b) (import (except (sample ring-a) y)))")))
            (LoadCase "loop.sld"
                      (Some "(import (sample leaf) (sample loop))")
                      (list (Pair "sample/leaf.sld" "(define-library (sample leaf))")
                            (Pair "sample/loop.sld"
                                  "(define-library (sample loop) (import (sample leaf) (sample loop)))")))
            (LoadCase "keyed.sld"
                      (Some "(generating \"other\" \"sample.keyed\")\n(import (sample keyed))")
                      (list))
            (LoadCase "named-main.sld"
                      (Some "(import (main))")
                      (list (Pair "main.sld" "(define-library (main) (begin (define x 1)))")))
            (LoadCase "through-main.sld"
                      (Some "(import (sample through))")
                      (list (Pair "sample/through.sld"
                                  "(define-library (sample through) (import (main)))")))))

    ;; The case written in `directory`, loaded, beside the old expansion.
    (: load-case-comparison (impl (Fn String LoadCase -> Comparison ! fs)))
    (define (load-case-comparison directory load-case)
      (let ((main (string-append directory "/" (::main load-case))))
        (for-each (lambda (file)
                    (write-file (string-append directory "/" (::first file)) (::second file)))
                  (::files load-case))
        (match (::text load-case)
          ((Some text) (write-file main text))
          ((None) (unit)))
        (match (Pair (load-program (list directory) (string-append directory "/generated") main)
                     (old-expansion (list directory) main))
          ((Pair (Err feedback) (Err stop)) (stop-comparison feedback stop))
          ((Pair (Err feedback) (Ok _)) (only-new-stops feedback))
          ((Pair (Ok _) (Err stop)) (only-old-stops stop))
          ((Pair (Ok _) (Ok _)) (Uncompared "neither stops")))))

    ;; ---- Order ----

    ;; How the libraries of a program that loads completely come beside
    ;; those the old expansion records, in order: the same, the same but
    ;; for differences explained, or otherwise.
    (enum OrderComparison
      (SameOrder)
      (KnownOrder
       ((note String)))
      (OtherOrder
       ((difference String)))
      (UncomparedOrder
       ((reason String))))

    ;; Producers' outputs are read from `generated`.
    (: order-comparison (impl (Fn (List String) String String -> OrderComparison ! fs)))
    (define (order-comparison directories generated path)
      (match (load-program directories generated path)
        ((Err feedback)
         (UncomparedOrder (string-append "it does not load: " (feedback-text feedback))))
        ((Ok (Unproduced _)) (UncomparedOrder "it reaches a generated library"))
        ((Ok (Complete files))
         (expanded-order (map (lambda (file) (library-key (loaded-name file))) files)
                         (old-expansion directories path)))))

    (: expanded-order
       (impl (Fn (List String) (Result old:ExpandedProgram old:Stop) -> OrderComparison)))
    (define (expanded-order new old)
      (match old
        ((Ok expanded)
         (orders-comparison new (reverse (map ::first (::libraries (::program expanded))))))
        ((Err (old:Failed diagnostics))
         (UncomparedOrder (string-append "the old compiler does not expand it: "
                                         (old:diagnostics->string diagnostics))))
        ((Err (old:Requested _)) (UncomparedOrder "the old compiler asks for an input"))))

    ;; Two differences are known. The old expansion records no run for the
    ;; primitive library, whose body declares and defines nothing, so it
    ;; never lists it. And a `deriving` clause loads (snail shell wire) and
    ;; what it imports, which this loader does not load yet, so the old
    ;; expansion may list them earlier than an import of them, before the
    ;; library that derives, or list them when nothing imports them.
    (: orders-comparison (impl (Fn (List String) (List String) -> OrderComparison)))
    (define (orders-comparison new old)
      (let ((shared (filter (lambda (key) (member? key new)) old))
            (extra (filter (lambda (key) (not (member? key new))) old))
            (kept (without "snail.core.primitive" new)))
        (cond ((same-keys? new old) (SameOrder))
              ((not (or (null? extra) (member? "snail.shell.wire" old))) (other-order new old))
              ((same-keys? kept shared) (KnownOrder (known-note new extra #f)))
              ((same-keys? (without "snail.shell.wire" kept) (without "snail.shell.wire" shared))
               (KnownOrder (known-note new extra #t)))
              (else (other-order new old)))))

    (: other-order (impl (Fn (List String) (List String) -> OrderComparison)))
    (define (other-order new old)
      (OtherOrder (string-append "new: " (string-join new " ") "; old: " (string-join old " "))))

    (: without (impl (Fn String (List String) -> (List String))))
    (define (without key keys)
      (filter (lambda (other) (not (string=? other key))) keys))

    (: known-note (impl (Fn (List String) (List String) Bool -> String)))
    (define (known-note new extra moved)
      (string-join
       (concatenate
        (list (if (member? "snail.core.primitive" new) (list "the primitive library") (Nil))
              (if moved (list "snail.shell.wire loaded early by a deriving clause") (Nil))
              (if (null? extra)
                  (Nil)
                  (list (string-append "a deriving clause's " (string-join extra " "))))))
       ", "))

    (: same-keys? (impl (Fn (List String) (List String) -> Bool)))
    (define (same-keys? keys others)
      (and (= (length keys) (length others))
           (every? (lambda (pair) (string=? (::first pair) (::second pair))) (zip keys others))))

    ;; ---- Producers ----

    ;; How the producers a program waits for come beside the generated
    ;; libraries the old closure walk reaches: alike, with how many there
    ;; are; or the first difference; or why they cannot be compared.
    (enum ProducerComparison
      (ProducersAlike
       ((count I64)))
      (ProducersDiffer
       ((difference String)))
      (UncomparedProducers
       ((reason String))))

    ;; A producer as the old compiler prints it: the library's key, the
    ;; producer's key, the text it prints as KEY.sld and the libraries
    ;; loading. The text is read back from where `print-producer` wrote it,
    ;; under `printed`, so it is the old text exactly.
    (struct OldProducer
      ((library String)
       (key String)
       (text String)
       (loading (List String))))

    (: producer-comparison
       (impl (Fn (List String) String String String -> ProducerComparison ! fs)))
    (define (producer-comparison directories generated printed path)
      (match (Pair (load-program directories generated path)
                   (old:compiling (lambda () (old-producers directories printed path))))
        ((Pair (Err feedback) _)
         (UncomparedProducers (string-append "it does not load: " (feedback-text feedback))))
        ((Pair _ (Err _)) (UncomparedProducers "the old closure walk stops"))
        ((Pair (Ok (Complete _)) (Ok olds)) (producers-comparison (Nil) olds))
        ((Pair (Ok (Unproduced producers)) (Ok olds)) (producers-comparison producers olds))))

    ;; The generated libraries the old closure walk reaches from the
    ;; program at `path`, with no producer's output supplied.
    (: old-producers (impl (Fn (List String) String String -> (List OldProducer) ! fs old:compile)))
    (define (old-producers directories printed path)
      (let ((source (old:generating-stack (old:read-source-file path))))
        (map (lambda (reached) (old-producer directories printed reached))
             (old:library-closure directories
                                  old:no-inputs
                                  (::first source)
                                  (old:program-imports (::second source))))))

    (: old-producer (impl (Fn (List String) String old:Reached -> OldProducer ! fs)))
    (define (old-producer directories printed reached)
      (let* ((key (old:producer-key (old:producer-text directories (::forms reached))))
             (file (string-append printed "/" key ".sld")))
        (old:print-producer file (::loading reached) (::forms reached))
        (OldProducer (string-join (::library reached) ".")
                     key
                     (read-file file)
                     (::loading reached))))

    (: producers-comparison (impl (Fn (List Producer) (List OldProducer) -> ProducerComparison)))
    (define (producers-comparison news olds)
      (if (= (length news) (length olds))
          (match (find-difference
                  (map (lambda (pair) (producer-difference (::first pair) (::second pair)))
                       (zip news olds)))
            ((Some difference) (ProducersDiffer difference))
            ((None) (ProducersAlike (length news))))
          (ProducersDiffer (string-append "the new compiler waits for "
                                          (i64->string (length news))
                                          " producers, the old reaches "
                                          (i64->string (length olds))))))

    (: find-difference (impl (Fn (List (Option String)) -> (Option String))))
    (define (find-difference differences)
      (match differences
        ((Nil) (None))
        ((Cons (Some difference) _) (Some difference))
        ((Cons (None) rest) (find-difference rest))))

    (: producer-difference (impl (Fn Producer OldProducer -> (Option String))))
    (define (producer-difference new old)
      (let ((library (library-key (::library new))))
        (cond ((not (string=? library (::library old)))
               (Some (string-append "the new compiler waits for " library ", the old reaches "
                                    (::library old))))
              ((not (string=? (::key new) (::key old)))
               (Some (string-append library ": the new key is " (::key new) ", the old "
                                    (::key old))))
              ((not (string=? (::text new) (::text old)))
               (Some (string-append library ": the producers print otherwise, new "
                                    (::text new) "; old " (::text old))))
              ((not (same-keys? (::loading new) (::loading old)))
               (Some (string-append library ": the libraries loading differ: new "
                                    (string-join (::loading new) " ") "; old "
                                    (string-join (::loading old) " "))))
              (else (None)))))

    ))
