;; Bounded whole-file reads through an explicit native filesystem capability.
;; The calling task waits while other tasks run.
;; Neither this operation nor its result promises a disk snapshot.
(define-library (snail shell async-files)
  (export Files
          read-file
          File-error
          Unavailable
          Invalid-input
          Too-large
          Not-found
          Permission-denied
          Failed)
  (import
   (snail core base)
   (snail shell task)
   (prefix (snail runtime native async-files) host-))
  (begin

    ;; ---- Capability and result ----

    (enum File-error
      (Unavailable)
      (Invalid-input)
      (Too-large)
      (Not-found)
      (Permission-denied)
      (Failed))

    (effect Files
      ((read-file (Fn String I32 → (Result Bytes File-error) ! Tasks)))
      (default ((read-file native-read))))

    ;; ---- Reading ----

    ;; The read runs to completion: the host delivers its result to the
    ;; waiting task, which takes it with `finish`.
    (define (native-read (path String) (maximum I32)) (→ (Result Bytes File-error)) (! Tasks)
      (let ((ticket (ticket)))
        (for-each host-path-character (string->list path))
        (let ((id (host-start-read ticket maximum)))
          (await ticket)
          (finish id))))

    ;; The host holds bytes only until the next finish; copying does not
    ;; suspend.

    (define (finish (id I64)) (→ (Result Bytes File-error))
      (let ((answer (host-finish id)))
        (if (< answer 0)
            (Err (failure answer))
            (Ok (vector-generate (i32->i64 answer)
                                 (lambda (index) (i32->u8 (host-byte (i64->i32 index)))))))))

    (define (failure (code I32)) (→ File-error)
      (cond ((= code -1) (Unavailable))
            ((= code -2) (Invalid-input))
            ((= code -3) (Too-large))
            ((= code -4) (Not-found))
            ((= code -5) (Permission-denied))
            (else (Failed))))))
