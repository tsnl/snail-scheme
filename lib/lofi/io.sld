;; Console text. The host implements `console` by default; a handler can
;; replace it, for example to capture output in a test.
(define-library (lofi io)
  (export
   console
   console-write
   console-read
   write-char
   write-string
   newline
   write-line
   display)
  (import
   (lofi base))
  (begin

    ;; ---- Console effect ----

    (effect console
      ((console-write (-> Char Unit))
       (console-read (-> I32)))
      (host "snail.library"
            ((console-write "snail:io/console-write")
             (console-read "snail:io/console-read"))))

    ;; ---- Text output ----

    (: write-char (-> Char Unit ! console))
    (define (write-char char)
      (console-write char))

    (: write-string (-> String Unit ! console))
    (define (write-string text)
      (let loop ((index 0))
        (when (< index (string-length text))
          (console-write (string-ref text index))
          (loop (+ index 1)))))

    (: newline (-> Unit ! console))
    (define (newline)
      (console-write #\newline))

    (: write-line (-> String Unit ! console))
    (define (write-line text)
      (write-string text)
      (newline))

    (: display (All (T) (requires (Show T)) (-> T Unit ! console)))
    (define (display value)
      (write-string (show value)))

    ))
