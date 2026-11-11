(import
 (snail core base)
 (snail core io))

;; Two sibling fields may hold one declaration at different arguments
;; without that being recursion. A struct of two cells is a shared handle,
;; so it is duplicated freely; the second taker finds the content gone.
(struct (Shared T)
  ((count (Ref I64))
   (current (Ref (Option T)))))

(define (share (shared (Shared T))) (→ (Pair (Shared T) (Shared T))) (∀ T)
  (Pair shared shared))

(define (run-current (shared (Shared String))) (→ Unit) (! console mut)
  (ref-set! (● shared count) (+ (ref-get (● shared count)) 1))
  (match (ref-replace! (● shared current) (None))
    ((Some text) (write-line text))
    ((None) (write-line "nothing to run"))))

(match (share (Shared (ref 0) (ref (Some "ran once"))))
  ((Pair first second)
   (run-current first)
   (run-current second)
   (write-line (string-append "asked " (show (ref-get (● first count))) " times"))))

(struct Handle
  ((name String)))

(instance (Drop (! console) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (write-line (string-append "released " name)))))))

(struct Token
  ((id I64)))

(instance (Drop (! console) Token)
  (define drop
    (lambda (token) (match token
                      ((Token id) (write-line (string-append "released token " (show id))))))))

(struct Two
  ((handle (Option Handle))
   (token (Option Token))))

(drop (Two (Some (Handle "h")) (Some (Token 1))))
