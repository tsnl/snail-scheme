(define-library (control search)
  (export
   signal-negative)
  (import
   (snail-core base)
   (snail-core io)
   (control signal))
  (begin
    ;; Signals each negative item, after reporting each item it passes; a
    ;; handler that does not resume stops it at the first.
    (: signal-negative (-> (List I64) Unit ! Signal console))
    (define (signal-negative items)
      (for-each (lambda (item)
                  (write-line (string-append "check " (show item)))
                  (when (< item 0) (signal item)))
                items))))
