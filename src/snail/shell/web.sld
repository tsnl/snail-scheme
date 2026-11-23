;; The web as a program on Node reads it, as the capability `Web`: the
;; length of the file at a URL, and parts of it, which HTTP's ranges ask a
;; server for, so a program reads what it needs of a large file and never
;; fetches the rest. Node's fetch makes each request
;; (host/native/web-imports.mjs), over HTTPS or HTTP, following
;; redirects, while the task that asked waits and the others run.
;;
;; `size url` answers the file's length. `parts url spans` answers the
;; bytes of each span of the file, asked for together, in the order given;
;; a span the server cannot answer with exactly those bytes, as when it
;; answers with the whole file instead, is why it has none.
(define-library (snail shell web)
  (export
   Web
   Span
   host-web)
  (import
   (snail core base)
   (only (snail core io) Host)
   (prefix (snail runtime native web) host-)
   (only (snail shell task) ticket await))
  (begin

    ;; ---- The capability ----

    ;; `count` bytes of a file, from byte `start`.
    (record Span
      ((start I64)
       (count I64)))

    (record Web
      ((size (Fn String → (Result I64 String)))
       (parts (Fn String (List Span) → (List (Result Bytes String))))))

    (define (host-web (host Host)) (→ Web)
      (new Web
        (size native-size)
        (parts native-parts)))

    ;; ---- Requests ----

    ;; A URL is sent just before the request that takes it starts, and
    ;; nothing between the two lets another task run.

    (define (send-url (url String)) (→ Unit)
      (for-each host-argument-character (string->list url))
      (host-argument-end))

    (define (native-size (url String)) (→ (Result I64 String))
      (let ((id (ticket)))
        (send-url url)
        (host-start-size id)
        (await (list id))
        (answered url (host-finish id) host-held-number)))

    ;; Every part starts, under a ticket of its own, before the task waits,
    ;; once, for all of them; then each is finished in turn, and its bytes
    ;; read before the next is. An empty span asks for nothing.

    (define (native-parts (url String) (spans (List Span))) (→ (List (Result Bytes String)))
      (let ((ids (map (lambda (span)
                        (if (= (● span count) 0)
                            (None)
                            (let ((id (ticket)))
                              (send-url url)
                              (host-start-part id (● span start) (● span count))
                              (Some id))))
                      spans)))
        (await (concatenate (map (lambda (id)
                                   (match id
                                     ((Some id) (list id))
                                     ((None) (Nil))))
                                 ids)))
        (map (lambda (id)
               (match id
                 ((Some id) (answered url (host-finish id) (lambda () (held-bytes 0))))
                 ((None) (Ok (make-array 0 (i32->u8 0))))))
             ids)))

    ;; ---- Answers ----

    (define (answered (url String) (answer I32) (success (Fn → T))) (→ (Result T String)) (∀ (T))
      (if (< answer 0)
          (Err (string-append "cannot read " url ": " (reason (held-text 0))))
          (Ok (success))))

    (define (reason (code String)) (→ String)
      (cond ((string=? code "NO_RANGES") "the server answers with the whole file, not a part of it")
            ((string=? code "NO_LENGTH") "the server does not say how long the file is")
            ((string=? code "WRONG_PART")
             "the server answers with another part than was asked for")
            ((and (> (string-length code) 5) (string=? (substring code 0 5) "HTTP_"))
             (string-append "the server answers "
                            (substring code 5 (string-length code))))
            (else code)))

    (define (held-bytes (position I32)) (→ Bytes)
      (array-generate (i32->i64 (host-held-length position))
                      (lambda (index) (i32->u8 (host-held-byte position (i64->i32 index))))))

    ;; Codes are ASCII.

    (define (held-text (position I32)) (→ String)
      (string-generate (i32->i64 (host-held-length position))
                       (lambda (index) (i32->char (host-held-byte position (i64->i32 index))))))))
