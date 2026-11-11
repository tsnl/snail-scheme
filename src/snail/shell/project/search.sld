;; A bounded literal search of the same saved files the editor can read.
;; Each hit carries the revision its scalar coordinates were computed from.
;; The service yields between files and scan chunks; it holds no index.
(define-library (snail shell project search)
  (export Query parse-query Hit
          Results search-project)
  (import
   (snail core base)
   (snail core io)
   (snail shell text search)
   (snail shell task)
   (snail shell project files))
  (begin

    ;; ---- Queries and results ----

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

    (define (search-project (root String) (paths (List String)) (query Query))
      (→ Results)
      (! fs tasks)
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
                     (let* ((text (::text snapshot))
                            (end (min budget (string-length text)))
                            (found (map (lambda (at)
                                          (Hit path (::revision snapshot)
                                               (::line at) (::column at)
                                               (::snippet at)))
                                        (scan query text end (- 201 (length hits)))))
                            (all (append hits found)))
                       (if (< end (string-length text))
                           (Results (take all 200) skipped #t)
                           (loop rest all skipped (- budget end))))))))))))

    ))
