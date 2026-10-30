(import
 (snail core base)
 (snail core io))

;; Two sibling fields may hold one declaration at different arguments
;; without that being recursion. A struct of two cells is a shared handle
;; whatever they hold, so it is duplicated freely, even holding a linear
;; value; one of two Options is dropped by glue that drops each.
(struct (Shared T)
  ((count (Ref I64))
   (current (Ref (Option T)))))

(: share (All (T) (-> (Shared T) (Pair (Shared T) (Shared T)))))
(define (share shared)
  (Pair shared shared))

(: run-current (-> (Shared (FnOnce Unit ! console)) Unit ! console mut))
(define (run-current shared)
  (ref-set! (Shared-count shared) (+ (ref-get (Shared-count shared)) 1))
  (match (ref-replace! (Shared-current shared) (None))
    ((Some work) (work))
    ((None) (write-line "nothing to run"))))

(match (share (Shared (ref 0) (ref (Some (once (lambda () (write-line "ran once")))))))
  ((Pair first second)
   (run-current first)
   (run-current second)
   (write-line (string-append "asked " (show (ref-get (Shared-count first))) " times"))))

(struct Handle
  ((name String)))

(instance (Drop (! console) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (write-line (string-append "released " name))))))

(struct Token
  ((id I64)))

(instance (Drop (! console) Token)
  (define (drop token)
    (match token
      ((Token id) (write-line (string-append "released token " (show id)))))))

(struct Two
  ((handle (Option Handle))
   (token (Option Token))))

(drop (Two (Some (Handle "h")) (Some (Token 1))))
