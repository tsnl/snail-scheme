;; How an index into a file's characters becomes a location. The reader
;; places every datum it reads, so the start of each line is found once,
;; and a location is a search among them rather than a count of the
;; newlines before it.
(define-library (snail compiler read lines)
  (export
   Lines
   lines-of
   loc-at)
  (import
   (snail core base)
   (snail compiler source))
  (begin

    ;; ---- Line starts ----

    ;; `starts` holds the index of each line's first character, in order:
    ;; 0, then the index after each newline. Every text has a first line,
    ;; even an empty one.
    (struct Lines
      ((file String)
       (starts (Vector I64))))

    (: lines-of (impl (Fn String (Vector Char) -> Lines)))
    (define (lines-of file chars)
      (Lines file (list->vector (reverse (line-starts chars 0 (list 0))))))

    ;; The starts after `index`, before the `starts` found so far, which
    ;; come latest first.
    (: line-starts (impl (Fn (Vector Char) I64 (List I64) -> (List I64))))
    (define (line-starts chars index starts)
      (cond ((= index (vector-length chars)) starts)
            ((char=? (vector-ref chars index) #\newline)
             (line-starts chars (+ index 1) (Cons (+ index 1) starts)))
            (else (line-starts chars (+ index 1) starts))))

    ;; ---- Locations ----

    ;; The location of the character at `index`, or of the end of the text
    ;; when `index` is its length.
    (: loc-at (impl (Fn Lines I64 -> Loc)))
    (define (loc-at lines index)
      (let* ((starts (::starts lines))
             (line (line-of starts index)))
        (Loc (::file lines) (+ line 1) (+ (- index (vector-ref starts line)) 1))))

    ;; The number, from 0, of the last line that starts at or before
    ;; `index`. Starts ascend, so it is a binary search; the first line
    ;; starts at 0, so `low` always starts at or before `index`.
    (: line-of (impl (Fn (Vector I64) I64 -> I64)))
    (define (line-of starts index)
      (let search ((low 0)
                   (high (- (vector-length starts) 1)))
        (if (= low high)
            low
            (let ((middle (quotient (+ (+ low high) 1) 2)))
              (if (<= (vector-ref starts middle) index)
                  (search middle high)
                  (search low (- middle 1)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-lines)
    (import
     (snail stage0 testing))
    (begin
      (define (test-lines)
        (test-line-starts)
        (test-locations))

      (define (lines text)
        (lines-of "t.sld" (string->vector text)))

      (define (test-line-starts)
        (expect (lines "") (Lines "t.sld" (list->vector (list 0))))
        (expect (lines "ab") (Lines "t.sld" (list->vector (list 0))))
        (expect (lines "a\nb\n") (Lines "t.sld" (list->vector (list 0 2 4))))
        (expect (lines "\n\n") (Lines "t.sld" (list->vector (list 0 1 2)))))

      ;; A newline ends its line, the end of the text is a place, and a
      ;; column counts characters, not bytes.
      (define (test-locations)
        (let ((text (lines "ab\ncd\n\nλ😀x")))
          (expect (map (lambda (index) (loc-at text index)) (list 0 1 2 3 4 5 6 7 8 9 10))
                  (list (Loc "t.sld" 1 1)
                        (Loc "t.sld" 1 2)
                        (Loc "t.sld" 1 3)
                        (Loc "t.sld" 2 1)
                        (Loc "t.sld" 2 2)
                        (Loc "t.sld" 2 3)
                        (Loc "t.sld" 3 1)
                        (Loc "t.sld" 4 1)
                        (Loc "t.sld" 4 2)
                        (Loc "t.sld" 4 3)
                        (Loc "t.sld" 4 4))))
        (expect (loc-at (lines "") 0) (Loc "t.sld" 1 1)))))
   (else)))
