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
(define (from-text (mut Mut) (text String)) (→ InputPort)
  (let ((position (new Cursor (index 0))))
    (new InputPort
      (read-char (lambda ()
                   (let ((index (● position index)))
                     (if (= index (string-length text))
                         (None)
                         (begin
                           (set! mut (● position index) (+ index 1))
                           (Some (string-ref text index))))))))))

;; What `action` writes to the port it is given.
(define (capture (mut Mut) (action (Fn OutputPort → Unit))) (→ String)
  (let ((chunks (new Output (reversed (Nil)))))
    (action (new OutputPort
              (write-string
               (lambda (text) (set! mut (● chunks reversed) (Cons text (● chunks reversed)))))))
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
    (read-char in)))

(define (main (mut Mut) (out OutputPort)) (→ Unit)
  (let ((in (from-text mut "aλ😀\n\nlast")))
    (line out (read-char in))
    (line out (read-line in))
    (line out (read-line in))
    (line out (read-line in))
    (line out (read-char in))
    (line out (read-char in)))
  ;; Each port keeps its own cursor, and reading one writes nothing.
  (let ((in (from-text mut "ab")))
    (line out (read-char in))
    (line out (read-line (from-text mut "inner")))
    (line out (read-char in)))
  ;; Capturing output leaves the input available to the computation.
  (let ((in (from-text mut "my string input\n")))
    (write-line out (capture mut (lambda (captured) (write captured (read-line in))))))
  ;; Nested output goes to its own port, and the outer one is still there.
  (write-line out
              (capture mut (lambda (outer)
                             (write-string outer "before:")
                             (let ((inner
                                    (capture mut (lambda (inner) (write inner (Some "inner"))))))
                               (write-string outer inner))
                             (write-char outer #\:)
                             (display outer "after"))))
  ;; A port made from another one writes through it.
  (write-line out
              (capture mut (lambda (outer)
                             (write (new OutputPort
                                      (write-string
                                       (lambda (text)
                                         (write-string outer (string-append "[" text "]")))))
                                    "forwarded"))))
  (line out (silent-eof))
  (unit))
