(import
 (snail core base)
 (snail core io))

;; Recursive aggregate results cross suspension without fabricating an object.
;; Cancellation must never construct or release the incomplete source value.
(struct Knot
  ((children (Vector Knot))))

(effect Ask
  ((ctl ask (Fn I64 → I64))))

(struct Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (write-line (string-append "drop " (show value)))))))

(define (knot) (→ Knot) (! Ask)
  (ask 7)
  (Knot (vector)))

(define (counted) (→ (Rc Resource)) (! Ask)
  (rc (Resource (ask 8))))

(define (weak) (→ (WeakRc I64)) (! Ask mut)
  (rc-downgrade (rc (ask 9))))

(define (values) (→ (Vector (Rc Resource))) (! Ask mut output-port)
  (let ((first (rc (Resource 40))))
    (list->vector (list first (counted)))))

(define (main) (→ Unit) (! mut output-port)
  (display (handle Ask ((ask (lambda (value resume) (drop resume) value)))
             (knot)
             0))
  (newline)
  (display (handle Ask ((ask (lambda (value resume) (drop resume) value)))
             (counted)
             0))
  (newline)
  (display (handle Ask ((ask (lambda (value resume) (drop resume) value)))
             (weak)
             0))
  (newline)
  (display (handle Ask ((ask (lambda (value resume) (drop resume) value)))
             (vector-length (values))))
  (newline)
  ;; Normal completion publishes a real counted result. Its single release
  ;; follows the read; the inactive result from the first return owns nothing.
  (display (handle Ask ((ask (lambda (value resume) (resume (+ value 100)))))
             (let ((cell (counted))) (● cell value))))
  (newline)
  (display (handle Ask ((ask (lambda (value resume) (resume (+ value 200)))))
             (let ((items (values))) (+ (● (vector-ref items 0) value)
                                        (● (vector-ref items 1) value)))))
  (newline)
  (unit))
