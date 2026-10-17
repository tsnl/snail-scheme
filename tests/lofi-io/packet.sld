;; Character, line and datum readers share one owned-file cursor.
(import
 (lofi base)
 (lofi io)
 (lofi datum)
 (lofi read))

;; ---- Peek and read through alternating aliases ----

(def code (-> CharacterResult I64)
     (lambda (result)
       (match result ((character-end) (ann -1 I64))
              ((character-value value) (char->integer value)))))

(def copy-aliases (-> InputPort InputPort OutputPort I64 I64)
     (lambda (left right output count)
       (begin
         (let first (code (peek-char left)))
         (if (= first (code (peek-char right)))
             (match (read-char left)
               ((character-end) (if (= first (ann -1 I64)) count (unreachable)))
               ((character-value character)
                (if (= first (char->integer character))
                    (begin
                      (write-char character output)
                      (copy-aliases right left output (+ count (ann 1 I64))))
                    (unreachable))))
             (unreachable)))))

(def copy-characters (-> I64)
     (lambda ()
       (call-with-input-file "input.txt"
         (lambda (input)
           (call-with-output-file "output.txt"
             (lambda (output) (copy-aliases input input output (ann 0 I64))))))))

;; ---- Interleave character, CRLF line and datum reads ----

(def mixed-readers (-> Bool)
     (lambda ()
       (call-with-input-file "input.txt"
         (lambda (port)
           (begin
             (let alias port)
             (if (= (code (peek-char port)) (ann 65 I64))
                 (if (= (code (read-char alias)) (ann 65 I64))
                     (if (string=? (line-text (read-line port)) "λline")
                         (mixed-tail alias port) #f)
                     #f)
                 #f))))))

(def mixed-tail (-> InputPort InputPort Bool)
     (lambda (left right)
       (match (datum-number-value (read-value! (read left)))
         ((exact-number number)
          (if (= number (ann 42 I64))
              (if (string=? (line-text (read-line right)) " end")
                  (if (= (code (read-char left)) (ann 90 I64)) (mixed-eof left right) #f)
                  #f)
              #f))
         ((rational-number number) #f) ((inexact-number number) #f)
         ((complex-number real imaginary) #f))))

(def mixed-eof (-> InputPort InputPort Bool)
     (lambda (left right)
       (if (character-end? (peek-char left))
           (if (character-end? (peek-char right))
               (if (character-end? (read-char left))
                   (if (character-end? (read-char right)) (eof-object? (read-line left)) #f)
                   #f)
               #f)
           #f)))

;; ---- Close invalidates pending input; stdin shares the scalar foreign cursor ----

(def cached-close (-> Unit)
     (lambda ()
       (begin
         (let port (open-input-file "input.txt"))
         (let alias port)
         (peek-char port)
         (close-input-port alias)
         (close-input-port port)
         (read-char port)
         (unit))))

(define-extern raw-read "snail.library" "snail:io/read-character" (-> I32 I32))
(define-extern raw-peek "snail.library" "snail:io/peek-character" (-> I32 I32))

(def copy-standard (-> I64)
     (lambda ()
       (begin
         (let input (current-input-port))
         (let first (code (peek-char input)))
         (close-input-port input)
         (close-input-port (current-input-port))
         (if (= first (i32->i64 (raw-peek (ann -3 I32))))
             (if (= first (i32->i64 (raw-read (ann -3 I32))))
                 (call-with-output-file "output.txt"
                   (lambda (output) (copy-standard-tail input output first)))
                 (unreachable))
             (unreachable)))))

(def copy-standard-tail (-> InputPort OutputPort I64 I64)
     (lambda (input output first)
       (if (= first (ann -1 I64))
           (copy-aliases input (current-input-port) output (ann 0 I64))
           (begin
             (write-char (integer->char first) output)
             (copy-aliases input (current-input-port) output (ann 1 I64))))))

;; ---- Consuming cached EOF permits a later read to observe file growth ----

(def growing (ref (current-input-port)))
(def open-growing (-> Unit)
     (lambda () (ref-set! growing (open-input-file "input.txt"))))
(def peek-growing (-> I64)
     (lambda () (code (peek-char (ref-get growing)))))
(def read-growing (-> I64)
     (lambda () (code (read-char (ref-get growing)))))
(def close-growing (-> Unit)
     (lambda () (close-input-port (ref-get growing))))

(unit)
