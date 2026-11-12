(import
 (snail core base)
 (snail core io))

;; Sibling instances of the same aggregate are searched independently.
;; Ordinary fields propagate linearity; Rc is the explicit shared owner.
(struct (Shared T)
  ((count I64)
   (current (Option T))))

(define (share (shared (Rc (Shared T)))) (→ (Pair (Rc (Shared T)) (Rc (Shared T)))) (∀ T)
  (Pair shared shared))

(define (run-current (shared (Rc (Shared String)))) (→ Unit) (! output-port mut)
  (set! (● shared count) (+ (● shared count) 1))
  (match (replace! (● shared current) (None))
    ((Some text) (write-line text))
    ((None) (write-line "nothing to run"))))

(struct Handle
  ((name String)))

(instance (Drop (! output-port) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (write-line (string-append "released " name)))))))

(struct Token
  ((id I64)))

(instance (Drop (! output-port) Token)
  (define drop
    (lambda (token) (match token
                      ((Token id) (write-line (string-append "released token " (show id))))))))

(struct Two
  ((handle (Option Handle))
   (token (Option Token))))

(define main
  (lambda ()
    (match (share (rc (Shared 0 (Some "ran once"))))
      ((Pair first second)
       (run-current first)
       (run-current second)
       (write-line (string-append "asked " (show (● first count)) " times"))))
    (drop (Two (Some (Handle "h")) (Some (Token 1))))
    (unit)))
