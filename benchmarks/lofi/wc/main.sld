;; Word boundaries are exactly ASCII space and LF, as in the pinned source.
(import (lofi base) (lofi io) (lofi datum) (lofi read))

;; ---- Canonical counting algorithm ----

(def wcport (-> InputPort (List I64))
  (lambda (port)
    (begin
      (def loop (-> I64 I64 I64 Bool (List I64))
        (lambda (lines words characters in-word)
          (match (read-char port)
            ((character-end) (cons lines (cons words (cons characters (empty-list )))))
            ((character-value character)
              (if (char=? character #\space)
                (loop lines words (+ characters (ann 1 I64)) #f)
                (if (char=? character #\newline)
                  (loop (+ lines (ann 1 I64)) words (+ characters (ann 1 I64)) #f)
                  (loop lines (if in-word words (+ words (ann 1 I64))) (+ characters (ann 1 I64)) #t)))))))
      (loop (ann 0 I64) (ann 0 I64) (ann 0 I64) #f))))

(def go (-> String (List I64))
  (lambda (filename) (call-with-input-file filename wcport)))

;; ---- Complete result predicate and typed input boundary ----

(define-extern barrier "benchmark" "barrier" (-> Bool))
(def exact-input (-> Datum I64)
  (lambda (value)
    (match (datum-number-value value)
      ((exact-number number) number)
      ((rational-number number) (datum-fail "count must fit I64"))
      ((inexact-number number) (datum-fail "count must be exact"))
      ((complex-number real imaginary) (datum-fail "count must be exact")))))

(def Specification (datatype ()
  (specification (count I64 specification-count) (path String specification-path)
    (expected Datum specification-expected))))

(def read-specification (-> InputPort Specification)
  (lambda (port)
    (begin (let count (exact-input (read-value! (read port))))
      (begin (let path (datum-string-value (read-value! (read port))))
        (begin (let expected (read-value! (read port)))
          (specification count path expected))))))

(def configured (call-with-input-file "input.txt" read-specification))
(def configured-count (-> I64) (lambda () (specification-count configured)))
(def hide-path (-> I64 String String)
  (lambda (count path) (if (barrier) path (unreachable))))

(def Result (datatype () (not-run) (counts (values (List I64)))))
(def counts->datum (-> (List I64) Datum)
  (lambda (values)
    (if (null? values) (datum-null)
      (datum-cons (datum-number (exact-number (car values))) (counts->datum (cdr values))))))
(def result->datum (-> Result Datum)
  (lambda (result)
    (match result ((not-run) (datum-boolean #f)) ((counts values) (counts->datum values)))))

(def bench (-> I64 I64)
  (lambda (count)
    (begin
      (def repeat (-> I64 Result I64)
        (lambda (index result)
          (if (< index count)
            (repeat (+ index (ann 1 I64)) (counts (go (hide-path count (specification-path configured)))))
            (if (datum=? (result->datum result) (specification-expected configured)) (ann 1 I64) (ann 0 I64)))))
      (repeat (ann 0 I64) (not-run)))))

(unit)
