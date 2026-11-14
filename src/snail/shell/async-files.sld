;; Bounded whole-file reads through an explicit native filesystem capability.
;; The calling task waits; ordinary dispatch can expose its result as a future.
;; Neither this operation nor its result promises a disk snapshot.
(define-library (snail shell async-files)
  (export files
          read-file
          FileError
          Unavailable
          InvalidInput
          TooLarge
          NotFound
          PermissionDenied
          Failed)
  (import
   (snail core base)
   (snail shell task)
   (prefix (snail runtime native async-files) host-))
  (begin

    ;; ---- Capability and result ----

    (enum FileError
      (Unavailable)
      (InvalidInput)
      (TooLarge)
      (NotFound)
      (PermissionDenied)
      (Failed))

    (effect files
      ((read-file (Fn String I32 → (Result Bytes FileError) ! tasks)))
      (default ((read-file native-read))))

    ;; ---- Reading ----

    ;; The read runs to completion: the host delivers its result to the
    ;; waiting task, which takes it with `finish`.
    (define (native-read (path String) (maximum I32)) (→ (Result Bytes FileError)) (! tasks)
      (let ((ticket (ticket)))
        (for-each host-path-character (string->list path))
        (let ((id (host-start-read ticket maximum)))
          (await ticket)
          (finish id))))

    ;; The host holds bytes only until the next finish; copying does not
    ;; suspend.

    (define (finish (id I64)) (→ (Result Bytes FileError))
      (let ((answer (host-finish id)))
        (if (< answer 0)
            (Err (failure answer))
            (Ok (vector-generate (i32->i64 answer)
                                 (lambda (index) (i32->u8 (host-byte (i64->i32 index)))))))))

    (define (failure (code I32)) (→ FileError)
      (cond ((= code -1) (Unavailable))
            ((= code -2) (InvalidInput))
            ((= code -3) (TooLarge))
            ((= code -4) (NotFound))
            ((= code -5) (PermissionDenied))
            (else (Failed))))))
