;; Bounded model checking of total state machines. From an initial state,
;; every move a state allows is applied, breadth first and up to a depth, and
;; the first state that breaks the invariant is reported with the moves that
;; reach it. A state is identified by its wire encoding, so each distinct
;; state is checked once, and the reported path is a shortest one.
(define-library (snail shell explore)
  (export
   Violation
   explore)
  (import
   (snail core base)
   (snail core table)
   (snail shell wire))
  (begin

    (struct (Violation S M)
      ((reason String)
       (moves (List M))
       (state S)))

    ;; A state with the moves that reached it, newest first.
    (struct (Visit S M)
      ((state S)
       (path (List M))))

    ;; `moves` lists what may happen in a state, `step` applies one, and
    ;; `invariant` explains why a state is wrong, if it is.

    (define (explore (initial S)
                     (moves (Fn S → (List M)))
                     (step (Fn S M → S))
                     (invariant (Fn S → (Option String)))
                     (depth I64))
      (→ (Option (Violation S M)))
      (∀ S M)
      (⊨ (Serialize S) (Copy S) (Copy M))
      (search (list (Visit initial (Nil)))
              moves
              step
              invariant
              depth
              (table-set empty-table (state-key initial) #t)))

    ;; Checks one frontier, then the states its moves reach for the first
    ;; time. `seen` holds every state reached so far.

    (define (search (frontier (List (Visit S M)))
                    (moves (Fn S → (List M)))
                    (step (Fn S M → S))
                    (invariant (Fn S → (Option String)))
                    (depth I64)
                    (seen (Table Bool)))
      (→ (Option (Violation S M)))
      (∀ S M)
      (⊨ (Serialize S) (Copy M) (Copy S))
      (match (first-violation frontier invariant)
        ((Some violation) (Some violation))
        ((None)
         (if (or (= depth 0) (null? frontier))
             (None)
             (match (successors frontier moves step seen)
               ((Pair next seen) (search next moves step invariant (- depth 1) seen)))))))

    (define (first-violation (frontier (List (Visit S M)))
                             (invariant (Fn S → (Option String))))
      (→ (Option (Violation S M)))
      (∀ S M)
      (⊨ (Copy M) (Copy S))
      (match frontier
        ((Nil) (None))
        ((Cons visit rest)
         (match (invariant (● visit state))
           ((Some reason)
            (Some (Violation reason (reverse (● visit path)) (● visit state))))
           ((None) (first-violation rest invariant))))))

    ;; The states the frontier reaches for the first time, with `seen`
    ;; grown by them.

    (define (successors (frontier (List (Visit S M)))
                        (moves (Fn S → (List M)))
                        (step (Fn S M → S))
                        (seen (Table Bool)))
      (→ (Pair (List (Visit S M)) (Table Bool)))
      (∀ S M)
      (⊨ (Serialize S) (Copy M) (Copy S))
      (match (fold-left (lambda (found visit)
                          (fold-left (lambda (found move)
                                       (let* ((state (step (● visit state) move))
                                              (key (state-key state)))
                                         (match found
                                           ((Pair next seen)
                                            (if (table-contains? seen key)
                                                found
                                                (Pair
                                                 (Cons (Visit state (Cons move (● visit path)))
                                                       next)
                                                 (table-set seen key #t)))))))
                                     found (moves (● visit state))))
                        (Pair (Nil) seen) frontier)
        ((Pair next seen) (Pair (reverse next) seen))))

    ;; The encoding as text, one character per byte, to key the table.

    (define (state-key (state S)) (→ String) (∀ S) (⊨ (Serialize S) (Copy S))
      (let ((bytes (serialize state)))
        (string-generate (vector-length bytes)
                         (lambda (index) (i32->char (u8->i32 (vector-ref bytes index)))))))

    ))
