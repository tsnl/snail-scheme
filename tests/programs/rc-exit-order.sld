(import
 (snail core base)
 (snail core io))

(record Resource
  ((number I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource
      ((Resource number) (write-line (string-append "drop " (show number)))))))

(define (accept (number I64)) (→ Unit) (! output-port)
  (write-line (string-append "accept " (show number))))

(define (callee) (→ (Fn I64 → Unit ! output-port)) (! output-port)
  (write-line "callee")
  accept)

(define (argument) (→ I64) (! output-port)
  (write-line "argument")
  9)

;; Outgoing operands run before any lexical release. Both alternatives
;; release their inner scopes before the parameter and then tail-transfer.
(define (transfer (outer (Rc Resource)) (choose Bool)) (→ Unit) (! mut output-port)
  (let ((inner (rc (new Resource (number 20)))))
    (if choose
        ((callee) (argument))
        (match (Some (rc (new Resource (number 30))))
          ((Some matched) (accept (● matched number)))
          ((None) (accept 0))))))

;; Observation must read the result before the receiver's last release.
(define (observe) (→ I64) (! mut output-port)
  (let ((outer (rc (new Resource (number 40)))))
    (let ((inner (rc (new Resource (number 50)))))
      (if #t (● inner number) (● outer number)))))

;; An activation's closure owner follows its locals. No enclosing binding
;; keeps this closure alive after the immediate invocation.
(define (make-call) (→ (Fn → Unit ! mut output-port))
  (let ((captured (rc (new Resource (number 60)))))
    (lambda ()
      (let ((inner (rc (new Resource (number 70)))))
        (accept (● captured number))))))

(define (main) (→ Unit) (! mut output-port)
  (transfer (rc (new Resource (number 10))) #t)
  (transfer (rc (new Resource (number 10))) #f)
  (accept (observe))
  ((make-call))
  (unit))
