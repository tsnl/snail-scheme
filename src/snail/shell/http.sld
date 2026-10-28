;; Bounded HTTP/1.1 head syntax and framing. This deliberately supports a
;; subset: ASCII heads, origin-form targets, Content-Length, one exchange,
;; and response streams that end when the connection closes.
(define-library (snail shell http)
  (export
   Header Header-name Header-value
   RequestHead RequestHead-method RequestHead-target RequestHead-headers RequestHead-body-length
   ParsedHead ParsedHead-request ParsedHead-end
   ResponseParts ResponseParts-head ResponseParts-body
   Target Target-path Target-query
   HttpError Malformed Unsupported HeadTooLarge BodyTooLarge InvalidResponse
   head-limit
   body-limit
   parse-request-head
   parse-target
   encode-response
   encode-stream-head
   header-values)
  (import
   (snail core base)
   (snail shell utf8))
  (begin

    ;; ---- Public values ----

    (struct Header
      ((name String)
       (value String)))

    (struct RequestHead
      ((method String)
       (target String)
       (headers (List Header))
       (body-length I64)))

    (struct ParsedHead
      ((request RequestHead)
       (end I64)))

    (struct ResponseParts
      ((head Bytes)
       (body Bytes)))

    ;; A decoded origin-form target. The path is its segments after the
    ;; first `/`, each percent-decoded, so `/` is ("") and `/a%2Fb/` is
    ;; ("a/b" ""); the query is its name and value pairs in order.
    (struct Target
      ((path (List String))
       (query (List (Pair String String)))))

    (enum HttpError
      (Malformed ((reason String)))
      (Unsupported ((feature String)))
      (HeadTooLarge)
      (BodyTooLarge)
      (InvalidResponse ((reason String))))

    (: head-limit I64)
    (define head-limit 16384)
    (: body-limit I64)
    (define body-limit 8388608)

    ;; ---- Request syntax ----

    (: digit? (-> Char Bool))
    (define (digit? char)
      (let ((code (char->integer char))) (and (>= code 48) (<= code 57))))

    (: letter? (-> Char Bool))
    (define (letter? char)
      (let ((code (char->integer char)))
        (or (and (>= code 65) (<= code 90)) (and (>= code 97) (<= code 122)))))

    (: contains-char? (-> String Char Bool))
    (define (contains-char? text char)
      (match (string-index text char) ((Some _) #t) ((None) #f)))

    (: token? (-> String Bool))
    (define (token? text)
      (and (> (string-length text) 0)
           (every? (lambda (char)
                     (or (letter? char) (digit? char) (contains-char? "!#$%&'*+-.^_`|~" char)))
                   (string->list text))))

    (: lower-ascii (-> String String))
    (define (lower-ascii text)
      (string-generate (string-length text)
                       (lambda (index)
                         (let ((code (char->integer (string-ref text index))))
                           (integer->char (if (and (>= code 65) (<= code 90)) (+ code 32) code))))))

    (: field-value? (-> String Bool))
    (define (field-value? text)
      (every? (lambda (char)
                (let ((code (char->integer char)))
                  (or (= code 9) (and (>= code 32) (<= code 126)))))
              (string->list text)))

    (: ows? (-> Char Bool))
    (define (ows? char) (or (= char #\space) (= char #\tab)))

    (: trim-ows (-> String String))
    (define (trim-ows text)
      (let start ((first 0))
        (if (and (< first (string-length text)) (ows? (string-ref text first)))
            (start (+ first 1))
            (let end ((last (string-length text)))
              (if (and (> last first) (ows? (string-ref text (- last 1))))
                  (end (- last 1))
                  (substring text first last))))))

    ;; Inspect only the bounded head prefix. Binary body bytes after the empty
    ;; line are not syntax, and even a large supplied body cannot enlarge it.
    (: head-end (-> Bytes (Result (Option I64) HttpError)))
    (define (head-end bytes)
      (let loop ((index 0))
        (cond ((= index head-limit) (Err (HeadTooLarge)))
              ((= index (vector-length bytes)) (Ok (None)))
              (else
               (let ((byte (u8->i32 (vector-ref bytes index)))
                     (previous (if (= index 0) 0 (u8->i32 (vector-ref bytes (- index 1))))))
                 (cond ((and (= previous 13) (not (= byte 10))) (Err (Malformed "CR without LF")))
                       ((and (= byte 10) (not (= previous 13))) (Err (Malformed "LF without CR")))
                       ((not
                         (or (= byte 9) (= byte 13) (= byte 10) (and (>= byte 32) (<= byte 126))))
                        (Err (Malformed "non-ASCII or control byte in head")))
                       ((and (>= index 3) (= byte 10) (= previous 13)
                             (= (u8->i32 (vector-ref bytes (- index 2))) 10)
                             (= (u8->i32 (vector-ref bytes (- index 3))) 13))
                        (Ok (Some (+ index 1))))
                       (else (loop (+ index 1)))))))))

    ;; head-end established CRLF and ASCII. Exclude the final empty line.
    (: head-lines (-> Bytes I64 (List String)))
    (define (head-lines bytes end)
      (let loop ((first 0) (index 0) (lines (Nil)))
        (cond ((= first (- end 2)) (reverse lines))
              ((= (u8->i32 (vector-ref bytes index)) 13)
               (let ((line (string-generate (- index first)
                                            (lambda (offset)
                                              (i32->char
                                               (u8->i32 (vector-ref bytes (+ first offset))))))))
                 (loop (+ index 2) (+ index 2) (Cons line lines))))
              (else (loop first (+ index 1) lines)))))

    (: hex? (-> Char Bool))
    (define (hex? char)
      (or (digit? char) (contains-char? "abcdefABCDEF" char)))

    ;; RFC 3986's unreserved and sub-delimiter characters, and those a path
    ;; or query may hold besides; `%` begins an escape.
    (: uri-char? (-> Char Bool))
    (define (uri-char? char)
      (or (letter? char) (digit? char) (contains-char? "-._~!$&'()*+,;=:@/?" char)))

    (: target? (-> String Bool))
    (define (target? text)
      (let loop ((index 0))
        (if (= index (string-length text))
            #t
            (let ((char (string-ref text index)))
              (cond ((= char #\%)
                     (and (< (+ index 2) (string-length text)) (hex? (string-ref text (+ index 1)))
                          (hex? (string-ref text (+ index 2))) (loop (+ index 3))))
                    ((uri-char? char) (loop (+ index 1)))
                    (else #f))))))

    (: request-line (-> String (Result (Pair String String) HttpError)))
    (define (request-line line)
      (match (string-index line #\space)
        ((None) (Err (Malformed "request line")))
        ((Some first)
         (let ((method (substring line 0 first))
               (rest (substring line (+ first 1) (string-length line))))
           (match (string-index rest #\space)
             ((None) (Err (Malformed "request line")))
             ((Some second)
              (request-target method
                              (substring rest 0 second)
                              (substring rest (+ second 1) (string-length rest)))))))))

    (: request-target (-> String String String (Result (Pair String String) HttpError)))
    (define (request-target method target version)
      (cond ((or (not (token? method)) (= (string-length target) 0))
             (Err (Malformed "method or target")))
            ((not (and (= (string-length version) 8) (string=? (substring version 0 5) "HTTP/")
                       (digit? (string-ref version 5))
                       (= (string-ref version 6) #\.)
                       (digit? (string-ref version 7))))
             (Err (Malformed "HTTP version")))
            ((not (string=? version "HTTP/1.1")) (Err (Unsupported "HTTP version")))
            ((or (string=? method "CONNECT") (not (= (string-ref target 0) #\/)))
             (Err (Unsupported "request target form")))
            ((not (target? target)) (Err (Malformed "request target")))
            (else (Ok (Pair method target)))))

    (: request-headers (-> (List String) (Result (List Header) HttpError)))
    (define (request-headers lines)
      (let loop ((lines lines) (headers (Nil)))
        (match lines
          ((Nil) (Ok (reverse headers)))
          ((Cons line rest)
           (match (string-index line #\:)
             ((None) (Err (Malformed "header has no colon")))
             ((Some colon)
              (let ((name (substring line 0 colon))
                    (value (trim-ows (substring line (+ colon 1) (string-length line)))))
                (if (token? name)
                    (loop rest (Cons (Header (lower-ascii name) value) headers))
                    (Err (Malformed "header name"))))))))))

    ;; ---- Request framing ----

    ;; Parsed names are lowercase. Preserve all occurrences in wire order.
    (: header-values (-> (List Header) String (List String)))
    (define (header-values headers name)
      (let ((name (lower-ascii name)))
        (map Header-value (filter (lambda (header) (string=? (Header-name header) name)) headers))))

    ;; The check precedes arithmetic, including for thousands of digits.
    (: decimal (-> String I64 HttpError (Result I64 HttpError)))
    (define (decimal text maximum excessive)
      (if (= (string-length text) 0)
          (Err (Malformed "empty decimal"))
          (let loop ((index 0) (value 0))
            (cond ((= index (string-length text)) (Ok value))
                  ((not (digit? (string-ref text index))) (Err (Malformed "invalid decimal")))
                  ((> value (quotient (- maximum (digit-value (string-ref text index))) 10))
                   (Err excessive))
                  (else
                   (loop (+ index 1) (+ (* value 10) (digit-value (string-ref text index)))))))))

    (: host-name? (-> String Bool))
    (define (host-name? name)
      (and (> (string-length name) 0)
           (every? (lambda (char) (or (letter? char) (digit? char) (contains-char? ".-_" char)))
                   (string->list name))))

    (: host-value (-> String (Result Unit HttpError)))
    (define (host-value text)
      (if (and (> (string-length text) 0) (= (string-ref text 0) #\[))
          (Err (Unsupported "IPv6 Host literal"))
          (match (string-index text #\:)
            ((None) (if (host-name? text) (Ok (unit)) (Err (Malformed "Host name"))))
            ((Some colon)
             (if (not (host-name? (substring text 0 colon)))
                 (Err (Malformed "Host name"))
                 (match (decimal (substring text (+ colon 1) (string-length text))
                                 65535
                                 (Malformed "Host port"))
                   ((Err error) (Err error))
                   ((Ok _) (Ok (unit)))))))))

    (: content-length (-> (List Header) (Result I64 HttpError)))
    (define (content-length headers)
      (let ((lengths (header-values headers "content-length"))
            (codings (header-values headers "transfer-encoding")))
        (cond ((and (not (null? lengths)) (not (null? codings)))
               (Err (Malformed "ambiguous body framing")))
              ((not (null? codings)) (Err (Unsupported "Transfer-Encoding")))
              ((not (null? (header-values headers "expect"))) (Err (Unsupported "Expect")))
              (else (match lengths
                      ((Nil) (Ok 0))
                      ((Cons value rest) (if (null? rest) (decimal value body-limit (BodyTooLarge))
                                             (Err (Malformed "duplicate Content-Length")))))))))

    (: framed-request (-> (Pair String String) (List Header) (Result RequestHead HttpError)))
    (define (framed-request line headers)
      (match (header-values headers "host")
        ((Cons host rest)
         (if (not (null? rest))
             (Err (Malformed "duplicate Host"))
             (match (host-value host)
               ((Err error) (Err error))
               ((Ok _) (match (content-length headers)
                         ((Err error) (Err error))
                         ((Ok count)
                          (Ok
                           (RequestHead (Pair-first line) (Pair-second line) headers count))))))))
        ((Nil) (Err (Malformed "missing Host")))))

    (: complete-head (-> (List String) (Result RequestHead HttpError)))
    (define (complete-head lines)
      (match lines
        ((Nil) (Err (Malformed "missing request line")))
        ((Cons first rest)
         (match (request-line first)
           ((Err error) (Err error))
           ((Ok line) (match (request-headers rest)
                        ((Err error) (Err error))
                        ((Ok headers) (framed-request line headers))))))))

    (: parse-request-head (-> Bytes (Result (Option ParsedHead) HttpError)))
    (define (parse-request-head bytes)
      (match (head-end bytes)
        ((Err error) (Err error))
        ((Ok end) (match end
                    ((None) (Ok (None)))
                    ((Some end) (match (complete-head (head-lines bytes end))
                                  ((Err error) (Err error))
                                  ((Ok request) (Ok (Some (ParsedHead request end))))))))))

    ;; ---- Request targets ----

    ;; Every piece between separators, empty ones included.
    (: split-on (-> String Char (List String)))
    (define (split-on text separator)
      (let loop ((start 0) (index 0) (pieces (Nil)))
        (cond ((= index (string-length text)) (reverse (Cons (substring text start index) pieces)))
              ((= (string-ref text index) separator)
               (loop (+ index 1) (+ index 1) (Cons (substring text start index) pieces)))
              (else (loop start (+ index 1) pieces)))))

    (: hex-value (-> Char I32))
    (define (hex-value char)
      (let ((code (char->i32 char)))
        (cond ((<= code 57) (- code 48))
              ((<= code 70) (- code 55))
              (else (- code 87)))))

    ;; The byte that the `%` at `index` escapes, if two hex digits follow it.
    (: escaped-byte (-> String I64 (Option U8)))
    (define (escaped-byte text index)
      (if (and (< (+ index 2) (string-length text))
               (hex? (string-ref text (+ index 1)))
               (hex? (string-ref text (+ index 2))))
          (Some (i32->u8 (+ (* 16 (hex-value (string-ref text (+ index 1))))
                            (hex-value (string-ref text (+ index 2))))))
          (None)))

    ;; Strict percent-decoding: each `%` begins two hex digits, every other
    ;; character is a URI character, and the bytes are UTF-8. In a query's
    ;; form encoding `+` is a space, decided before decoding, so `%2B` is
    ;; still a plus.
    (: percent-decode (-> String Bool (Result String HttpError)))
    (define (percent-decode text form)
      (let loop ((index 0) (bytes (Nil)))
        (if (= index (string-length text))
            (match (utf8->string (list->vector (reverse bytes)))
              ((Ok decoded) (Ok decoded))
              ((Err _) (Err (Malformed "request target is not UTF-8"))))
            (let ((char (string-ref text index)))
              (cond ((= char #\%) (match (escaped-byte text index)
                                    ((Some byte) (loop (+ index 3) (Cons byte bytes)))
                                    ((None) (Err (Malformed "percent escape")))))
                    ((not (uri-char? char)) (Err (Malformed "request target")))
                    ((and form (= char #\+)) (loop (+ index 1) (Cons (i32->u8 32) bytes)))
                    (else (loop (+ index 1) (Cons (i32->u8 (char->i32 char)) bytes))))))))

    ;; The URL standard's path rules, which `new URL` applies: after
    ;; decoding, so that `%2e%2e` is one too, `..` removes the segment before
    ;; it and `.` removes itself, and either one, last, leaves an empty
    ;; final segment, so `/a/b/..` is `/a/`.
    (: dot-step (-> String Bool (List String) (List String)))
    (define (dot-step segment final segments)
      (cond ((string=? segment ".") (if final (Cons "" segments) segments))
            ((string=? segment "..") (if final (Cons "" (drop segments 1)) (drop segments 1)))
            (else (Cons segment segments))))

    (: path-segments (-> String (Result (List String) HttpError)))
    (define (path-segments text)
      (let loop ((pieces (split-on text #\/)) (segments (Nil)))
        (match pieces
          ((Nil) (Ok (reverse segments)))
          ((Cons piece rest)
           (match (percent-decode piece #f)
             ((Err error) (Err error))
             ((Ok segment) (loop rest (dot-step segment (null? rest) segments))))))))

    ;; The first `=` separates a name from its value; with none, the value
    ;; is empty.
    (: query-pair (-> String (Result (Pair String String) HttpError)))
    (define (query-pair piece)
      (let* ((length (string-length piece))
             (equals (match (string-index piece #\=) ((Some index) index) ((None) length))))
        (match (percent-decode (substring piece 0 equals) #t)
          ((Err error) (Err error))
          ((Ok name) (match (percent-decode (substring piece (min (+ equals 1) length) length) #t)
                       ((Err error) (Err error))
                       ((Ok value) (Ok (Pair name value))))))))

    ;; The URL standard's form decoding, which URLSearchParams applies: `&`
    ;; separates pairs, and empty pieces are skipped.
    (: query-pairs (-> String (Result (List (Pair String String)) HttpError)))
    (define (query-pairs text)
      (let loop ((pieces (filter (lambda (piece) (> (string-length piece) 0)) (split-on text #\&)))
                 (pairs (Nil)))
        (match pieces
          ((Nil) (Ok (reverse pairs)))
          ((Cons piece rest)
           (match (query-pair piece)
             ((Err error) (Err error))
             ((Ok pair) (loop rest (Cons pair pairs))))))))

    ;; The path runs to the first `?`, and the query follows it. A target
    ;; with no `/` first is not origin-form, as the head parser decides too.
    (: parse-target (-> String (Result Target HttpError)))
    (define (parse-target text)
      (if (or (= (string-length text) 0) (not (= (string-ref text 0) #\/)))
          (Err (Unsupported "request target form"))
          (let* ((length (string-length text))
                 (end (match (string-index text #\?) ((Some index) index) ((None) length))))
            (match (path-segments (substring text 1 end))
              ((Err error) (Err error))
              ((Ok path) (match (query-pairs (substring text (min (+ end 1) length) length))
                           ((Err error) (Err error))
                           ((Ok query) (Ok (Target path query)))))))))

    ;; ---- Response encoding ----

    (: controlled-header? (-> String Bool))
    (define (controlled-header? name)
      (member? name (list "content-length" "transfer-encoding" "connection" "trailer" "upgrade")))

    (: response-fields (-> (List Header) I64 (Result (List String) HttpError)))
    (define (response-fields headers remaining)
      (let loop ((headers headers) (remaining remaining) (lines (Nil)))
        (match headers
          ((Nil) (Ok (reverse lines)))
          ((Cons header rest)
           (let ((name (Header-name header)) (value (Header-value header)))
             (cond ((or (> (string-length name) remaining)
                        (> (string-length value) (- (- remaining (string-length name)) 4)))
                    (Err (HeadTooLarge)))
                   ((or (not (token? name)) (not (field-value? value)))
                    (Err (InvalidResponse "header name or value")))
                   (else (let ((name (lower-ascii name)))
                           (if (controlled-header? name)
                               (Err (InvalidResponse "application framing header"))
                               (loop rest
                                     (- (- (- remaining (string-length name)) (string-length value))
                                        4)
                                     (Cons (string-append name ": " value "\r\n") lines)))))))))))

    ;; The status line and the one connection field every response has.
    (: status-lines (-> I32 String))
    (define (status-lines status)
      (string-append "HTTP/1.1 " (show status) " \r\nConnection: close\r\n"))

    (: response-prefix (-> I32 I64 String))
    (define (response-prefix status count)
      (string-append (status-lines status)
                     (if (or (= status 204) (= status 304)) ""
                         (string-append "Content-Length: "
                                        (show (if (= status 205) 0 count))
                                        "\r\n"))))

    (: response-body (-> String I32 Bytes Bytes))
    (define (response-body method status bytes)
      (if (or (string=? method "HEAD") (= status 204) (= status 205) (= status 304)) #u8() bytes))

    ;; The head after `prefix`: the fields, then the empty line. Every
    ;; character is ASCII, which response-fields established, so each is
    ;; one byte.
    (: head-bytes (-> String (List Header) (Result Bytes HttpError)))
    (define (head-bytes prefix headers)
      (match (response-fields headers (- (- head-limit (string-length prefix)) 2))
        ((Err error) (Err error))
        ((Ok fields)
         (let ((head (string-concatenate (Cons prefix (append fields (list "\r\n"))))))
           (Ok (vector-generate (string-length head)
                                (lambda (index) (i32->u8 (char->i32 (string-ref head index))))))))))

    (: encode-response (-> String I32 (List Header) Bytes (Result ResponseParts HttpError)))
    (define (encode-response method status headers bytes)
      (cond ((or (not (token? method)) (< status 200) (> status 599))
             (Err (InvalidResponse "method or final status")))
            ((and (string=? method "CONNECT") (< status 300)) (Err (Unsupported "CONNECT tunnel")))
            (else
             (match (head-bytes (response-prefix status (vector-length bytes)) headers)
               ((Err error) (Err error))
               ((Ok head) (Ok (ResponseParts head (response-body method status bytes))))))))

    ;; ---- Streaming responses ----

    ;; A head with no Content-Length, for a body that is every byte written
    ;; after it until the server closes the connection (RFC 9112 §6.3, rule
    ;; 8), as an event stream's is. Statuses that forbid a body have no
    ;; stream, and neither does HEAD, which the caller answers with
    ;; encode-response instead.
    (: encode-stream-head (-> I32 (List Header) (Result Bytes HttpError)))
    (define (encode-stream-head status headers)
      (if (or (< status 200) (> status 599) (member? status (list 204 205 304)))
          (Err (InvalidResponse "streaming status"))
          (head-bytes (status-lines status) headers)))

    ))
