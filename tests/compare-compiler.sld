;; The comparisons of the new compiler with the old that load or expand
;; whole programs, too slow on Chibi for `make test-compiler`, so compiled,
;; and those that read every tracked library or need a producer's
;; encoder, which stage 0 cannot load: `make compare-compiler` runs this
;; from the repository's root, with every tracked library as its
;; arguments. Each suite's programs load with the directories
;; tests/run.scm gives that suite, and no producer's output, since the
;; suite keeps none: how far each loads is counted, and the libraries of
;; each that loads completely are compared, in order, with the old
;; expansion's; the producers each waits for are compared with the
;; generated libraries the old closure walk reaches, as (snail compiler
;; adapter load) says; then each program that loads completely is taken
;; through the new passes, `read` to `cohere`, and compared with the old
;; expansion as (snail compiler adapter expansion) says, as is the
;; program (snail compiler adapter program) makes of it, and the old
;; checker's answers for the two programs, and its targets
;; discovered beside the old discovery, as (snail compiler adapter
;; discover) says, as are that library's cases. Then every tracked
;; library's forms, and the unusual texts of (snail compiler adapter
;; read), are written as text by both compilers; and those forms, encoded
;; as a producer encodes them, and the malformed outputs of (snail
;; compiler adapter read), are decoded by both. Last, the SHA-256 the
;; integrator names linked files by is compared with the old one
;; compiled, as tests/compiler.scm compares them on Chibi.
(import
 (snail core base)
 (snail core io)
 (snail compiler source)
 (snail compiler names libraries)
 (snail compiler integrate walk)
 (snail compiler integrate load)
 (snail compiler adapter read)
 (snail compiler adapter outline)
 (snail compiler adapter load)
 (snail compiler adapter expansion)
 (snail compiler adapter discover)
 (snail compiler adapter sha256)
 (snail shell syntax)
 (prefix (only (snail shell compiler read)
               Syntax
               Atom
               Ident
               Form
               Datum
               DInt
               DFloat
               DString
               DChar
               DBytes
               DBool
               DUnit
               read-text
               compiling)
         old:))

;; ---- Scratch ----

;; No producer's output is in `generated`, which need not exist, so a
;; program that reaches a generated library waits for its producer; the
;; old producers are printed in `printed`.
(: generated String)
(define generated "build/compare-compiler/generated")

(: printed String)
(define printed "build/compare-compiler/printed")

;; ---- Suites ----

;; A directory of programs, and where their libraries are found.
(struct Suite
  ((directory String)
   (libraries (List String))))

(: suites (List Suite))
(define suites
  (list (Suite "examples" (list "examples" "src"))
        (Suite "tests/programs" (list "tests/programs" "tests/programs/lib" "src"))
        (Suite "tests/projects" (list "src" "src"))
        (Suite "apps/siegework/tests" (list "apps/siegework/src" "src"))
        (Suite "apps/hearsay/tests" (list "apps/hearsay/src" "src"))))

;; A suite's programs, in name order.
(: suite-programs (impl (Fn Suite -> (List String) ! fs)))
(define (suite-programs suite)
  (match (list-directory (::directory suite))
    ((Ok names)
     (map (lambda (name) (string-append (::directory suite) "/" name))
          (list-sort string<? (filter source-name? names))))
    ((Err _) (Nil))))

(: source-name? (impl (Fn String -> Bool)))
(define (source-name? name)
  (let* ((chars (string->vector name))
         (start (- (vector-length chars) 4)))
    (and (> start 0)
         (string=? (vector->string (subvector chars start (vector-length chars))) ".sld"))))

;; ---- Findings ----

;; One program's findings: how far it loads, how its order compares, how
;; its producers compare, how its expansion compares, how the program
;; the adapter makes of it compares with the old expansion's, how the old
;; checker's answers for the two compare, and how its discovery compares.
(struct Finding
  ((path String)
   (load String)
   (order OrderComparison)
   (producers ProducerComparison)
   (expansion (Pair String String))
   (adapted (Pair String String))
   (checked (Pair String String))
   (discovery (Pair String String))))

