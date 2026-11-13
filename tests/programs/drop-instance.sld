(import
 (snail core base)
 (snail core io))

;; A handle that says when it is released: its Drop instance performs
;; `log`, the row its head names, wherever a handle is dropped. The book's
;; ownership chapter includes the text between ANCHOR and ANCHOR_END.
;; ANCHOR: handle
(effect log
  ((say (Fn String → Unit))))

(record Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define (drop (handle Handle)) (→ Unit) (! log)
    (match handle
      ((Handle name) (say (string-append "released " name))))))

;; ANCHOR_END: handle

;; A token is linear by its declaration, and holds nothing to release.
(record Token
  ((id I64))
  )
(instance (Drop (!) Token)
  (define (drop (value Token)) (→ Unit)
    (match value ((Token _) (unit)))))

;; A generic drop needs the row of what it drops.
(define (release-all (items (List A))) (→ Unit) (! e) (∀ (A e)) (⊨ (Drop e A))
  (drop items))

(define (demo) (→ Unit) (! log)
  (drop (new Handle (name "one")))
  ;; Glue drops each linear field, in order.
  (drop (new Pair (first (new Handle (name "two"))) (second (new Handle (name "three")))))
  (drop (list (new Handle (name "four")) (new Handle (name "five"))))
  (drop (Some (new Handle (name "six"))))
  (release-all (list (new Handle (name "seven")) (new Handle (name "eight"))))
  ;; Nothing to run.
  (drop (new Token (id 9)))
  (drop (once (lambda () (say "never called"))))
  (say "done"))

(define (main) (→ Unit) (! output-port)
  (handle log
      ((say (lambda (text) (write-line text))))
    (demo))
  (unit))
