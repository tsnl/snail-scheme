;; The self-hosted compiler's entry program:
;;
;;   compile SOURCE OUTPUT [DIRECTORY ...]
;;
;; writes the WebAssembly text of the program SOURCE to OUTPUT, finding its
;; libraries in the DIRECTORY arguments. A generated library needs a host that
;; can compile and run its producer, so only the Chibi host supports one.
(import
 (lofi base)
 (lofi io)
 (lofi compiler))

(match (command-line)
  ((Cons _ (Cons source (Cons output directories)))
   (write-file output (compile->wat directories source (lambda (forms path) (panic "a generated library needs the Chibi host")))))
  (_ (panic "usage: compile SOURCE OUTPUT [DIRECTORY ...]")))
