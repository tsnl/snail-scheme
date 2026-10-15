;; Host-only scalar-provider diagnostics. Catching these conditions lets this
;; probe inspect ownership transitions; a failed guest invocation never resumes.

;; ---- Independent observations of raw service state ----

(define (boundary-check condition)
  (unless condition (error 'io-boundary "unexpected scalar-provider behavior")))
(define (boundary-message action)
  (guard (failure
          ((message-condition? failure) (condition-message failure))
          (else (raise failure)))
    (action)
    "unexpected normal return"))
(define (boundary-path text)
  (io-begin-path)
  (for-each io-path-character (string->list text)))
(define (boundary-open direction path)
  (boundary-path path) (io-open direction))
(define (boundary-bytes path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block) #f)
    get-bytevector-all))

;; ---- Lookahead includes NUL and EOF, without text-transcoder normalization ----

(let ((id (boundary-open 'input "scalar-input")))
  (for-each
   (lambda (expected)
     (boundary-check (= (io-read id #t) expected))
     (boundary-check (= (io-read id #t) expected))
     (boundary-check (= (io-read id #f) expected)))
   '(0 65279 13 10 127 128 2047 2048 55295 57344 65535 65536 955 128512 1114111 -1 -1))
  (boundary-check (string=? (boundary-message (lambda () (io-output id)))
                            "expected an open output port"))
  (boundary-check (string=? (boundary-message (lambda () (io-write id 55296)))
                            "invalid Unicode scalar"))
  (boundary-check (string=? (boundary-message (lambda () (io-write id 65)))
                            "expected an output port"))
  (io-close id)
  (boundary-check (string=? (boundary-message (lambda () (io-read id #f)))
                            "unknown or closed file port")))
(boundary-check (string=? (boundary-message (lambda () (io-write -3 55296)))
                          "unknown or closed file port"))

;; ---- Failed opens consume paths and IDs; borrowed close consumes neither ----

(let ((before io-next-id))
  (boundary-path "does-not-exist")
  (boundary-message (lambda () (io-open 'input)))
  (boundary-check (= io-next-id (+ before 1)))
  (boundary-check (not io-path))
  (io-close -2) (io-close -2)
  (boundary-check (= io-next-id (+ before 1))))
(boundary-path "discarded")
(boundary-path "replacement")
(boundary-check (string=? (io-take-path) "replacement"))
(boundary-check (string=? (boundary-message io-take-path) "no pathname transfer is active"))

;; ---- Cleanup follows issue order and preserves the original failure ----

(let* ((first (boundary-open 'output "shared-output"))
       (second (boundary-open 'output "shared-output")))
  (io-write first 65) (io-write second 66)
  (boundary-check (not (io-finish #f)))
  (boundary-check (equal? (boundary-bytes "shared-output") #vu8(66))))
(let* ((failed (boundary-open 'output "/dev/full"))
       (port (vector-ref (cdr (io-entry failed)) 0))
       (descriptor (port-file-descriptor port))
       (pending (boundary-open 'output "cleanup-output"))
       (original (condition (make-error) (make-message-condition "first failure"))))
  (io-write failed 65) (io-write pending 67)
  (boundary-path "unfinished")
  (boundary-check (eq? (io-finish original) original))
  (boundary-check (and (null? io-files) (not io-path) (port-closed? port)))
  (boundary-check (not (file-exists? (string-append "/proc/self/fd/" (number->string descriptor)))))
  (boundary-check (equal? (boundary-bytes "cleanup-output") #vu8(67))))

;; ---- The last legal ID is issued once; exhaustion precedes file truncation ----

(set! io-next-id 2147483647)
(let ((last (boundary-open 'output "last-output")))
  (boundary-check (= last 2147483647)) (io-close last))
(boundary-path "shared-output")
(boundary-check (string=? (boundary-message (lambda () (io-open 'output))) "file port IDs exhausted"))
(boundary-check (and (= io-next-id 2147483648) (not io-path)))
(boundary-check (equal? (boundary-bytes "shared-output") #vu8(66)))
(boundary-check (not (io-finish #f)))
(display "PASS Chez scalar I/O boundary\n")
