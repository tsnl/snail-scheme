(import
 (snail core base)
 (snail core io)
 (snail shell http))

(define (ascii (text String)) (→ Bytes)
  (vector-generate (string-length text)
                   (lambda (index) (i32->u8 (char->i32 (string-ref text index))))))

(define (text (bytes Bytes)) (→ String)
  (string-generate (vector-length bytes)
                   (lambda (index) (i32->char (u8->i32 (vector-ref bytes index))))))

(define (assert (condition Bool)) (→ Unit) (unless condition (panic "HTTP assertion failed")))

(define (kind (error HttpError)) (→ String)
  (match error
    ((Malformed _) "malformed")
    ((Unsupported _) "unsupported")
    ((HeadTooLarge) "head-limit")
    ((BodyTooLarge) "body-limit")
    ((InvalidResponse _) "response")))

(define (reject-head (source String) (expected String)) (→ Unit)
  (match (parse-request-head (ascii source))
    ((Err error) (assert (string=? (kind error) expected)))
    ((Ok _) (panic "accepted invalid head"))))

(define (parsed (bytes Bytes)) (→ ParsedHead)
  (match (parse-request-head bytes)
    ((Ok value) (match value ((Some head) head) ((None) (panic "incomplete test head"))))
    ((Err _) (panic "rejected test head"))))

(define (encoded (method String) (status I32) (headers (List Header)) (bytes Bytes))
  (→ ResponseParts)
  (match (encode-response method status headers bytes)
    ((Ok response) response)
    ((Err _) (panic "rejected test response"))))

