(import
 (snail core base)
 (snail core io))

;; A handle that says when it is released: its Drop instance performs
;; `log`, the row its head names, wherever a handle is dropped. The book's
;; ownership chapter includes the text between ANCHOR and ANCHOR_END.
;; ANCHOR: handle
(effect log
  ((say (-> String Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (say (string-append "released " name))))))
;; ANCHOR_END: handle

;; A token is linear by its declaration, and holds nothing to release.
(struct Token
  ((id I64))
  (deriving Move))

;; A generic drop needs the row of what it drops.
(: release-all (All (A e) (requires (Drop e A)) (-> (List A) Unit ! e)))
(define (release-all items)
  (drop items))

(: demo (-> Unit ! log))
(define (demo)
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

(handle log
    ((say (lambda (text) (write-line text))))
  (demo))
