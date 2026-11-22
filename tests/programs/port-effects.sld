(import
 (snail core base)
 (snail core io))

;; These private handlers model streams with state owned by each invocation.
(record Cursor
  ((index I64)))
(record Output
  ((reversed (List String))))

(define (from-text (text String) (action (Fn → A ! mut e)))
  (→ A) (! mut e) (∀ (A e))
  (let ((position (new Cursor (index 0))))
    (handle input-port
        ((read-char (lambda ()
                      (let ((index (● position index)))
                        (if (= index (string-length text))
                            (None)
                            (begin (set! (● position index) (+ index 1))
                                   (Some (string-ref text index))))))))
      (action))))

(define (capture (action (Fn → Unit ! mut e)))
  (→ String) (! mut e) (∀ (e))
  (let ((chunks (new Output (reversed (Nil)))))
    (handle output-port
        ((write-string (lambda (text) (set! (● chunks reversed) (Cons text (● chunks reversed))))))
      (action))
    (string-concatenate (reverse (● chunks reversed)))))

(define (line (out OutputPort) (value T)) (→ Unit) (! mut) (∀ (T)) (⊨ (Repr T))
  (write out value)
  (newline out))

;; Both operations can be handled without any remaining I/O effect.
(define (silent-eof) (→ (Option Char))
  (handle input-port
      ((read-char (lambda () (None))))
    (handle output-port
        ((write-string (lambda (text) (unit))))
      (write out "discarded")
      (read-char in))))

(define (main (out OutputPort)) (→ Unit) (! mut)

  (from-text "aλ😀\n\nlast"
             (lambda ()
               (line out (read-char in))
               (line out (read-line in))
               (line out (read-line in))
               (line out (read-line in))
               (line out (read-char in))
               (line out (read-char in))))
  ;; Input handlers restore the outer cursor and do not intercept output.
  (from-text "ab"
             (lambda ()
               (line out (read-char in))
               (from-text "inner" (lambda () (line out (read-line in))))
               (line out (read-char in))))
  ;; Capturing output leaves the current input available to the computation.
  (from-text "my string input\n"
             (lambda () (write-line out (capture (lambda () (write out (read-line in)))))))
  ;; Nested output goes to its own destination, then the outer one is restored.
  (write-line out
   (capture (lambda ()
              (write-string out "before:")
              (let ((inner (capture (lambda () (write out (Some "inner"))))))
                (write-string out inner))
              (write-char out #\:)
              (display out "after"))))
  ;; Calling the operation inside its implementation forwards to the outer port.
  (write-line out
   (capture (lambda ()
              (handle output-port
                  ((write-string (lambda (text) (write-string out (string-append "[" text "]")))))
                (write out "forwarded")))))
  (line out (silent-eof))
  (unit))