(let* ((source
        "POST /a%2Fb?x=1&x=2 HTTP/1.1\r\nHost: example.test:8080\r\nContent-Length: 3\r\nX-Test: first\r\nx-TEST:\tsecond \t\r\n\r\n")
       (bytes (ascii source))
       (head (parsed (vector-append bytes #u8(0 255 128))))
       (request (● head request)))
  (assert (= (● head end) (vector-length bytes)))
  (assert (= (● request body-length) 3))
  (write-line (● request method))
  (write-line (● request target))
  (for-each write-line (header-values (● request headers) "X-Test"))
  (let loop ((count 0))
    (when (< count (vector-length bytes))
      (assert (match (parse-request-head (subvector bytes 0 count))
                ((Ok value) (match value ((None) #t) (_ #f)))
                (_ #f)))
      (loop (+ count 1)))))

(let ((response (encoded "HEAD" 200 (list (Header "Content-Type" "text/plain")) #u8(97 98 99))))
  (assert (= (vector-length (● response body)) 0))
  (assert (string=? (text (● response head))
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
  (assert (= (● (parsed (ascii exact)) end) head-limit))
  (reject-head (string-append prefix (make-string (+ count 1) #\x) suffix) "head-limit"))
(reject-head (make-string head-limit #\x) "head-limit")
(let* ((head (ascii "GET / HTTP/1.1\r\nHost: a\r\n\r\n"))
       (with-body (vector-append head (make-vector (+ head-limit 1) (i32->u8 255)))))
  (assert (= (● (parsed with-body) end) (vector-length head))))
(for-each (lambda (byte)
            (let ((head (vector-concatenate (list (ascii "GET / HTTP/1.1\r\nHost: a\r\nX: ")
                                                  (make-vector 1 byte) (ascii "\r\n\r\n")))))
              (match (parse-request-head head)
                ((Err error) (assert (string=? (kind error) "malformed")))
                ((Ok _) (panic "accepted control or non-ASCII head byte")))))
          (list (i32->u8 0) (i32->u8 127) (i32->u8 255)))
(let* ((prefix "GET / HTTP/1.1\r\nHost: a\r\n")
       (count (quotient (- (- head-limit (string-length prefix)) 2) 4))
       (source
        (string-append prefix (string-concatenate (map (lambda (_) "x:\r\n") (iota count))) "\r\n"))
       (request (● (parsed (ascii source)) request)))
  (assert (= (length (● request headers)) (+ count 1))))
(let ((request
       (● (parsed (ascii "POST / HTTP/1.1\r\nHost: a:0\r\nContent-Length: 8388608\r\n\r\n"))
          request)))
  (assert (= (● request body-length) body-limit)))
(reject-head "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 8388609\r\n\r\n" "body-limit")
(reject-head
 (string-append "POST / HTTP/1.1\r\nHost: a\r\nContent-Length: " (make-string 1000 #\9) "\r\n\r\n")
 "body-limit")
(write-line "exact limits")

(define (check-response (method String) (status I32) (head String) (body Bytes)) (→ Unit)
  (let ((response (encoded method status (Nil) #u8(0 255 128))))
    (assert (string=? (text (● response head)) head))
    (assert (= (vector-length (● response body)) (vector-length body)))
    (for-each (lambda (index)
                (assert
                 (= (vector-ref (● response body) index) (vector-ref body index))))
              (iota (vector-length body)))))

(check-response "GET"
                200
                "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 3\r\n\r\n"
                #u8(0 255 128))
(check-response "GET" 204 "HTTP/1.1 204 \r\nConnection: close\r\n\r\n" #u8())
(check-response "HEAD" 204 "HTTP/1.1 204 \r\nConnection: close\r\n\r\n" #u8())
(check-response "GET" 205 "HTTP/1.1 205 \r\nConnection: close\r\nContent-Length: 0\r\n\r\n" #u8())
(check-response "HEAD" 205 "HTTP/1.1 205 \r\nConnection: close\r\nContent-Length: 0\r\n\r\n" #u8())
(check-response "GET" 304 "HTTP/1.1 304 \r\nConnection: close\r\n\r\n" #u8())
(check-response "HEAD" 304 "HTTP/1.1 304 \r\nConnection: close\r\n\r\n" #u8())
(check-response "HEAD" 200 "HTTP/1.1 200 \r\nConnection: close\r\nContent-Length: 3\r\n\r\n" #u8())
(write-line "response framing")

(define (reject-response (method String) (status I32) (headers (List Header)) (expected String))
  (→ Unit)
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
  (assert
   (= (vector-length (● (encoded "GET" 200 (list header) #u8()) head)) head-limit))
  (reject-response "GET" 200 (list (Header "X" (make-string (+ count 1) #\x))) "head-limit")
  (let ((many (map (lambda (_) (Header "x" ""))
                   (iota (quotient (- head-limit (string-length base)) 5)))))
    (assert (<= (vector-length (● (encoded "GET" 200 many #u8()) head)) head-limit))))
(write-line "safe output")

;; Targets decode as `new URL` reads them: the path's segments, each
;; decoded, with dot segments resolved, and the query as URLSearchParams
;; pairs. The expected lines for well-formed targets were produced once by
;; Node from `new URL(target, base)`, splitting its pathname at `/` before
;; decoding each segment. Malformed escapes and text that is not UTF-8,
;; which Node passes through or replaces, are errors here.
(define (target-text (source String)) (→ String)
  (match (parse-target source)
    ((Err error) (string-append source " -> error " (kind error)))
    ((Ok target)
     (string-join (Cons (string-append source
                                       " -> "
                                       (string-concatenate
                                        (map (lambda (segment) (string-append "[" segment "]"))
                                             (● target path))))
                        (map
                         (lambda (pair) (string-append (● pair first) "=" (● pair second)))
                         (● target query)))
                  " "))))

(for-each (lambda (source) (write-line (target-text source)))
          (list "/"
                "/api/file?path=src%2Fmain.sld"
                "/api/file?path=a+b%2Bc%20d"
                "/api/file?path=%CE%BB%F0%9F%98%80.sld"
                "/api/run/start?target=web&target=other&&x&=y"
                "/a%2Fb/c/"
                "/a/./b/../c"
                "/a/b/.."
                "/a/%2e%2E/b"
                "/.."
                "/a/."
                "/api//file"
                "/x?a=b=c&q=%3F%26%3D"
                "/x?"
                "/caf%C3%A9?%C3%A9=%C3%A9"
                "/x?path=%2e%2e/secret"
                "/bad%GG"
                "/bad%4"
                "/x?path=%"
                "/%FF"
                "/x?path=%C0%AF"
                "/x?path=%ED%A0%80"
                "/a b"
                "/a#frag"
                "/λ"
                "api/file" "" "*"))
(match (parse-request-head (ascii "GET /api/file?path=%CE%BB HTTP/1.1\r\nHost: a\r\n\r\n"))
  ((Ok (Some parsed))
   (match (parse-target (● (● parsed request) target))
     ((Ok target)
      (assert (match (assoc-ref (● target query) "path")
                ((Some path) (string=? path "λ"))
                ((None) #f))))
     ((Err _) (panic "rejected a parsed target"))))
  (_ (panic "rejected test head")))
(write-line "request targets")

;; A stream's head has no Content-Length: the body ends when the
;; connection closes.
(define (stream-head (status I32) (headers (List Header))) (→ String)
  (match (encode-stream-head status headers)
    ((Ok head) (text head))
    ((Err error) (string-append "error " (kind error)))))

(assert (string=? (stream-head 200
                               (list (Header "Content-Type" "text/event-stream")
                                     (Header "Cache-Control" "no-store")))
                  "HTTP/1.1 200 \r\nConnection: close\r\ncontent-type: text/event-stream\r\ncache-control: no-store\r\n\r\n"))
(assert (string=? (stream-head 503 (Nil)) "HTTP/1.1 503 \r\nConnection: close\r\n\r\n"))
(for-each (lambda (status) (assert (string=? (stream-head status (Nil)) "error response")))
          (list 199 204 205 304 600))
(for-each (lambda (header) (assert (string=? (stream-head 200 (list header)) "error response")))
          (list (Header "Content-Length" "0")
                (Header "Transfer-Encoding" "chunked")
                (Header "X" "bad\r\nInjected: value")))
(assert
 (string=? (stream-head 200 (list (Header "X" (make-string head-limit #\x)))) "error head-limit"))
(write-line "stream heads")
