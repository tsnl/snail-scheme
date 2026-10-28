(import
 (snail-core base)
 (snail-core io)
 (snail-core http))

(: ascii (-> String Bytes))
(define (ascii text)
  (vector-generate (string-length text)
                   (lambda (index)
                     (i32->u8 (char->i32 (string-ref text index))))))

(: text (-> Bytes String))
(define (text bytes)
  (string-generate (vector-length bytes)
                   (lambda (index)
                     (i32->char (u8->i32 (vector-ref bytes index))))))

(: assert (-> Bool Unit))
(define (assert condition) (unless condition (panic "HTTP assertion failed")))

(: kind (-> HttpError String))
(define (kind error)
  (match error
    ((Malformed _) "malformed")
    ((Unsupported _) "unsupported")
    ((HeadTooLarge) "head-limit")
    ((BodyTooLarge) "body-limit")
    ((InvalidResponse _) "response")))

(: reject-head (-> String String Unit))
(define (reject-head source expected)
  (match (parse-request-head (ascii source))
    ((Err error) (assert (string=? (kind error) expected)))
    ((Ok _) (panic "accepted invalid head"))))

(: parsed (-> Bytes ParsedHead))
(define (parsed bytes)
  (match (parse-request-head bytes)
    ((Ok value)
     (match value ((Some head) head) ((None) (panic "incomplete test head"))))
    ((Err _) (panic "rejected test head"))))

(: encoded (-> String I32 (List Header) Bytes ResponseParts))
(define (encoded method status headers bytes)
  (match (encode-response method status headers bytes)
    ((Ok response) response)
    ((Err _) (panic "rejected test response"))))

