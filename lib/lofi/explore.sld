;; Bounded model checking of total state machines. From an initial state,
;; every move a state allows is applied, breadth first and up to a depth, and
;; the first state that breaks the invariant is reported with the moves that
;; reach it. A state is identified by its wire encoding, so each distinct
;; state is checked once, and the reported path is a shortest one.
(define-library (lofi explore)
  (export
   Violation
   Violation-reason
   Violation-moves
   Violation-state
   explore)
  (import
   (lofi base)
   (lofi table)
   (lofi wire))
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
    ;; `invariant` explains why a state is wrong, if it is. The table of seen
    ;; states is local to the search, so the search is total.
    (: explore (All (S M) (requires (Serialize S))
                    (-> S (-> S (List M)) (-> S M S) (-> S (Option String)) I64 (Option (Violation S M)))))
    (define (explore initial moves step invariant depth)
      (unsafe-total
       (lambda ()
         (let ((seen (make-table)))
           (table-set! seen (state-key initial) #t)
           (search (list (Visit initial (Nil))) moves step invariant depth seen)))))

    ;; Checks one frontier, then the states its moves reach for the first
    ;; time.
    (: search (All (S M) (requires (Serialize S))
                   (-> (List (Visit S M)) (-> S (List M)) (-> S M S) (-> S (Option String)) I64 (Table Bool)
                       (Option (Violation S M)) ! mut)))
    (define (search frontier moves step invariant depth seen)
      (match (first-violation frontier invariant)
        ((Some violation) (Some violation))
        ((None)
         (if (or (= depth 0) (null? frontier))
             (None)
             (search (successors frontier moves step seen) moves step invariant (- depth 1) seen)))))

    (: first-violation (All (S M) (-> (List (Visit S M)) (-> S (Option String)) (Option (Violation S M)))))
    (define (first-violation frontier invariant)
      (match frontier
        ((Nil) (None))
        ((Cons visit rest)
         (match (invariant (Visit-state visit))
           ((Some reason) (Some (Violation reason (reverse (Visit-path visit)) (Visit-state visit))))
           ((None) (first-violation rest invariant))))))

    (: successors (All (S M) (requires (Serialize S))
                       (-> (List (Visit S M)) (-> S (List M)) (-> S M S) (Table Bool) (List (Visit S M)) ! mut)))
    (define (successors frontier moves step seen)
      (reverse
       (fold-left (lambda (next visit)
                    (fold-left (lambda (next move)
                                 (let* ((state (step (Visit-state visit) move)) (key (state-key state)))
                                   (if (table-contains? seen key)
                                       next
                                       (begin (table-set! seen key #t) (Cons (Visit state (Cons move (Visit-path visit))) next)))))
                               next (moves (Visit-state visit))))
                  (Nil) frontier)))

    ;; The encoding as text, one character per byte, to key the table.
    (: state-key (All (S) (requires (Serialize S)) (-> S String)))
    (define (state-key state)
      (let ((bytes (serialize state)))
        (string-generate (vector-length bytes) (lambda (index) (i32->char (u8->i32 (vector-ref bytes index)))))))

    ))
