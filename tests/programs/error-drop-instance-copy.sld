(import
 (snail core base)
 (snail core io))

;; A Drop instance that requires (Copy A) plans its body's drops with A
;; unrestricted, so dropping the pair is free there. Used at a Handle, it
;; would release one handle twice.
(effect log
  ((say (Fn String → Unit))))

(record Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define (drop (handle Handle)) (→ Unit) (! log)
    (match handle
      ((Handle name) (say (string-append "released " name))))))

(record (Wrapper A)
  ((item A)))

(instance (Drop (! log) (Wrapper A))
  (⊨ (Copy A))
  (define (drop (wrapper (Wrapper A))) (→ Unit) (! log)
    (match wrapper
      ((Wrapper item) (drop (new Pair (first item) (second item)))))))

(define (demo) (→ Unit) (! log)
  (drop (new Wrapper (item (new Handle (name "h"))))))

(define main
  (lambda ()
    (handle log
        ((say (lambda (text) (write-line text))))
      (demo))
    (unit)))
