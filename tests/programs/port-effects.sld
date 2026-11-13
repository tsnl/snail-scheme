(import
 (snail core base)
 (snail core io))

;; These private handlers model streams with state owned by each invocation.
(struct Cursor
  ((index I64)))
(struct Output
  ((reversed (List String))))

(define (from-text (text String) (action (FnOnce → A ! input-port e)))
  (→ A) (! mut e) (∀ A e)
  (let ((position (Cursor 0)))
    (handle input-port
        ((read-char (lambda ()
                      (let ((index (● position index)))
                        (if (= index (string-length text))
                            (None)
                            (begin (set! (● position index) (+ index 1))
                                   (Some (string-ref text index))))))))
      (action))))

(define (capture (action (FnOnce → Unit ! output-port e)))
  (→ String) (! mut e) (∀ e)
  (let ((chunks (Output (Nil))))
    (handle output-port
        ((write-string (lambda (text) (set! (● chunks reversed) (Cons text (● chunks reversed))))))
      (action))
    (string-concatenate (reverse (● chunks reversed)))))

(define (line (value T)) (→ Unit) (! output-port) (∀ T) (⊨ (Repr T) (Drop (!) T))
  (write value)
  (newline))

;; Both operations can be handled without any remaining I/O effect.
(define (silent-eof) (→ (Option Char))
  (handle input-port
      ((read-char (lambda () (None))))
    (handle output-port
        ((write-string (lambda (text) (unit))))
      (write "discarded")
      (read-char))))

(define main
  (lambda ()
    (from-text "aλ😀\n\nlast"
               (lambda ()
                 (line (read-char))
                 (line (read-line))
                 (line (read-line))
                 (line (read-line))
                 (line (read-char))
                 (line (read-char))))
    ;; Input handlers restore the outer cursor and do not intercept output.
    (from-text "ab"
               (lambda ()
                 (line (read-char))
                 (from-text "inner" (lambda () (line (read-line))))
                 (line (read-char))))
    ;; Capturing output leaves the current input available to the computation.
    (from-text "my string input\n"
               (lambda () (write-line (capture (lambda () (write (read-line)))))))
    ;; Nested output goes to its own destination, then the outer one is restored.
    (write-line
     (capture (lambda ()
                (write-string "before:")
                (let ((inner (capture (lambda () (write (Some "inner"))))))
                  (write-string inner))
                (write-char #\:)
                (display "after"))))
    ;; Calling the operation inside its implementation forwards to the outer port.
    (write-line
     (capture (lambda ()
                (handle output-port
                    ((write-string (lambda (text) (write-string (string-append "[" text "]")))))
                  (write "forwarded")))))
    (line (silent-eof))
    (unit)))
