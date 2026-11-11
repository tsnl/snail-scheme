(import
 (snail core base)
 (snail core io))

(effect audit
  ((note (dyn (Fn String → Unit)))))
(struct Resource
  ((name String)))
(instance (Drop (! audit) Resource)
  (define drop
    (lambda (resource) (match resource ((Resource name) (note (string-append "drop " name)))))))
(define (integer (value Any)) (→ I64) (! dyn-cast) value)

;; Cleanup alone justifies audit; there is no textual drop in this body.
(define (aborting) (→ Unit) (! dyn-cast audit)
  (let ((first (Resource "first")))
    (let ((second (Resource "second")))
      (integer "bad")
      (panic "unreachable"))))

;; The same cleanup row is inferred without an annotation.
(define inferred-cleanup
  (lambda () (let ((resource (Resource "inferred")))
               (integer "bad")
               (panic "unreachable"))))

;; Catching the conversion still leaves the resource's audit effect to infer.
(define inferred-caught-cleanup
  (lambda () (handle dyn-cast ((conversion-failed (lambda (_) (unit))))
               (let ((resource (Resource "inferred caught")))
                 (integer "bad")
                 (panic "unreachable")))))

(define (consume (resource Resource) (a I64) (b I64)) (→ Unit) (! audit)
  (drop resource))
(define (later) (→ I64) (! console) (write-line "unreachable argument") 0)

(handle audit ((note (lambda (text) (write-line text))))
  (handle dyn-cast ((conversion-failed (lambda (_) (write-line "caught"))))
    (aborting))
  (handle dyn-cast ((conversion-failed (lambda (_) (write-line "inferred caught"))))
    (inferred-cleanup))
  (inferred-caught-cleanup)
  ;; The first operand becomes an owned temporary before the second fails.
  (handle dyn-cast ((conversion-failed (lambda (_) (write-line "arguments caught"))))
    (consume (Resource "argument") (integer "bad") (later)))
  ;; A locally caught abort leaves an owner outside the handle alive.
  (let ((outside (Resource "outside")))
    (handle dyn-cast ((conversion-failed (lambda (_) (unit))))
      (integer "bad")
      (unit))
    (write-line "outside remains")
    (drop outside))
  ;; A branch that never mentions its owner must still release it.
  (let ((conditional (Resource "conditional")))
    (handle dyn-cast ((conversion-failed (lambda (_) (write-line "branch caught"))))
      (if #t
          (begin (integer "bad") (panic "unreachable"))
          (drop conditional)))))

;; Local handlers discharge cleanup effects too; the exported function is pure.
(define (pure-cleanup) (→ I64)
  (let ((count (ref 0)))
    (handle audit ((note (lambda (_) (ref-set! count (+ 1 (ref-get count))))))
      (handle dyn-cast ((conversion-failed (lambda (_) (unit))))
        (let ((resource (Resource "local")))
          (ann (ann "bad" Any) I64)
          (panic "unreachable"))))
    (ref-get count)))
(write-line (show (pure-cleanup)))

(handle dyn-cast ((conversion-failed (lambda (_) (write-line "outer catch"))))
  (handle audit ((note (lambda (text) (write-line (string-append "inner: " text)))))
    (let ((resource (Resource "nested")))
      (integer "bad")
      (panic "unreachable"))))
