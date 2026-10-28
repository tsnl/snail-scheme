;; The compiled compiler's synchronous entry.
(import
 (snail core base)
 (snail core io)
 (snail shell compiler driver))

(: compile-source (-> Unit ! mut fs))
(define (compile-source)
  (compile-command-line))

(expose compile-source "compiler-compile")

(unit)
