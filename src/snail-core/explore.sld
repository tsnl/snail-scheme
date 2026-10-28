;; Bounded model checking of total state machines. From an initial state,
;; every move a state allows is applied, breadth first and up to a depth, and
;; the first state that breaks the invariant is reported with the moves that
;; reach it. A state is identified by its wire encoding, so each distinct
;; state is checked once, and the reported path is a shortest one.
(define-library (snail-core explore)
  (export
   Violation
   Violation-reason
   Violation-moves
   Violation-state
   explore)
  (import
   (snail-core base)
   (snail-core table)
   (snail-core wire))
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
    (: explore (All (S M) (requires (Serialize S))
                    (-> S
                        (-> S (List M))
                        (-> S M S)
                        (-> S (Option String))
                        I64
                        (Option (Violation S M)))))
    (define (explore initial moves step invariant depth)
      (search (list (Visit initial (Nil)))
              moves
              step
              invariant
              depth
              (table-set empty-table (state-key initial) #t)))

    ;; Checks one frontier, then the states its moves reach for the first
    ;; time. `seen` holds every state reached so far.
    (: search (All (S M) (requires (Serialize S))
                   (-> (List (Visit S M))
                       (-> S (List M))
                       (-> S M S)
                       (-> S (Option String))
                       I64
                       (Table Bool)
                       (Option (Violation S M)))))
    (define (search frontier moves step invariant depth seen)
      (match (first-violation frontier invariant)
        ((Some violation) (Some violation))
        ((None)
         (if (or (= depth 0) (null? frontier))
             (None)
             (match (successors frontier moves step seen)
               ((Pair next seen) (search next moves step invariant (- depth 1) seen)))))))

    (: first-violation
       (All (S M) (-> (List (Visit S M)) (-> S (Option String)) (Option (Violation S M)))))
    (define (first-violation frontier invariant)
      (match frontier
        ((Nil) (None))
        ((Cons visit rest)
         (match (invariant (Visit-state visit))
           ((Some reason)
            (Some (Violation reason (reverse (Visit-path visit)) (Visit-state visit))))
           ((None) (first-violation rest invariant))))))

    ;; The states the frontier reaches for the first time, with `seen`
    ;; grown by them.
    (: successors (All (S M) (requires (Serialize S))
                       (-> (List (Visit S M))
                           (-> S (List M))
                           (-> S M S)
                           (Table Bool)
                           (Pair (List (Visit S M)) (Table Bool)))))
    (define (successors frontier moves step seen)
      (match (fold-left (lambda (found visit)
                          (fold-left (lambda (found move)
                                       (let* ((state (step (Visit-state visit) move))
                                              (key (state-key state)))
                                         (match found
                                           ((Pair next seen)
                                            (if (table-contains? seen key)
                                                found
                                                (Pair
                                                 (Cons (Visit state (Cons move (Visit-path visit)))
                                                       next)
                                                 (table-set seen key #t)))))))
                                     found (moves (Visit-state visit))))
                        (Pair (Nil) seen) frontier)
        ((Pair next seen) (Pair (reverse next) seen))))

    ;; The encoding as text, one character per byte, to key the table.
    (: state-key (All (S) (requires (Serialize S)) (-> S String)))
    (define (state-key state)
      (let ((bytes (serialize state)))
        (string-generate (vector-length bytes)
                         (lambda (index) (i32->char (u8->i32 (vector-ref bytes index)))))))

    ))
