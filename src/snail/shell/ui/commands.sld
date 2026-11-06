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

    (: register (All (A) (requires (Copy A))
                     (-> (Vector (Command A)) (Result (Registry A) String))))
    (define (register commands)
      (let loop ((index 0) (names (ann empty-table (Table Bool))))
        (if (= index (vector-length commands)) (Ok (Registry commands))
            (let ((name (::name (vector-ref commands index))))
              (cond ((string=? name "") (Err "a command needs a name"))
                    ((table-contains? names name) (Err (string-append "duplicate command: " name)))
                    (else (loop (+ index 1) (table-set names name #t))))))))

    ;; ---- Lookup ----

    (: named (All (A) (requires (Copy A)) (-> (Registry A) String (Option A))))
    (define (named registry name)
      (let ((commands (::commands registry)))
        (let loop ((index 0))
          (cond ((= index (vector-length commands)) (None))
                ((string=? (::name (vector-ref commands index)) name)
                 (Some (::action (vector-ref commands index))))
                (else (loop (+ index 1)))))))
    ))
