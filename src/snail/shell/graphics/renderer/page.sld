;; Any browser app can opt its renderer into a downloadable trace with ?trace=1.
(define-library (snail shell graphics renderer page)
  (export page-renderer-config)
  (import
   (snail core base)
   (snail shell fetch)
   (snail shell files)
   (snail shell graphics api-trace))
  (begin
    (define (trace-query? (query String)) (→ Bool)
      (let ((end (match (string-index query #\&) ((Some i) i) (_ (string-length query)))))
        (or (string=? (substring query 0 end) "trace=1")
            (and (< end (string-length query))
                 (trace-query? (substring query (+ end 1) (string-length query)))))))
    (define (page-renderer-config (fetch Fetch) (files FilePicker)) (→ RendererConfig)
      (let* ((url ((● fetch page-address)))
             (base (match (string-index url #\#) ((Some n) (substring url 0 n)) (_ url)))
             (on (match (string-index base #\?)
                   ((Some n) (trace-query? (substring base (+ n 1) (string-length base))))
                   (_ #f))))
        (new RendererConfig
          (trace (if on (Some ((● files download-text) "renderer.jsonl")) (None))))))))
