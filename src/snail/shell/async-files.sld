;; Bounded whole-file reads through an explicit native filesystem capability.
;; The calling task waits; ordinary dispatch can expose its result as a future.
;; A canceled task withdraws reception while the host finishes and closes the
;; request. Neither this operation nor its result promises a disk snapshot.
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
      ((read-file (-> String I32 (Result Bytes FileError) ! mut tasks)))
      (default ((read-file native-read))))

    ;; ---- Pending request ownership ----

    ;; Only the suspended frame owns this token. Its cleanup does not free
    ;; kernel-visible storage: that storage belongs to the native operation.
    (struct Request
      ((id I64)))

    (instance (Drop (! mut) Request)
      (define (drop request)
        (match request ((Request id) (host-cancel id)))))

    (: native-read (-> String I32 (Result Bytes FileError) ! mut tasks))
    (define (native-read path maximum)
      (let ((ticket (ticket)))
        (for-each host-path-character (string->list path))
        (let ((request (Request (host-start-read ticket maximum))))
          (await ticket)
          (finish request))))

    ;; The host holds bytes only until the next finish; copying does not
    ;; suspend. Completion consumes the token, so Drop cannot cancel it again.
    (: finish (-> Request (Result Bytes FileError)))
    (define (finish request)
      (match request
        ((Request id)
         (let ((answer (host-finish id)))
           (if (< answer 0)
               (Err (failure answer))
               (Ok (vector-generate (i32->i64 answer)
                                    (lambda (index) (i32->u8 (host-byte (i64->i32 index)))))))))))

    (: failure (-> I32 FileError))
    (define (failure code)
      (cond ((= code -1) (Unavailable))
            ((= code -2) (InvalidInput))
            ((= code -3) (TooLarge))
            ((= code -4) (NotFound))
            ((= code -5) (PermissionDenied))
            (else (Failed))))))
