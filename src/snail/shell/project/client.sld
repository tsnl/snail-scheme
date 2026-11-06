;; Typed HTTP replies shared by the editor and its feature libraries.
(define-library (snail shell project client)
  (export Failure Failure-status Failure-message api url-component file-url
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
    (: api (-> String String (List Header) String (Result Json Failure) ! fetch tasks))
    (define (api method url headers body)
      (match (request method url headers body)
        ((Ok reply) (reply-json reply))
        ((Err why) (Err (Failure -1 why)))))

    (: reply-json (-> Reply (Result Json Failure)))
    (define (reply-json reply)
      (let ((status (Reply-status reply)))
        (match (if (= status 204) (Some (JsonNull)) (string->json (Reply-body reply)))
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
    (: url-component (-> String String))
    (define (url-component text)
      (string-concatenate
       (map (lambda (byte) (url-byte (u8->i32 byte))) (vector->list (string->utf8 text)))))

    (: url-byte (-> I32 String))
    (define (url-byte byte)
      (if (or (and (>= byte 65) (<= byte 90))
              (and (>= byte 97) (<= byte 122))
              (and (>= byte 48) (<= byte 57))
              (member? byte (list 33 39 40 41 42 45 46 95 126)))
          (make-string 1 (i32->char byte))
          (string-append "%"
                         (hex-digit (i32-shift-right/logical byte 4))
                         (hex-digit (i32-and byte 15)))))

    (: hex-digit (-> I32 String))
    (define (hex-digit value)
      (make-string 1 (string-ref "0123456789ABCDEF" (i32->i64 value))))

    (: file-url (-> String String))
    (define (file-url path)
      (string-append "/api/file?path=" (url-component path)))

    ;; ---- Typed replies ----

    (: decoded-reply
       (All (T) (requires (Copy T))
            (-> (-> Json (Option T)) String (Result Json Failure) (Result T Failure))))
    (define (decoded-reply decode subject reply)
      (match reply
        ((Err failure) (Err failure))
        ((Ok json)
         (match (decode json)
           ((Some value) (Ok value))
           ((None) (Err (Failure 200 (string-append "invalid " subject " response"))))))))

    (: file-reply (-> (Result Json Failure) (Result Snapshot Failure)))
    (define (file-reply reply)
      (decoded-reply json->file "file" reply))

    (: project-reply (-> (Result Json Failure) (Result Project Failure)))
    (define (project-reply reply)
      (decoded-reply json->project "project" reply))

    (: search-reply (-> (Result Json Failure) (Result SearchResults Failure)))
    (define (search-reply reply)
      (decoded-reply json->search "search" reply))))
