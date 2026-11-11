;; The comparisons of the new compiler with the old that load or expand
;; whole programs, too slow on Chibi for `make test-compiler`, so compiled:
;; `make compare-compiler` runs this from the repository's root. Each
;; suite's programs load with the directories tests/run.scm gives that
;; suite: how far each loads is counted, and the libraries of each that
;; loads completely are compared, in order, with the old expansion's;
;; then each such program is expanded and bound, and compared with the old
;; expansion as (snail compiler adapter expansion) says. Last, the
;; SHA-256 the integrator names linked files by is compared with the old
;; one compiled, as tests/compiler.scm compares them on Chibi.
(import
 (snail core base)
 (snail core io)
 (snail compiler source)
 (snail compiler outline names)
 (snail compiler integrate walk)
 (snail compiler integrate load)
 (snail compiler adapter outline)
 (snail compiler adapter load)
 (snail compiler adapter expansion)
 (snail compiler adapter sha256))

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

;; One program's findings: how far it loads, and how its order compares.
(struct Finding
  ((path String)
   (load String)
   (order OrderComparison)
   (expansion (Pair String String))))

(: program-finding (impl (Fn Suite String -> Finding ! fs)))
(define (program-finding suite path)
  (Finding path
           (load-summary (load-program (::libraries suite) path))
           (order-comparison (::libraries suite) path)
           (expansion-comparison (::libraries suite) path)))

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
    ((Ok loaded)
     (match (::waiting loaded)
       ((Nil) "complete")
       (waiting (string-append "generated: " (string-join (map written-name waiting) " ")))))
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

;; ---- Main ----

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
  (for-each write-line (concatenate (map expansion-line findings)))
  (write-line (string-append "compared their expansion with the old: "
                             (string-join (map (lambda (kind) (expansion-count findings kind))
                                               expansion-kinds)
                                          ", ")))
  (if (any? (lambda (finding)
              (member? (::first (::expansion finding))
                       (list "fail alike first, several problems differ"
                             "fail differently"
                             "only the new fails"
                             "expansions differ")))
            findings)
      (panic "the expansions differ")
      (unit))
  (if (any? (lambda (finding) (string=? (order-kind (::order finding)) "other differences"))
            findings)
      (panic "the orders differ")
      (unit))
  (match (digest-difference)
    ((None) (write-line "compared the new SHA-256 with the old: no differences"))
    ((Some difference) (panic (string-append "the SHA-256 differs: " difference)))))
