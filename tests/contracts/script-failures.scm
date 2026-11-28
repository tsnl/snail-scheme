;; A script build that fails reports the error it met and keeps nothing it
;; made: the generation it created is discarded, and the output of an
;; earlier build stays published, as `snail-scheme build` shows from outside.
;;
;;   ./snail-scheme run --target node tests/contracts/script-failures.scm ROOT
(import
 (snail core base)
 (snail core io)
 (snail shell process)
 (contracts support))

(define (build (c Context) (project String)) (→ Ran)
  (snail c (list "build" "--target" "node" "main.scm") project))

;; What the project's build directory holds, hidden names included.
(define (inventory (c Context) (project String)) (→ (List String))
  (match (list-directory (● c fs) (string-append project "/build"))
    ((Ok names) (list-sort string<? names))
    ((Err why) (panic (string-append "no build directory: " (show why))))))

(define (link-target (c Context) (path String)) (→ String)
  (first-line (● (succeeded (command c "readlink" (list path) "/" "") "readlink") stdout)))

(define (same-names? (a (List String)) (b (List String))) (→ Bool)
  (string=? (string-join (list-sort string<? a) "\n") (string-join (list-sort string<? b) "\n")))

;; The checker's solver finds a class with no instance; that error reaches
;; the user through a build as a type error does.
(define (errors (c Context) (project String)) (→ Unit)
  (make-directories (● c fs) (string-append project "/src"))
  (put! c (string-append project "/main.scm")
        "(import (snail core base)) (define (main) (→ Unit) (ann \"wrong type\" I64) (unit))")
  (failed-with (build c project) "expected I64, found String" "a type error")
  (put! c
        (string-append project "/main.scm")
        (text-of c (string-append (● c root) "/tests/programs/error-instance.sld")))
  (failed-with (build c project)
               (first-line
                (text-of c (string-append (● c root) "/tests/programs/error-instance.err")))
               "a class with no instance")
  (expect (null? (inventory c project)) "a failed build discards the generation it created"))

;; A producer reads real input files when the build runs it, and is compiled
;; and run in private compiler scratch, so the workspace's build directory
;; holds only the script's generation and its link.
(define (producers (c Context) (project String)) (→ Unit)
  (put! c (string-append project "/main.scm")
        "(import (snail core base) (generated flag)) (define (main) (→ Unit) (ann (value) String) (unit))")
  (put! c (string-append project "/flag.txt") "valid")
  (put! c (string-append project "/src/generated/flag.sld")
        (string-append
         "(generate-library (generated flag)\n"
         "  (import (snail core base) (snail core io) (snail shell syntax))\n"
         "  (lambda ((fs Fs))\n"
         "    (library-syntax (list \"generated\" \"flag\") (list \"value\") (list (list \"snail\" \"core\" \"base\"))\n"
         "      (list (form \"define\" (list (form \"value\" (Nil))\n"
         "        (form \"→\" (list (SymbolSyntax \"String\")))\n"
         "          (if (string=? (read-file fs \"" project "/flag.txt\") \"valid\")\n"
         "            (StringSyntax \"ok\") (SymbolSyntax \"unknown-generated-name\"))))))))"))
  (succeeded (build c project) "the producer's build")
  (let ((published (link-target c (string-append project "/build/main"))))
    (expect (same-names? (inventory c project) (list published "main"))
            "the build directory holds the generation and its link")
    (expect
     (same-names? (match (list-directory (● c fs) (string-append project "/build/" published))
                    ((Ok names) names)
                    ((Err _) (Nil)))
                  (list ".snail-target" "host" "main.mjs" "main.wasm" "package.json"))
     "producer programs use private compiler scratch")
    (put! c (string-append project "/flag.txt") "invalid")
    (failed-with (build c project) "unknown-generated-name" "a producer that fails")
    (expect (same-names? (inventory c project) (list published "main"))
            "a failed build leaves the published generation")
    (expect-text (link-target c (string-append project "/build/main")) published "and its link")))

(define (main (arguments Arguments)
              (fs Fs)
              (processes Processes)
              (environment ProcessEnvironment)
              (out OutputPort))
  (→ Unit)
  (let* ((c (context arguments fs processes environment))
         (project (scratch c "failures-workspace")))
    (errors c project)
    (producers c project)
    (removed! c project)
    (write-line out "script failures passed")))
