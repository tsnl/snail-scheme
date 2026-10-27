;; Bounded HTTP/1.1 head syntax and framing. This deliberately supports a
;; subset: ASCII heads, origin-form targets, Content-Length and one exchange.
(define-library (snail-core http)
  (export
   Header Header-name Header-value
   RequestHead RequestHead-method RequestHead-target RequestHead-headers RequestHead-body-length
   ParsedHead ParsedHead-request ParsedHead-end
   ResponseParts ResponseParts-head ResponseParts-body
   HttpError Malformed Unsupported HeadTooLarge BodyTooLarge InvalidResponse
   head-limit body-limit parse-request-head encode-response header-values)
  (import
   (snail-core base))
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
           (every? (lambda (char) (or (letter? char) (digit? char) (contains-char? "!#$%&'*+-.^_`|~" char)))
                   (string->list text))))

    (: lower-ascii (-> String String))
    (define (lower-ascii text)
      (string-generate (string-length text)
                       (lambda (index)
                         (let ((code (char->integer (string-ref text index))))
                           (integer->char (if (and (>= code 65) (<= code 90)) (+ code 32) code))))))

    (: field-value? (-> String Bool))
    (define (field-value? text)
      (every? (lambda (char) (let ((code (char->integer char))) (or (= code 9) (and (>= code 32) (<= code 126)))))
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
                       ((not (or (= byte 9) (= byte 13) (= byte 10) (and (>= byte 32) (<= byte 126))))
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
                                            (lambda (offset) (i32->char (u8->i32 (vector-ref bytes (+ first offset))))))))
                 (loop (+ index 2) (+ index 2) (Cons line lines))))
              (else (loop first (+ index 1) lines)))))

    (: hex? (-> Char Bool))
    (define (hex? char)
      (or (digit? char) (contains-char? "abcdefABCDEF" char)))

    (: target? (-> String Bool))
    (define (target? text)
      (let loop ((index 0))
        (if (= index (string-length text))
            #t
            (let ((char (string-ref text index)))
              (cond ((= char #\%) (and (< (+ index 2) (string-length text)) (hex? (string-ref text (+ index 1)))
                                       (hex? (string-ref text (+ index 2))) (loop (+ index 3))))
                    ((or (letter? char) (digit? char) (contains-char? "-._~!$&'()*+,;=:@/?" char)) (loop (+ index 1)))
                    (else #f))))))

    (: request-line (-> String (Result (Pair String String) HttpError)))
    (define (request-line line)
      (match (string-index line #\space)
        ((None) (Err (Malformed "request line")))
        ((Some first)
         (let ((method (substring line 0 first)) (rest (substring line (+ first 1) (string-length line))))
           (match (string-index rest #\space)
             ((None) (Err (Malformed "request line")))
             ((Some second)
              (request-target method (substring rest 0 second) (substring rest (+ second 1) (string-length rest)))))))))

    (: request-target (-> String String String (Result (Pair String String) HttpError)))
    (define (request-target method target version)
      (cond ((or (not (token? method)) (= (string-length target) 0)) (Err (Malformed "method or target")))
            ((not (and (= (string-length version) 8) (string=? (substring version 0 5) "HTTP/")
                       (digit? (string-ref version 5)) (= (string-ref version 6) #\.) (digit? (string-ref version 7))))
             (Err (Malformed "HTTP version")))
            ((not (string=? version "HTTP/1.1")) (Err (Unsupported "HTTP version")))
            ((or (string=? method "CONNECT") (not (= (string-ref target 0) #\/))) (Err (Unsupported "request target form")))
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
              (let ((name (substring line 0 colon)) (value (trim-ows (substring line (+ colon 1) (string-length line)))))
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
                  ((> value (quotient (- maximum (digit-value (string-ref text index))) 10)) (Err excessive))
                  (else (loop (+ index 1) (+ (* value 10) (digit-value (string-ref text index)))))))))

    (: host-name? (-> String Bool))
    (define (host-name? name)
      (and (> (string-length name) 0)
           (every? (lambda (char) (or (letter? char) (digit? char) (contains-char? ".-_" char))) (string->list name))))

    (: host-value (-> String (Result Unit HttpError)))
    (define (host-value text)
      (if (and (> (string-length text) 0) (= (string-ref text 0) #\[))
          (Err (Unsupported "IPv6 Host literal"))
          (match (string-index text #\:)
            ((None) (if (host-name? text) (Ok (unit)) (Err (Malformed "Host name"))))
            ((Some colon)
             (if (not (host-name? (substring text 0 colon)))
                 (Err (Malformed "Host name"))
                 (match (decimal (substring text (+ colon 1) (string-length text)) 65535 (Malformed "Host port"))
                   ((Err error) (Err error))
                   ((Ok _) (Ok (unit)))))))))

    (: content-length (-> (List Header) (Result I64 HttpError)))
    (define (content-length headers)
      (let ((lengths (header-values headers "content-length")) (codings (header-values headers "transfer-encoding")))
        (cond ((and (not (null? lengths)) (not (null? codings))) (Err (Malformed "ambiguous body framing")))
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
                         ((Ok count) (Ok (RequestHead (Pair-first line) (Pair-second line) headers count))))))))
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
             (cond ((or (> (string-length name) remaining) (> (string-length value) (- (- remaining (string-length name)) 4)))
                    (Err (HeadTooLarge)))
                   ((or (not (token? name)) (not (field-value? value))) (Err (InvalidResponse "header name or value")))
                   (else (let ((name (lower-ascii name)))
                           (if (controlled-header? name)
                               (Err (InvalidResponse "application framing header"))
                               (loop rest (- (- (- remaining (string-length name)) (string-length value)) 4)
                                     (Cons (string-append name ": " value "\r\n") lines)))))))))))

    (: response-prefix (-> I32 I64 String))
    (define (response-prefix status count)
      (string-append "HTTP/1.1 " (show status) " \r\nConnection: close\r\n"
                     (if (or (= status 204) (= status 304)) ""
                         (string-append "Content-Length: " (show (if (= status 205) 0 count)) "\r\n"))))

    (: response-body (-> String I32 Bytes Bytes))
    (define (response-body method status bytes)
      (if (or (string=? method "HEAD") (= status 204) (= status 205) (= status 304)) #u8() bytes))

    (: encode-response (-> String I32 (List Header) Bytes (Result ResponseParts HttpError)))
    (define (encode-response method status headers bytes)
      (cond ((or (not (token? method)) (< status 200) (> status 599)) (Err (InvalidResponse "method or final status")))
            ((and (string=? method "CONNECT") (< status 300)) (Err (Unsupported "CONNECT tunnel")))
            (else
             (let ((prefix (response-prefix status (vector-length bytes))))
               (match (response-fields headers (- (- head-limit (string-length prefix)) 2))
                 ((Err error) (Err error))
                 ((Ok fields)
                  (let ((head (string-concatenate (Cons prefix (append fields (list "\r\n"))))))
                    (Ok (ResponseParts (vector-generate (string-length head) (lambda (index) (i32->u8 (char->i32 (string-ref head index)))))
                                       (response-body method status bytes))))))))))

    ))
