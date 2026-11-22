(import
 (snail core base)
 (snail core io))

;; A port is a value: a program makes its own from a function, with state
;; the port alone holds, and gives it to the code that reads or writes.
(record Cursor
  ((index I64)))

(record Output
  ((reversed (List String))))

;; ANCHOR: ports
;; A port that reads `text`, a character at a time.
(define (from-text (text String)) (→ InputPort)
  (let ((position (new Cursor (index 0))))
    (new InputPort
      (read-char (lambda ()
                   (let ((index (● position index)))
                     (if (= index (string-length text))
                         (None)
                         (begin
                           (set! (● position index) (+ index 1))
                           (Some (string-ref text index))))))))))

;; What `action` writes to the port it is given.
(define (capture (action (Fn OutputPort → Unit))) (→ String)
  (let ((chunks (new Output (reversed (Nil)))))
    (action (new OutputPort
              (write-string
               (lambda (text) (set! (● chunks reversed) (Cons text (● chunks reversed)))))))
    (string-concatenate (reverse (● chunks reversed)))))

;; ANCHOR_END: ports

(define (line (out OutputPort) (value T)) (→ Unit) (∀ (T)) (⊨ (Repr T))
  (write out value)
  (newline out))

;; Ports that read nothing and keep nothing touch no stream at all.
(define (silent-eof) (→ (Option Char))
  (let ((in (new InputPort (read-char (lambda () (None)))))
        (out (new OutputPort (write-string (lambda (text) (unit))))))
    (write out "discarded")
    (in::read-char)))

(define (main (out OutputPort)) (→ Unit)
  (let ((in (from-text "aλ😀\n\nlast")))
    (line out (in::read-char))
    (line out (read-line in))
    (line out (read-line in))
    (line out (read-line in))
    (line out (in::read-char))
    (line out (in::read-char)))
  ;; Each port keeps its own cursor, and reading one writes nothing.
  (let ((in (from-text "ab")))
    (line out (in::read-char))
    (line out (read-line (from-text "inner")))
    (line out (in::read-char)))
  ;; Capturing output leaves the input available to the computation.
  (let ((in (from-text "my string input\n")))
    (write-line out (capture (lambda (captured) (write captured (read-line in))))))
  ;; Nested output goes to its own port, and the outer one is still there.
  (write-line out
              (capture (lambda (outer)
                         (outer::write-string "before:")
                         (let ((inner
                                (capture (lambda (inner) (write inner (Some "inner"))))))
                           (outer::write-string inner))
                         (write-char outer #\:)
                         (display outer "after"))))
  ;; A port made from another one writes through it.
  (write-line out
              (capture (lambda (outer)
                         (write (new OutputPort
                                  (write-string
                                   (lambda (text)
                                     (outer::write-string (string-append "[" text "]")))))
                                "forwarded"))))
  (line out (silent-eof))
  (unit))