(: program-finding (impl (Fn Suite String -> Finding ! fs)))
(define (program-finding suite path)
  (let ((directories (::libraries suite))
        (expansions (expansion-comparison (::libraries suite) generated path)))
    (Finding path
             (load-summary (load-program directories generated path))
             (order-comparison directories generated path)
             (producer-comparison directories generated printed path)
             (::expansion expansions)
             (::adapted expansions)
             (::checked expansions)
             (discovery-comparison directories generated path))))

;; The kinds of expansion finding, the ones that need no word first.
(: expansion-kinds (List String))
(define expansion-kinds
  (list "expand alike"
        "fail alike"
        "fail alike, several problems"
        "fail alike first, several problems differ"
        "fail differently"
        "only the old fails"
        "only the new fails"
        "expansions differ"
        "not compared"))

(: expansion-line (impl (Fn Finding -> (List String))))
(define (expansion-line finding)
  (let ((kind (::first (::expansion finding))))
    (if (or (string=? kind "expand alike") (string=? kind "fail alike"))
        (Nil)
        (list (string-append (::path finding) ": " kind ": " (::second (::expansion finding)))))))

;; A program whose adapted program is compared and differs.
(: adapted-line (impl (Fn Finding -> (List String))))
(define (adapted-line finding)
  (if (string=? (::first (::adapted finding)) "adaptations differ")
      (list
       (string-append (::path finding) ": adaptations differ: " (::second (::adapted finding))))
      (Nil)))

(: adapted-count (impl (Fn (List Finding) String -> String)))
(define (adapted-count findings kind)
  (string-append (i64->string (length (filter (lambda (finding)
                                                (string=? (::first (::adapted finding)) kind))
                                              findings)))
                 " "
                 kind))

;; The kinds of check finding; those but "check alike", "fail alike" and
;; "not compared" are differences.
(: check-kinds (List String))
(define check-kinds
  (list "check alike"
        "fail alike"
        "fail differently"
        "only the adapted fails"
        "only the old fails"
        "checks differ"
        "not compared"))

(: check-differs? (impl (Fn Finding -> Bool)))
(define (check-differs? finding)
  (not (member? (::first (::checked finding)) (list "check alike" "fail alike" "not compared"))))

(: check-line (impl (Fn Finding -> (List String))))
(define (check-line finding)
  (if (check-differs? finding)
      (list (string-append (::path finding)
                           ": "
                           (::first (::checked finding))
                           ": "
                           (::second (::checked finding))))
      (Nil)))

(: check-count (impl (Fn (List Finding) String -> String)))
(define (check-count findings kind)
  (string-append (i64->string (length (filter (lambda (finding)
                                                (string=? (::first (::checked finding)) kind))
                                              findings)))
                 " "
                 kind))

(: expansion-count (impl (Fn (List Finding) String -> String)))
(define (expansion-count findings kind)
  (string-append (i64->string (length (filter (lambda (finding)
                                                (string=? (::first (::expansion finding)) kind))
                                              findings)))
                 " "
                 kind))

;; "complete", "generated" or "failed", and what stopped it.
(: load-summary (impl (Fn (Result Loaded (List Feedback)) -> String)))
(define (load-summary result)
  (match result
    ((Ok (Complete _)) "complete")
    ((Ok (Unproduced producers))
     (string-append "generated: "
                    (string-join (map (lambda (producer) (written-name (::library producer)))
                                      producers)
                                 " ")))
    ((Err feedback) (string-append "failed: " (feedback-text feedback)))))

(: starts-with? (impl (Fn String String -> Bool)))
(define (starts-with? text start)
  (let ((chars (string->vector text))
        (prefix (string->vector start)))
    (and (>= (vector-length chars) (vector-length prefix))
         (string=? (vector->string (subvector chars 0 (vector-length prefix))) start))))

(: count-loads (impl (Fn (List Finding) String -> I64)))
(define (count-loads findings start)
  (length (filter (lambda (finding) (starts-with? (::load finding) start)) findings)))

(: order-line (impl (Fn Finding -> (List String))))
(define (order-line finding)
  (match (::order finding)
    ((SameOrder) (Nil))
    ((KnownOrder note) (list (string-append (::path finding) ": known order difference: " note)))
    ((OtherOrder difference) (list (string-append (::path finding) ": ORDER DIFFERS: " difference)))
    ((UncomparedOrder reason)
     (list (string-append (::path finding) ": order not compared: " reason)))))

