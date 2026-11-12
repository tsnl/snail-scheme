(import
 (snail core base)
 (snail core io))

;; `clone` duplicates a value: it answers the value and a copy, and
;; performs what copying it does. The book's ownership chapter includes
;; the text between ANCHOR and ANCHOR_END.
(effect log
  ((say (Fn String → Unit))))

;; ANCHOR: ticket
;; A ticket is linear by its Drop instance, so only its Clone instance
;; copies one, and says so.
(struct Ticket
  ((seat I64)))

(instance (Drop (! log) Ticket)
  (define drop
    (lambda (ticket) (match ticket
                       ((Ticket seat) (say (string-append "returned seat " (i64->string seat))))))))

(instance (Clone (! log) Ticket)
  (define clone
    (lambda (ticket) (match ticket
                       ((Ticket seat)
                        (say (string-append "copied seat " (i64->string seat)))
                        (Pair (Ticket seat) (Ticket (+ seat 100))))))))

;; ANCHOR_END: ticket

;; A generic wrapper's instance copies what it holds in the row `e` of its
;; requirement.
(struct (Tagged A)
  ((tag String)
   (item A)))

(instance (Clone (! log e) (Tagged A))
  (⊨ (Clone e A))
  (define clone
    (lambda (tagged) (match tagged
                       ((Tagged tag item)
                        (say (string-append "copying " tag))
                        (match (clone item)
                          ((Pair a b)
                           (Pair (Tagged tag a) (Tagged (string-append tag "'") b)))))))))

;; A generic definition requires (Clone e A).
(define (twin (value A)) (→ (Pair A A)) (! e) (∀ A e) (⊨ (Clone e A))
  (clone value))

(define (demo) (→ Unit) (! log output-port)
  (match (clone (Ticket 1))
    ((Pair a b) (drop a) (drop b)))
  ;; Glue clones the linear fields and shares the others.
  (match (clone (Pair (Ticket 2) "row two"))
    ((Pair (Pair a label) (Pair b same))
     (write-line (string-append label ", " same))
     (drop a)
     (drop b)))
  (match (clone (list (Ticket 3) (Ticket 4)))
    ((Pair tickets copies) (drop tickets) (drop copies)))
  ;; An unrestricted value is shared.
  (match (twin "shared")
    ((Pair x y) (write-line (string-append x " and " y))))
  (match (twin (Ticket 5))
    ((Pair a b) (drop a) (drop b)))
  (match (clone (Tagged "t" (Ticket 6)))
    ((Pair (Tagged first a) (Tagged second b))
     (write-line (string-append first ", " second))
     (drop a)
     (drop b)))
  ;; An instance runs for an unrestricted type too.
  (match (clone (Tagged "n" 7))
    ((Pair (Tagged first x) (Tagged second y))
     (write-line (string-append first " " (i64->string x) ", " second " " (i64->string y))))))

(define main
  (lambda ()
    (handle log
        ((say (lambda (text) (write-line text))))
      (demo))
    (unit)))
