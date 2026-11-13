;; A named operation is independent of how a person invokes it. A palette,
;; button or keyboard binding selects a name; the application dispatches it
;; through its message loop. Actions can be Scheme functions returning work.
(define-library (snail shell ui commands)
  (export Command Registry register named)
  (import
   (snail core base)
   (snail core table))
  (begin

    ;; ---- Registration ----

    (struct (Command A)
      ((name String)
       (action A)))

    (struct (Registry A)
      ((commands (Vector (Command A)))))

    (define (register (commands (Vector (Command A))))
      (→ (Result (Registry A) String))
      (! e) (∀ (A e))
      (⊨ (Copy A) (Drop e A))
      (let loop ((index 0) (names (ann (empty-table) (Table Bool))))
        (if (= index (vector-length commands)) (Ok (Registry commands))
            (let ((name (● (vector-ref commands index) name)))
              (cond ((string=? name "") (Err "a command needs a name"))
                    ((table-contains? names name) (Err (string-append "duplicate command: " name)))
                    (else (loop (+ index 1) (table-set names name #t))))))))

    ;; ---- Lookup ----

    (define (named (registry (Registry A)) (name String))
      (→ (Option A))
      (! e)
      (∀ (A e))
      (⊨ (Copy A) (Drop e A))
      (let ((commands (● registry commands)))
        (let loop ((index 0))
          (cond ((= index (vector-length commands)) (None))
                ((string=? (● (vector-ref commands index) name) name)
                 (Some (● (vector-ref commands index) action)))
                (else (loop (+ index 1)))))))
    ))