(let* ((source
        "POST /a%2Fb?x=1&x=2 HTTP/1.1\r\nHost: example.test:8080\r\nContent-Length: 3\r\nX-Test: first\r\nx-TEST:\tsecond \t\r\n\r\n")
       (bytes (ascii source))
       (head (parsed (vector-append bytes #u8(0 255 128))))
       (request (ParsedHead-request head)))
  (assert (= (ParsedHead-end head) (vector-length bytes)))
  (assert (= (RequestHead-body-length request) 3))
  (write-line (RequestHead-method request))
  (write-line (RequestHead-target request))
  (for-each write-line (header-values (RequestHead-headers request) "X-Test"))
  (let loop ((count 0))
    (when (< count (vector-length bytes))
      (assert (match (parse-request-head (subvector bytes 0 count))
                ((Ok value) (match value ((None) #t) (_ #f)))
                (_ #f)))
      (loop (+ count 1)))))

(let ((response (encoded "HEAD"
                         200
                         (list (Header "Content-Type" "text/plain"))
                         #u8(97 98 99))))
  (assert (= (vector-length (ResponseParts-body response)) 0))
  (assert (string=? (text (ResponseParts-head response))
                    "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 3\r\ncontent-type: text/plain\r\n\r\n")))

;; Error classes preserve the distinction between bad framing and unsupported
;; protocol features. No request body is needed to decide Expect or TE.
(for-each (lambda (source) (reject-head source "malformed"))
          (list "GET / HTTP/1.1\nHost: a\n\n"
                "GET / HTTP/1.1\rHost: a\r\n\r\n"
                "GET / HTTP/1.1\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: a\r\nHOST: a\r\n\r\n"
                "GET / HTTP/1.1\r\nHost : a\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: a\r\n x-folded\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: user@a\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: a:65536\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: a:\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 1, 1\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: a\r\nContent-Length: +1\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: a\r\nContent-Length: -0\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n"
                "GET / HTTP/1.1 extra\r\nHost: a\r\n\r\n"
                "GET /bad%GG HTTP/1.1\r\nHost: a\r\n\r\n"
                "GET /bad#fragment HTTP/1.1\r\nHost: a\r\n\r\n"))
(for-each (lambda (source) (reject-head source "unsupported"))
          (list "GET / HTTP/1.0\r\nHost: a\r\n\r\n"
                "GET http://a/ HTTP/1.1\r\nHost: a\r\n\r\n"
                "OPTIONS * HTTP/1.1\r\nHost: a\r\n\r\n"
                "CONNECT a:80 HTTP/1.1\r\nHost: a\r\n\r\n"
                "GET / HTTP/1.1\r\nHost: [::1]\r\n\r\n"
                "POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n"
                "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\nExpect: 100-continue\r\n\r\n"))
(write-line "framing errors")

(let* ((prefix "GET / HTTP/1.1\r\nHost: a\r\nX: ") (suffix "\r\n\r\n")
       (count (- (- head-limit (string-length prefix)) (string-length suffix)))
       (exact (string-append prefix (make-string count #\x) suffix)))
  (assert (= (ParsedHead-end (parsed (ascii exact))) head-limit))
  (reject-head (string-append prefix (make-string (+ count 1) #\x) suffix)
               "head-limit"))
(reject-head (make-string head-limit #\x) "head-limit")
(let* ((head (ascii "GET / HTTP/1.1\r\nHost: a\r\n\r\n"))
       (with-body
        (vector-append head (make-vector (+ head-limit 1) (i32->u8 255)))))
  (assert (= (ParsedHead-end (parsed with-body)) (vector-length head))))
(for-each (lambda (byte)
            (let ((head (vector-concatenate
                         (list (ascii "GET / HTTP/1.1\r\nHost: a\r\nX: ")
                               (make-vector 1 byte) (ascii "\r\n\r\n")))))
              (match (parse-request-head head)
                ((Err error) (assert (string=? (kind error) "malformed")))
                ((Ok _) (panic "accepted control or non-ASCII head byte")))))
          (list (i32->u8 0) (i32->u8 127) (i32->u8 255)))
(let* ((prefix "GET / HTTP/1.1\r\nHost: a\r\n")
       (count (quotient (- (- head-limit (string-length prefix)) 2) 4))
       (source (string-append prefix
                              (string-concatenate
                               (map (lambda (_) "x:\r\n") (iota count)))
                              "\r\n"))
       (request (ParsedHead-request (parsed (ascii source)))))
  (assert (= (length (RequestHead-headers request)) (+ count 1))))
(let ((request
       (ParsedHead-request
        (parsed
         (ascii
          "POST / HTTP/1.1\r\nHost: a:0\r\nContent-Length: 8388608\r\n\r\n")))))
  (assert (= (RequestHead-body-length request) body-limit)))
(reject-head "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 8388609\r\n\r\n"
             "body-limit")
(reject-head (string-append "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: "
                            (make-string 1000 #\9)
                            "\r\n\r\n")
             "body-limit")
(write-line "exact limits")

(: check-response (-> String I32 String Bytes Unit))
(define (check-response method status head body)
  (let ((response (encoded method status (Nil) #u8(0 255 128))))
    (assert (string=? (text (ResponseParts-head response)) head))
    (assert
     (= (vector-length (ResponseParts-body response)) (vector-length body)))
    (for-each (lambda (index)
                (assert (= (vector-ref (ResponseParts-body response) index)
                           (vector-ref body index))))
              (iota (vector-length body)))))

(check-response "GET"
                200
                "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 3\r\n\r\n"
                #u8(0 255 128))
(check-response "GET" 204 "HTTP/1.1 204 \r\nConnection: close\r\n\r\n" #u8())
(check-response "HEAD" 204 "HTTP/1.1 204 \r\nConnection: close\r\n\r\n" #u8())
(check-response "GET"
                205
                "HTTP/1.1 205 \r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
                #u8())
(check-response "HEAD"
                205
                "HTTP/1.1 205 \r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
                #u8())
(check-response "GET" 304 "HTTP/1.1 304 \r\nConnection: close\r\n\r\n" #u8())
(check-response "HEAD" 304 "HTTP/1.1 304 \r\nConnection: close\r\n\r\n" #u8())
(check-response "HEAD"
                200
                "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 3\r\n\r\n"
                #u8())
(write-line "response framing")

(: reject-response (-> String I32 (List Header) String Unit))
(define (reject-response method status headers expected)
  (match (encode-response method status headers #u8())
    ((Err error) (assert (string=? (kind error) expected)))
    ((Ok _) (panic "accepted invalid response"))))

(for-each (lambda (header) (reject-response "GET" 200 (list header) "response"))
          (list (Header "X" "bad\r\nInjected: value")
                (Header "X\r\nInjected" "bad")
                (Header "X" "λ")
                (Header "Bad Name" "value")
                (Header "Content-Length" "0")
                (Header "TRANSFER-ENCODING" "chunked")
                (Header "Connection" "keep-alive")
                (Header "Trailer" "X")
                (Header "Upgrade" "websocket")))
(reject-response "GET" 199 (Nil) "response")
(reject-response "GET" 600 (Nil) "response")
(reject-response "bad method" 200 (Nil) "response")
(reject-response "CONNECT" 200 (Nil) "unsupported")
(let* ((base "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
       (count (- (- head-limit (string-length base)) 5))
       (header (Header "X" (make-string count #\x))))
  (assert (= (vector-length
              (ResponseParts-head (encoded "GET" 200 (list header) #u8())))
             head-limit))
  (reject-response "GET"
                   200
                   (list (Header "X" (make-string (+ count 1) #\x)))
                   "head-limit")
  (let ((many (map (lambda (_) (Header "x" ""))
                   (iota (quotient (- head-limit (string-length base)) 5)))))
    (assert
     (<= (vector-length (ResponseParts-head (encoded "GET" 200 many #u8())))
         head-limit))))
(write-line "safe output")