(: order-kind (impl (Fn OrderComparison -> String)))
(define (order-kind order)
  (match order
    ((SameOrder) "the same")
    ((KnownOrder _) "known differences")
    ((OtherOrder _) "other differences")
    ((UncomparedOrder _) "not compared")))

(: order-count (impl (Fn (List Finding) String -> String)))
(define (order-count findings kind)
  (string-append (i64->string (length (filter (lambda (finding)
                                                (string=? (order-kind (::order finding)) kind))
                                              findings)))
                 " "
                 kind))

;; ---- Producers ----

(: producer-line (impl (Fn Finding -> (List String))))
(define (producer-line finding)
  (match (::producers finding)
    ((ProducersAlike _) (Nil))
    ((ProducersDiffer difference)
     (list (string-append (::path finding) ": PRODUCERS DIFFER: " difference)))
    ((UncomparedProducers reason)
     (list (string-append (::path finding) ": producers not compared: " reason)))))

;; The programs that wait for a producer, and how many producers they
;; wait for in all.
(: producer-counts (impl (Fn (List Finding) -> (Pair I64 I64))))
(define (producer-counts findings)
  (fold-left (lambda (counts finding)
               (match (::producers finding)
                 ((ProducersAlike count)
                  (if (> count 0)
                      (Pair (+ (::first counts) 1) (+ (::second counts) count))
                      counts))
                 (_ counts)))
             (Pair 0 0)
             findings))

