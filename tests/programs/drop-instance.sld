(import
 (snail core base)
 (snail core io))

;; A handle that says when it is released: its Drop instance performs
;; `log`, the row its head names, wherever a handle is dropped. The book's
;; ownership chapter includes the text between ANCHOR and ANCHOR_END.
;; ANCHOR: handle
(effect log
  ((say (Fn String → Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (say (string-append "released " name)))))))

;; ANCHOR_END: handle

;; A token is linear by its declaration, and holds nothing to release.
(struct Token
  ((id I64))
  )
(instance (Drop (!) Token)
  (define (drop (value Token)) (→ Unit)
    (match value ((Token _) (unit)))))

;; A generic drop needs the row of what it drops.
(define (release-all (items (List A))) (→ Unit) (! e) (∀ (A e)) (⊨ (Drop e A))
  (drop items))

(define (demo) (→ Unit) (! log)
  (drop (Handle "one"))
  ;; Glue drops each linear field, in order.
  (drop (Pair (Handle "two") (Handle "three")))
  (drop (list (Handle "four") (Handle "five")))
  (drop (Some (Handle "six")))
  (release-all (list (Handle "seven") (Handle "eight")))
  ;; Nothing to run.
  (drop (Token 9))
  (drop (once (lambda () (say "never called"))))
  (say "done"))

(define (main) (→ Unit) (! output-port)
  (handle log
      ((say (lambda (text) (write-line text))))
    (demo))
  (unit))
