;; The self-hosted compiler's entry program:
;;
;;   compile wat|modules|schema SOURCE OUTPUT GENERATED [DIRECTORY ...]
;;
;; writes the WebAssembly text of the program SOURCE, or the schemas of its
;; wire types, to OUTPUT, finding its libraries in the DIRECTORY arguments.
;; `modules` writes one module per library into the directory OUTPUT, as
;; NAME.wat, and their names in program order, one to a line, to
;; OUTPUT/modules.
;; A compiled program cannot run another, so the driver produces generated
;; libraries: the syntax a producer writes is GENERATED/KEY.syntax, where KEY
;; hashes the producer program; when it is missing, the compiler writes the
;; producer to GENERATED/KEY.sld, writes KEY to GENERATED/request, and stops.
;; The request file, never a diagnostic's text, asks the driver to produce it.
(import
 (lofi base)
 (lofi io)
 (only (lofi compiler read) syntax->string)
 (only (lofi compiler core) fnv-1a)
 (lofi compiler))

(define (generated-syntax directory forms)
  (let* ((text (string-join (map syntax->string forms) "\n")) (key (i64->string (fnv-1a text)))
         (output (string-append directory "/" key ".syntax")))
    (if (file-exists? output)
        (read-bytes output)
        (begin (write-file (string-append directory "/" key ".sld") text)
               (write-file (string-append directory "/request") key)
               (panic "a generated library was requested")))))

(define (write-modules directory modules)
  (for-each (lambda (module) (write-file (string-append directory "/" (Pair-first module) ".wat") (Pair-second module))) modules)
  (write-file (string-append directory "/modules") (string-concatenate (map (lambda (module) (string-append (Pair-first module) "\n")) modules))))

(define (compile-source mode source output generate directories)
  (cond ((string=? mode "schema") (write-file output (compile->schemas directories source generate)))
        ((string=? mode "modules") (write-modules output (compile->modules directories source generate)))
        (else (write-file output (compile->wat directories source generate)))))

(match (command-line)
  ((Cons _ (Cons mode (Cons source (Cons output (Cons generated directories)))))
   (compile-source mode source output (lambda (forms) (generated-syntax generated forms)) directories))
  (_ (panic "usage: compile wat|modules|schema SOURCE OUTPUT GENERATED [DIRECTORY ...]")))
