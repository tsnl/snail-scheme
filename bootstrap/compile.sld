;; The compiled compiler's synchronous entry and its post-exit request hook.
(import
 (snail core base)
 (snail core io)
 (snail shell compiler driver))

(: publish-request (-> Unit ! mut fs))
(define (publish-request)
  (publish-compiler-request!))

(: compile-source (-> Unit ! mut fs))
(define (compile-source)
  (compile-command-line))

(expose publish-request "compiler-request")
(expose compile-source "compiler-compile")

(unit)
