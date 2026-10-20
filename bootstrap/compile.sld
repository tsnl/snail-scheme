;; The self-hosted compiler's entry program:
;;
;;   compile wat|schema SOURCE OUTPUT GENERATED [DIRECTORY ...]
;;
;; writes the WebAssembly text of the program SOURCE, or the schemas of its
;; wire types, to OUTPUT, finding its libraries in the DIRECTORY arguments.
;; A compiled program cannot run another, so the driver produces generated
;; libraries: their text is GENERATED/KEY.out, where KEY hashes the producer
;; program; when it is missing, the compiler writes the producer to
;; GENERATED/KEY.sld and stops with `generate KEY`.
(import
 (lofi base)
 (lofi io)
 (only (lofi compiler read) syntax->string)
 (only (lofi compiler core) fnv-1a)
 (lofi compiler))

(define (generated-text directory forms)
  (let* ((text (string-join (map syntax->string forms) "\n")) (key (i64->string (fnv-1a text)))
         (output (string-append directory "/" key ".out")))
    (if (file-exists? output)
        (read-file output)
        (begin (write-file (string-append directory "/" key ".sld") text)
               (panic (string-append "generate " key))))))

(match (command-line)
  ((Cons _ (Cons mode (Cons source (Cons output (Cons generated directories)))))
   (let ((generate (lambda (forms path) (generated-text generated forms))))
     (write-file output (if (string=? mode "schema")
                            (compile->schemas directories source generate)
                            (compile->wat directories source generate)))))
  (_ (panic "usage: compile wat|schema SOURCE OUTPUT GENERATED [DIRECTORY ...]")))
