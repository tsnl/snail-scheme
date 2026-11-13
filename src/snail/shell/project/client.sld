;; Typed HTTP replies shared by the editor and its feature libraries.
(define-library (snail shell project client)
  (export Failure api url-component file-url
          decoded-reply file-reply project-reply search-reply)
  (import
   (snail core base)
   (snail shell utf8)
   (snail shell task)
   (snail shell fetch)
   (snail shell json)
   (snail shell json read)
   (snail shell project protocol))
  (begin
    ;; ---- Requests ----

    ;; Why a request failed: the reply's status, or -1 when there was no
    ;; reply, and the service's message, or the connection's.
    (struct Failure
      ((status I32)
       (message String)))

    ;; The service's JSON answer, or why there is none. A reply without
    ;; content answers null.

    (define (api (method String) (url String) (headers (List Header)) (body String))
      (→ (Result Json Failure))
      (! fetch tasks)
      (match (request method url headers body)
        ((Ok reply) (reply-json reply))
        ((Err why) (Err (Failure -1 why)))))

    (define (reply-json (reply Reply)) (→ (Result Json Failure))
      (let ((status (● reply status)))
        (match (if (= status 204) (Some (JsonNull)) (string->json (● reply body)))
          ((Some json)
           (if (and (>= status 200) (< status 300))
               (Ok json)
               (Err (Failure status (match (json->message json)
                                      ((Some message) message)
                                      ((None) "invalid service error response"))))))
          ((None)
           (Err
            (Failure status
                     (string-append "the service answered " (show status) " without JSON")))))))

    ;; `text` as one component of a URL, as `encodeURIComponent` writes it:
    ;; its UTF-8 bytes, each but the unreserved characters escaped.

    (define (url-component (text String)) (→ String)
      (string-concatenate
       (map (lambda (byte) (url-byte (u8->i32 byte))) (vector->list (string->utf8 text)))))

    (define (url-byte (byte I32)) (→ String)
      (if (or (and (>= byte 65) (<= byte 90))
              (and (>= byte 97) (<= byte 122))
              (and (>= byte 48) (<= byte 57))
              (member? byte (list 33 39 40 41 42 45 46 95 126)))
          (make-string 1 (i32->char byte))
          (string-append "%"
                         (hex-digit (i32-shift-right/logical byte 4))
                         (hex-digit (i32-and byte 15)))))

    (define (hex-digit (value I32)) (→ String)
      (make-string 1 (string-ref "0123456789ABCDEF" (i32->i64 value))))

    (define (file-url (path String)) (→ String)
      (string-append "/api/file?path=" (url-component path)))

    ;; ---- Typed replies ----

    (define (decoded-reply (decode (Fn Json → (Option T)))
                           (subject String)
                           (reply (Result Json Failure)))
      (→ (Result T Failure))
      (∀ (T))
      (⊨ (Copy T) (Drop (!) T))
      (match reply
        ((Err failure) (Err failure))
        ((Ok json)
         (match (decode json)
           ((Some value) (Ok value))
           ((None) (Err (Failure 200 (string-append "invalid " subject " response"))))))))

    (define (file-reply (reply (Result Json Failure))) (→ (Result Snapshot Failure))
      (decoded-reply json->file "file" reply))

    (define (project-reply (reply (Result Json Failure))) (→ (Result Project Failure))
      (decoded-reply json->project "project" reply))

    (define (search-reply (reply (Result Json Failure))) (→ (Result SearchResults Failure))
      (decoded-reply json->search "search" reply))))