(: producers-differ? (impl (Fn Finding -> Bool)))
(define (producers-differ? finding)
  (match (::producers finding)
    ((ProducersDiffer _) #t)
    (_ #f)))

;; ---- Discovery ----

(: discovery-kinds (List String))
(define discovery-kinds
  (list "discover alike"
        "fail alike"
        "only the old fails"
        "only the new fails"
        "fail differently"
        "discoveries differ"
        "not compared"))

;; A program only the old discovery refuses is one whose problem a pass
;; after `expand` finds, so the new compile must refuse it alike.
(: discovery-line (impl (Fn Finding -> (List String))))
(define (discovery-line finding)
  (let ((kind (::first (::discovery finding))))
    (cond ((member? kind (list "discover alike" "fail alike")) (Nil))
          ((and (string=? kind "only the old fails") (later-refusal? finding)) (Nil))
          (else (list (string-append (::path finding)
                                     ": discovery: "
                                     kind
                                     ": "
                                     (::second (::discovery finding))))))))

(: later-refusal? (impl (Fn Finding -> Bool)))
(define (later-refusal? finding)
  (member? (::first (::expansion finding)) (list "fail alike" "fail alike, several problems")))

(: discovery-wrong? (impl (Fn Finding -> Bool)))
(define (discovery-wrong? finding)
  (let ((kind (::first (::discovery finding))))
    (or (member? kind (list "only the new fails" "fail differently" "discoveries differ"))
        (and (string=? kind "only the old fails") (not (later-refusal? finding))))))

(: discovery-count (impl (Fn (List Finding) String -> String)))
(define (discovery-count findings kind)
  (string-append (i64->string (length (filter (lambda (finding)
                                                (string=? (::first (::discovery finding)) kind))
                                              findings)))
                 " "
                 kind))

;; The discovery cases of (snail compiler adapter discover), each written
;; in build/compare-compiler/discovery/, its libraries found there and in
;; src, by its program's name, with what discovery finds of it.
(: discovery-case-findings (impl (Fn -> (List (Pair String (Pair String String))) ! fs)))
(define (discovery-case-findings)
  (let ((directory "build/compare-compiler/discovery"))
    (match (make-directories (string-append directory "/sample"))
      ((Ok _)
       (map (lambda (discovery-case)
              (Pair (::main discovery-case)
                    (discovery-case-comparison directory (list "src") generated discovery-case)))
            discovery-cases))
      ((Err _) (panic (string-append "cannot make " directory))))))

(: case-kind (impl (Fn (Pair String (Pair String String)) -> String)))
(define (case-kind finding)
  (::first (::second finding)))

;; The cases not discovered alike.
(: unlike-cases
   (impl
    (Fn (List (Pair String (Pair String String))) -> (List (Pair String (Pair String String))))))
(define (unlike-cases found)
  (filter (lambda (finding) (not (string=? (case-kind finding) "discover alike"))) found))

;; A line for each case not discovered alike, and a line counting them.
(: case-lines (impl (Fn (List (Pair String (Pair String String))) -> (List String))))
(define (case-lines found)
  (append (map (lambda (finding)
                 (string-append (::first finding)
                                ": discovery: "
                                (case-kind finding)
                                ": "
                                (::second (::second finding))))
               (unlike-cases found))
          (list (string-append "compared the discovery of "
                               (i64->string (length found))
                               " cases with the old: "
                               (i64->string (length (unlike-cases found)))
                               " differ"))))

;; ---- Written text ----

;; The tracked libraries' forms and the unusual texts, written: a line for
;; each form whose text the new compiler writes otherwise than the old,
;; and a line counting them.
(: written-findings (impl (Fn (List String) -> (List String) ! fs)))
(define (written-findings paths)
  (let ((differences
         (append (concatenate (map (lambda (path)
                                     (match (written-difference path (read-file path))
                                       ((Some difference)
                                        (list (string-append path ": " difference)))
                                       ((None) (Nil))))
                                   paths))
                 (written-differences))))
    (append differences
            (list (string-append "compared the text of Syntax on "
                                 (i64->string (length paths))
                                 " libraries and "
                                 (i64->string (length unusual-texts))
                                 " texts: "
                                 (i64->string (length differences))
                                 " differences")))))

;; ---- Producers' outputs ----

;; A form the old reader read, as a recipe would return it to its
;; producer. The reader writes no unit datum.
(: recipe-syntax (impl (Fn old:Syntax -> Syntax)))
(define (recipe-syntax syntax)
  (match syntax
    ((old:Form items _) (ListSyntax (map recipe-syntax items)))
    ((old:Ident name _ _) (SymbolSyntax name))
    ((old:Atom datum _) (datum-syntax datum))))

(: datum-syntax (impl (Fn old:Datum -> Syntax)))
(define (datum-syntax datum)
  (match datum
    ((old:DInt value) (IntegerSyntax value))
    ((old:DFloat text) (FloatSyntax text))
    ((old:DString value) (StringSyntax value))
    ((old:DChar value) (CharSyntax value))
    ((old:DBytes value) (BytesSyntax value))
    ((old:DBool value) (BooleanSyntax value))
    ((old:DUnit) (ListSyntax (list (SymbolSyntax "unit"))))))

;; Each form of the library at `path` that the decoders make otherwise of,
;; once a producer has encoded it, and how many forms were decoded.
(: library-output-differences (impl (Fn String -> (Pair I64 (List String)) ! fs)))
(define (library-output-differences path)
  (match (old:compiling (lambda () (old:read-text (read-file path) path)))
    ((Ok forms)
     (Pair (length forms)
           (concatenate (map (lambda (form)
                               (match (output-difference (syntax->bytes (recipe-syntax form))
                                                         (Loc path 1 1))
                                 ((Some difference) (list (string-append path ": " difference)))
                                 ((None) (Nil))))
                             forms))))
    ((Err _) (Pair 0 (Nil)))))

;; The tracked libraries' forms and the malformed outputs, decoded: a line
;; for each difference, and a line counting them.
(: output-findings (impl (Fn (List String) -> (List String) ! fs)))
(define (output-findings paths)
  (let* ((found (map library-output-differences paths))
         (differences (append (concatenate (map ::second found)) (output-differences))))
    (append differences
            (list (string-append "compared the decoding of producers' outputs on "
                                 (i64->string (fold-left + 0 (map ::first found)))
                                 " forms of "
                                 (i64->string (length paths))
                                 " libraries and "
                                 (i64->string (length malformed-outputs))
                                 " malformed outputs: "
                                 (i64->string (length differences))
                                 " differences")))))

;; ---- Main ----

;; The tracked libraries, which the Makefile names as the arguments.
(: tracked (List String))
(define tracked
  (match (command-line)
    ((Cons _ paths) paths)
    ((Nil) (Nil))))

(match (make-directories printed)
  ((Ok _) (unit))
  ((Err _) (panic (string-append "cannot make " printed))))

(let* ((findings (concatenate (map (lambda (suite)
                                     (map (lambda (path) (program-finding suite path))
                                          (suite-programs suite)))
                                   suites)))
       (total (length findings)))
  (for-each (lambda (finding)
              (if (starts-with? (::load finding) "complete")
                  (unit)
                  (write-line (string-append (::path finding) ": " (::load finding)))))
            findings)
  (for-each write-line (concatenate (map order-line findings)))
  (write-line (string-append "loaded "
                             (i64->string total)
                             " programs: "
                             (i64->string (count-loads findings "complete"))
                             " completely, "
                             (i64->string (count-loads findings "generated"))
                             " up to a generated library, "
                             (i64->string (count-loads findings "failed"))
                             " failed"))
  (write-line (string-append "compared their order with the old expansion: "
                             (string-join (map (lambda (kind) (order-count findings kind))
                                               (list "the same"
                                                     "known differences"
                                                     "other differences"
                                                     "not compared"))
                                          ", ")))
  (for-each write-line (concatenate (map producer-line findings)))
  (let ((counts (producer-counts findings)))
    (write-line (string-append "compared their producers with the old: "
                               (i64->string (::second counts))
                               " producers of "
                               (i64->string (::first counts))
                               " programs alike, "
                               (i64->string (length (filter producers-differ? findings)))
                               " programs differ")))
  (for-each write-line (concatenate (map expansion-line findings)))
  (write-line (string-append "compared their expansion with the old: "
                             (string-join (map (lambda (kind) (expansion-count findings kind))
                                               expansion-kinds)
                                          ", ")))
  (for-each write-line (concatenate (map adapted-line findings)))
  (write-line (string-append "compared the programs adapted with the old expansions': "
                             (string-join (map (lambda (kind) (adapted-count findings kind))
                                               (list "adapt alike"
                                                     "adaptations differ"
                                                     "not compared"))
                                          ", ")))
  (for-each write-line (concatenate (map check-line findings)))
  (write-line
   (string-append "compared the old checker on the programs adapted and the old expansions': "
                  (string-join (map (lambda (kind) (check-count findings kind))
                                    check-kinds)
                               ", ")))
  (for-each write-line (concatenate (map discovery-line findings)))
  (write-line (string-append "compared their discovery with the old: "
                             (string-join (map (lambda (kind) (discovery-count findings kind))
                                               discovery-kinds)
                                          ", ")))
  (let ((cases (discovery-case-findings)))
    (for-each write-line (case-lines cases))
    (if (null? (unlike-cases cases)) (unit) (panic "the discoveries of the cases differ")))
  (let ((written (written-findings tracked)))
    (for-each write-line written)
    (if (> (length written) 1) (panic "the written texts differ") (unit)))
  (let ((outputs (output-findings tracked)))
    (for-each write-line outputs)
    (if (> (length outputs) 1) (panic "the decoders differ") (unit)))
  (if (any? (lambda (finding)
              (member? (::first (::expansion finding))
                       (list "fail alike first, several problems differ"
                             "fail differently"
                             "only the new fails"
                             "expansions differ")))
            findings)
      (panic "the expansions differ")
      (unit))
  (if (any? (lambda (finding) (string=? (::first (::adapted finding)) "adaptations differ"))
            findings)
      (panic "the programs adapted differ")
      (unit))
  (if (any? check-differs? findings) (panic "the old checker's answers differ") (unit))
  (if (any? (lambda (finding) (string=? (order-kind (::order finding)) "other differences"))
            findings)
      (panic "the orders differ")
      (unit))
  (if (any? producers-differ? findings) (panic "the producers differ") (unit))
  (if (any? discovery-wrong? findings) (panic "the discoveries differ") (unit))
  (match (digest-difference)
    ((None) (write-line "compared the new SHA-256 with the old: no differences"))
    ((Some difference) (panic (string-append "the SHA-256 differs: " difference)))))
