;; A bounded literal search of the same saved files the editor can read.
;; Each hit carries the revision its scalar coordinates were computed from.
;; The service yields between files and scan chunks; it holds no index.
(define-library (snail shell project search)
  (export Query parse-query Hit Hit-path Hit-revision Hit-line Hit-column Hit-snippet
          Results Results-hits Results-skipped Results-limited search-project)
  (import
   (snail core base)
   (snail core io)
   (snail shell text)
   (snail shell task)
   (snail shell project files))
  (begin

    ;; ---- Queries and results ----

    (struct Query
      ((text String)))

    (: parse-query (-> String (Result Query String)))
    (define (parse-query text)
      (if (and (> (string-length text) 0) (<= (string-length text) 128)
               (not (any? (lambda (char) (or (char=? char #\newline) (char=? char #\return)
                                             (char=? char #\null)))
                          (string->list text))))
          (Ok (Query (string-downcase text)))
          (Err "search needs 1–128 characters on one line")))

    (struct Hit
      ((path String)
       (revision String)
       (line I64)
       (column I64)
       (snippet String)))

    (struct Results
      ((hits (List Hit))
       (skipped I64)
       (limited Bool)))

    ;; At most 200 hits and four million scalars per request. A 201st hit
    ;; proves truncation. Unreadable, binary and oversized files count as
    ;; skipped. The existing reader bounds each file to eight MiB.
    (: search-project (-> String (List String) Query Results ! fs tasks))
    (define (search-project root paths query)
      (let loop ((paths paths) (hits (ann (Nil) (List Hit))) (skipped 0) (budget 4000000))
        (cond ((> (length hits) 200) (Results (take hits 200) skipped #t))
              ((and (<= budget 0) (not (null? paths))) (Results hits skipped #t))
              (else
               (match paths
                 ((Nil) (Results hits skipped #f))
                 ((Cons path rest)
                  (yield)
                  (match (read-project-text root path)
                    ((Err _) (loop rest hits (+ skipped 1) budget))
                    ((Ok snapshot)
                     (let* ((text (ProjectText-text snapshot))
                            (end (min budget (string-length text)))
                            (found (scan query path snapshot end (- 201 (length hits))))
                            (all (append hits found)))
                       (if (< end (string-length text))
                           (Results (take all 200) skipped #t)
                           (loop rest all skipped (- budget end))))))))))))

    ;; ---- Scanning ----

    ;; Offsets and columns count Unicode scalars, matching the editor and
    ;; compiler. Simple case mapping preserves that count. A query cannot
    ;; cross a line; CRLF counts as one newline and snippets omit the CR.
    (: scan (-> Query String ProjectText I64 I64 (List Hit) ! tasks))
    (define (scan query path snapshot end room)
      (let ((text (ProjectText-text snapshot)) (needle (Query-text query)))
        (let loop ((at 0) (line 1) (start 0) (hits (ann (Nil) (List Hit))) (room room)
                   (next-yield 0))
          (cond ((or (>= at end) (= room 0)) (reverse hits))
                (else
                 (when (>= at next-yield) (yield))
                 (let* ((found (matches-at? text needle at end))
                        (char (string-ref text at))
                        (newline (or (char=? char #\newline) (char=? char #\return)))
                        (step (if (and (char=? char #\return) (< (+ at 1) end)
                                       (char=? (string-ref text (+ at 1)) #\newline)) 2 1))
                        (next (if found (Cons (Hit path (ProjectText-revision snapshot)
                                                   line (+ 1 (- at start)) (snippet text start at))
                                              hits) hits)))
                   (loop (+ at step) (if newline (+ line 1) line) (if newline (+ at step) start)
                         next (if found (- room 1) room)
                         (if (>= at next-yield) (+ at 4096) next-yield))))))))

    (: matches-at? (-> String String I64 I64 Bool))
    (define (matches-at? text needle at end)
      (and (<= (+ at (string-length needle)) end)
           (let loop ((index 0))
             (or (= index (string-length needle))
                 (and (char=? (char-downcase (string-ref text (+ at index)))
                              (string-ref needle index))
                      (loop (+ index 1)))))))

    (: snippet (-> String I64 I64 String))
    (define (snippet text line-start at)
      (let ((start (max line-start (- at 40))))
        (let loop ((end start))
          (if (or (>= end (min (string-length text) (+ start 160)))
                  (char=? (string-ref text end) #\newline) (char=? (string-ref text end) #\return))
              (string-append (if (> start line-start) "…" "") (substring text start end))
              (loop (+ end 1))))))))
