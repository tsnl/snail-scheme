;; A pass names one operation per source arm. The visitor selects an arm;
;; callers explicitly arrange child dependencies and pass their results in.
;; There is deliberately no pass-composition or interleaving combinator.
(define-library (lofi pass)
  (export make-pass pass? visit-pass pass-conversion)
  (import
   (scheme base)
   (only (lofi ir) node-kind node-loc))
  (begin

    ;; ---- Arm operations and common dispatch ----

    (define-record-type pass
      (make-pass literal name lambda call block conditional annotation instantiation match binding conversion) pass?
      (literal pass-literal)
      (name pass-name)
      (lambda pass-lambda)
      (call pass-call)
      (block pass-block)
      (conditional pass-conditional)
      (annotation pass-annotation)
      (instantiation pass-instantiation)
      (match pass-match)
      (binding pass-binding)
      (conversion pass-conversion))
    (define (visit-pass pass node . inputs)
      (apply (case (node-kind node)
               ((literal) (pass-literal pass)) ((name) (pass-name pass))
               ((lambda) (pass-lambda pass)) ((call) (pass-call pass))
               ((block) (pass-block pass)) ((if) (pass-conditional pass))
               ((annotation) (pass-annotation pass)) ((instantiation) (pass-instantiation pass))
               ((match) (pass-match pass)) ((bind) (pass-binding pass))
               (else (error "unsupported strict expression" (node-loc node) (node-kind node))))
             node inputs))))
