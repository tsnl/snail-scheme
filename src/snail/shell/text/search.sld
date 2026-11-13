;; Literal, case-insensitive text search with Unicode scalar coordinates.
;; Callers own file identities and revisions; this scanner only sees text.
(define-library (snail shell text search)
  (export Query parse-query Occurrence scan)
  (import
   (snail core base)
   (snail shell text)
   (snail shell task))
  (begin
    (record Query
      ((text String)))

    (define (parse-query (text String)) (→ (Result Query String))
      (if (and (> (string-length text) 0) (<= (string-length text) 128)
               (not (any? (lambda (char) (or (char=? char #\newline) (char=? char #\return)
                                             (char=? char #\null)))
                          (string->list text))))
          (Ok (new Query (text (string-downcase text))))
          (Err "search needs 1–128 characters on one line")))

    (record Occurrence
      ((line I64)
       (column I64)
       (snippet String)))

    ;; ---- Scanning ----

    ;; Offsets and columns count Unicode scalars, matching the editor and
    ;; compiler. Simple case mapping preserves that count. A query cannot
    ;; cross a line; CRLF counts as one newline and snippets omit the CR.

    (define (scan (query Query) (text String) (end I64) (room I64)) (→ (List Occurrence)) (! tasks)
      (let ((needle (● query text)))
        (let loop ((at 0) (line 1) (start 0) (hits (ann (Nil) (List Occurrence))) (room room)
                   (next-yield 0))
          (cond ((or (>= at end) (= room 0)) (reverse hits))
                (else
                 (when (>= at next-yield) (yield))
                 (let* ((found (matches-at? text needle at end))
                        (char (string-ref text at))
                        (newline (or (char=? char #\newline) (char=? char #\return)))
                        (step (if (and (char=? char #\return) (< (+ at 1) end)
                                       (char=? (string-ref text (+ at 1)) #\newline)) 2 1))
                        (next (if found
                                  (Cons (new Occurrence
                                          (line line)
                                          (column (+ 1 (- at start)))
                                          (snippet (snippet text start at)))
                                        hits) hits)))
                   (loop (+ at step) (if newline (+ line 1) line) (if newline (+ at step) start)
                         next (if found (- room 1) room)
                         (if (>= at next-yield) (+ at 4096) next-yield))))))))

    (define (matches-at? (text String) (needle String) (at I64) (end I64)) (→ Bool)
      (and (<= (+ at (string-length needle)) end)
           (let loop ((index 0))
             (or (= index (string-length needle))
                 (and (char=? (char-downcase (string-ref text (+ at index)))
                              (string-ref needle index))
                      (loop (+ index 1)))))))

    (define (snippet (text String) (line-start I64) (at I64)) (→ String)
      (let ((start (max line-start (- at 40))))
        (let loop ((end start))
          (if (or (>= end (min (string-length text) (+ start 160)))
                  (char=? (string-ref text end) #\newline) (char=? (string-ref text end) #\return))
              (string-append (if (> start line-start) "…" "") (substring text start end))
              (loop (+ end 1))))))))
