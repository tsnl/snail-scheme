(import
 (snail core base)
 (snail core io))

;; Sibling instances of the same aggregate are searched independently.
;; Ordinary fields propagate linearity; Rc is the explicit shared owner.
(record (Shared T)
  ((count I64)
   (current (Option T))))

(define (share (shared (Rc (Shared T)))) (→ (Pair (Rc (Shared T)) (Rc (Shared T)))) (∀ (T))
  (new Pair (first shared) (second shared)))

(define (run-current (shared (Rc (Shared String)))) (→ Unit) (! output-port mut)
  (set! (● shared count) (+ (● shared count) 1))
  (match (replace! (● shared current) (None))
    ((Some text) (write-line text))
    ((None) (write-line "nothing to run"))))

(record Handle
  ((name String)))

(instance (Drop (! output-port) Handle)
  (define (drop (handle Handle)) (→ Unit) (! output-port)
    (match handle
      ((Handle name) (write-line (string-append "released " name))))))

(record Token
  ((id I64)))

(instance (Drop (! output-port) Token)
  (define (drop (token Token)) (→ Unit) (! output-port)
    (match token
      ((Token id) (write-line (string-append "released token " (show id)))))))

(record Two
  ((handle (Option Handle))
   (token (Option Token))))

(define (main) (→ Unit) (! mut output-port)

  (match (share (rc (new Shared (count 0) (current (Some "ran once")))))
    ((Pair first second)
     (run-current first)
     (run-current second)
     (write-line (string-append "asked " (show (● first count)) " times"))))
  (drop (new Two (handle (Some (new Handle (name "h")))) (token (Some (new Token (id 1))))))
  (unit))
