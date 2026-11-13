(import
 (snail core base)
 (snail core io))

(effect Log ((record-drop (Fn I64 → Unit))))
(struct Token
  ((value I64)))
(instance (Drop (! Log) Token)
  (define (drop (token Token)) (→ Unit) (! Log)
    (match token ((Token value) (record-drop value)))))

(define owner (→ (Rc Token)) (rc (Token 7)))
(struct Holder
  ((owner (Rc Token))))
(define holder (→ Holder) (Holder (rc (Token 11))))

(define (probe (weak (WeakRc Token))) (→ I64) (! mut Log)
  (match (weak-rc-upgrade weak)
    ((Some value) (● value value))
    ((None) -1)))

(define (main) (→ Unit) (! mut output-port)
  (handle Log ((record-drop (lambda (value) (write-line (string-append "drop " (show value))))))
    (let ((weak (rc-downgrade owner)))
      (drop owner)
      (drop owner)
      (write-line (show (probe weak))))
    (let ((weak (rc-downgrade (● holder owner))))
      (let ((alias (● holder owner)))
        (set! (● holder owner) (rc (Token 12)))
        (write-line (show (probe weak)))
        (drop alias))
      (write-line (show (probe weak))))
    (write-line (show (● holder owner value)))))
