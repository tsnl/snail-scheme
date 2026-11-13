(import
 (snail core base)
 (snail core io))

(struct Trace
  ((text String)))

(define (assert (condition Bool)) (→ Unit)
  (unless condition (panic "conversion probe assertion failed")))

(define (input (trace Trace) (label String) (value Any)) (→ Any) (! mut)
  (set! (● trace text) (string-append (● trace text) label))
  value)

(define (text (value Any)) (→ String)
  (match (try-convert value String)
    ((Ok value) (string-append "text: " value))
    (_ "missing")))

(struct Example
  ((left Any)
   (right Any)
   (expected String)))

;; A successful conversion does not imply that its nested pattern matches.
(struct Point
  ((x I64)
   (y I64)))

;; A right-hand abort still happens after a failed left probe. Ownership
;; sees that exit and releases the surrounding resource before handling it.
(effect Stop ((ctl stop (Fn → Never))))

(struct Resource
  ())

(instance (Drop (! output-port) Resource)
  (define drop (lambda (resource) (match resource ((Resource) (write-line "released"))))))

(define (right (trace Trace)) (→ Any) (! mut Stop)
  (set! (● trace text) (string-append (● trace text) "R"))
  (absurd (stop)))

(define main
  (lambda ()
    (assert (string=? (text "yes") "text: yes"))
    (assert (string=? (text 1) "missing"))
    ;; Both inputs run once, left to right, for all four outcomes. Successful
    ;; operands are used at their concrete types without a dyn-cast effect.
    (for-each
     (lambda (example)
       (let* ((trace (Trace ""))
              (result (match (Pair (try-convert (input trace "L" (● example left)) I64)
                                   (try-convert (input trace "R" (● example right)) String))
                        ((Pair (Ok left) (Ok right)) (string-append (show left) right))
                        (_ "missing"))))
         (assert (string=? (● trace text) "LR"))
         (assert (string=? result (● example expected)))))
     (list (Example 2 "yes" "2yes") (Example 2 #f "missing")
           (Example #f "yes" "missing") (Example #f #f "missing")))
    ;; Escaping results and observed errors keep their ordinary representation.
    (let ((result (try-convert (ann #f Any) I64)))
      (assert (match result
                ((Err error)
                 (and (string=? (string-join (● error expected) ",") "I64")
                      (match (● error reason) ((TypeMismatch) #t) (_ #f))))
                (_ #f))))
    (assert (match (try-convert (ann #f Any) I64)
              ((Ok value) (= value 0))
              ((Err error) (= (● error argument) -1))))
    (assert (match (try-convert (ann (Point 1 2) Any) Point)
              ((Ok (Point 0 y)) #f)
              (_ #t)))
    (assert (match (try-convert (ann (Point 1 2) Any) Point)
              ((Ok point) (= (+ (● point x) (● point y)) 3))
              (_ #f)))
    (assert (match (try-convert (ann "identity" Any) Any)
              ((Ok value) (type-test value String))
              (_ #f)))
    (let ((trace (Trace "")))
      (handle Stop ((stop (lambda ()
                            (set! (● trace text) (string-append (● trace text) " caught")))))
        (let ((resource (Resource)))
          (match (Pair (try-convert (input trace "L" #f) I64)
                       (try-convert (right trace) String))
            ((Pair (Ok left) (Ok right)) (unit))
            (_ (unit)))
          (drop resource)))
      (assert (string=? (● trace text) "LR caught")))
    (write-line "checked probes passed")
    (unit)))
