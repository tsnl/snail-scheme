(define-library (control search)
  (export
   signal-negative)
  (import
   (snail-core base)
   (snail-core io)
   (control signal))
  (begin
    ;; Signals the first negative item, after reporting each one it passes.
    (: signal-negative (-> (List I64) Unit ! Signal console))
    (define (signal-negative items)
      (for-each (lambda (item)
                  (write-line (string-append "check " (show item)))
                  (when (< item 0) (signal item)))
                items))))
