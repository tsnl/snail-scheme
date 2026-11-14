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

    (record Hit
      ((path String)
       (revision String)
       (line I64)
       (column I64)
       (snippet String)))

    (record Results
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
        (cond
         ((> (length hits) 200) (new Results (hits (take hits 200)) (skipped skipped) (limited #t)))
         ((and (<= budget 0) (not (null? paths)))
          (new Results (hits hits) (skipped skipped) (limited #t)))
         (else
          (match paths
            ((Nil) (new Results (hits hits) (skipped skipped) (limited #f)))
            ((Cons path rest)
             (yield)
             (match (read-project-text root path)
               ((Err _) (loop rest hits (+ skipped 1) budget))
               ((Ok snapshot)
                (let* ((text (● snapshot text))
                       (end (min budget (string-length text)))
                       (found (map (lambda (at)
                                     (new Hit (path path) (revision (● snapshot revision))
                                          (line (● at line)) (column (● at column))
                                          (snippet (● at snippet))))
                                   (scan query text end (- 201 (length hits)))))
                       (all (append hits found)))
                  (if (< end (string-length text))
                      (new Results (hits (take all 200)) (skipped skipped) (limited #t))
                      (loop rest all skipped (- budget end))))))))))))

    ))
