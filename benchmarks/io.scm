;; Sequential, buffered literal search over a frozen corpus of original text.
;;
;; Run from the repository root. Each query reopens every document, reads it
;; completely, and closes it before advancing to the next document. Substring
;; search is a native operation so this is a host-heavy comparison workload.
;; The operating-system page cache is intentionally left warm: this benchmark
;; does not claim to measure cold disks, storage bandwidth, or concurrent I/O.
(import (scheme base) (scheme file) (scheme write) (scheme time)
        (scheme process-context) (snail-scheme runtime))

(define corpus-directory "benchmarks/corpus/")
(define document-count 64)
(define chunk-size 4096)
(define queries '("copper owl" "river lantern" "winter fern" "silent comet" "absent phrase"))

;; Streaming search retains just enough suffix for a match crossing the next
;; chunk boundary. A suffix shorter than the needle contains no complete match,
;; so rescanning it cannot count an already reported occurrence twice.

(define (occurrences text needle)
  (let loop ((start 0) (count 0))
    (let ((match (string-contains text needle start)))
      (if match
          (loop (+ match 1) (+ count 1))
          count))))

(define (trailing-prefix text needle)
  (let* ((length (string-length text))
         (keep (- (string-length needle) 1))
         (start (if (> length keep) (- length keep) 0)))
    (substring text start length)))

(define-record-type search-result
  (make-result matches characters)
  search-result?
  (matches result-matches)
  (characters result-characters))

(define (read-matches port needle size)
  (let loop ((carry "") (matches 0) (characters 0))
    (let ((chunk (read-string size port)))
      (if (eof-object? chunk)
          (make-result matches characters)
          (let ((text (string-append carry chunk)))
            (loop (trailing-prefix text needle)
                  (+ matches (occurrences text needle))
                  (+ characters (string-length chunk))))))))

(define (search-file path needle size)
  (call-with-input-file path
    (lambda (port) (read-matches port needle size))))

(define (document-name number)
  (string-append corpus-directory "document-"
                 (cond ((< number 10) "00") ((< number 100) "0") (else ""))
                 (number->string number) ".txt"))

;; A weighted count distinguishes file/query order errors that a total match
;; count could miss. Character counts also prove that unsuccessful searches and
;; successful searches both read their files completely.

(define-record-type search-summary
  (make-summary matches checksum characters)
  search-summary?
  (matches summary-matches)
  (checksum summary-checksum)
  (characters summary-characters))

(define empty-summary (make-summary 0 0 0))

(define (add-result summary result document query)
  (let ((matches (result-matches result)))
    (make-summary (+ (summary-matches summary) matches)
                  (+ (summary-checksum summary) (* (+ document 1) (+ query 1) matches))
                  (+ (summary-characters summary) (result-characters result)))))

(define (search-document document summary)
  (let loop ((remaining queries) (query 0) (summary summary))
    (if (null? remaining)
        summary
        (let ((result (search-file (document-name document) (car remaining) chunk-size)))
          (loop (cdr remaining) (+ query 1)
                (add-result summary result document query))))))

(define (workload)
  (let loop ((document 0) (summary empty-summary))
    (if (= document document-count)
        summary
        (loop (+ document 1) (search-document document summary)))))

(define (summary-values summary)
  (list (summary-matches summary) (summary-checksum summary) (summary-characters summary)))

;; Fixed answers come from the separate corpus generator and its SHA256SUMS.
;; The runner verifies that manifest before timing any executable.

(define expected-summary '(2534 207395 1609295))

(define (require-equal actual expected description)
  (unless (equal? actual expected)
    (error description actual expected)))

(define (check-substrings)
  (require-equal (occurrences "aaaa" "aaa") 2 "overlapping literal matches")
  (require-equal (occurrences "copper owl" "copper owl") 1 "whole-string match")
  (require-equal (occurrences "copper owl" "missing") 0 "absent match")
  (require-equal (occurrences "" "owl") 0 "empty input")
  (require-equal (string-contains "owl owl" "owl" 1) 4 "search start offset"))

(define (check-chunk-size size)
  (let ((path (string-append corpus-directory "checks.txt")))
    (for-each
     (lambda (needle)
       (let ((result (search-file path needle size)))
         (require-equal (result-matches result) 1 "chunk boundary search")
         (require-equal (result-characters result) 55 "complete file read")))
     '("copper owl" "river lantern" "winter fern" "silent comet"))))

(define (check-search)
  (check-substrings)
  (for-each check-chunk-size '(1 3 7 4096)))

(define (repeat-work count)
  (let loop ((remaining count) (checksum 0))
    (if (= remaining 0)
        checksum
        (let ((summary (workload)))
          (require-equal (summary-values summary) expected-summary "corpus search result")
          (loop (- remaining 1) (+ checksum (summary-checksum summary)))))))

(define (positive-count text)
  (let ((count (string->number text)))
    (unless (and (exact-integer? count) (> count 0))
      (error "repeat count must be a positive integer" text))
    count))

(define (repetitions)
  (let ((arguments (cdr (command-line))))
    (cond ((null? arguments) 4)
          ((null? (cdr arguments)) (positive-count (car arguments)))
          (else (error "usage: io [REPETITIONS]")))))

(define (elapsed-microseconds start finish)
  (quotient (* (- finish start) 1000000) (jiffies-per-second)))

(define (write-milliseconds microseconds)
  (display (quotient microseconds 1000))
  (display ".")
  (let ((fraction (modulo microseconds 1000)))
    (when (< fraction 100) (display "0"))
    (when (< fraction 10) (display "0"))
    (display fraction)))

(define (report checksum elapsed count)
  (display "I/O: sequential frozen-corpus search") (newline)
  (display "checksum: ") (write checksum) (newline)
  (display "elapsed: ") (write-milliseconds elapsed)
  (display " ms; repetitions: ") (write count) (newline))

(define (main)
  (check-search)
  (let* ((count (repetitions))
         (start (current-jiffy))
         (checksum (repeat-work count))
         (finish (current-jiffy)))
    (report checksum (elapsed-microseconds start finish) count)))

(main)
