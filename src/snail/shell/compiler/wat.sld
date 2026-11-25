;; Folded instructions shared by representation selection and physical layout.
(define-library (snail shell compiler wat)
  (export Wat Word Node wat wat* int wat->string field->string wat->text
          wat-string hex-digit utf-8-bytes fill parse-wat)
  (import
   (snail core base))
  (begin
    ;; ---- Text ----

    ;; A WAT S-expression is a word, such as a keyword, identifier, number,
    ;; string literal or a preformatted helper, or a parenthesized node.
    (enum Wat
      (Word
       ((text String)))
      (Node
       ((items (List Wat)))))

    ;; `(wat "i32.add" a b)` is the node `(i32.add a b)`.
    (define-syntax wat
      (syntax-rules ()
        ((_ head item ...) (Node (list (Word head) item ...)))))

    ;; A node whose items after the head form a list.

    (define (wat* (head String) (items (List Wat))) (→ Wat)
      (Node (Cons (Word head) items)))

    (define (int (n I64)) (→ Wat)
      (Word (i64->string n)))

    ;; Top-level module fields and function instructions start new lines.

    (define (wat->string (module Wat)) (→ String)
      (match module
        ((Node (Cons _ fields))
         (string-concatenate
          (reverse (Cons ")\n"
                         (fold-left (lambda (pieces field) (write-field field (Cons "\n  " pieces)))
                                    (list "(module")
                                    fields)))))
        (_ (panic "internal error: not a module"))))

    (define (field->string (field Wat)) (→ String)
      (string-concatenate (reverse (write-field field (Nil)))))

    (define (write-field (field Wat) (pieces (List String))) (→ (List String))
      (match field
        ((Node (Cons (Word head) parts))
         (if (or (string=? head "func") (string=? head "rec"))
             (Cons ")"
                   (fold-left (lambda (pieces part)
                                (write-wat part
                                           (Cons (if (own-line? head part) "\n    " " ") pieces)))
                              (Cons head (Cons "(" pieces)) parts))
             (write-wat field pieces)))
        (_ (write-wat field pieces))))

    (define (own-line? (head String) (part Wat)) (→ Bool)
      (match part
        ((Node (Cons (Word inner) _))
         (or (string=? head "rec")
             (not (member? inner (list "type" "param" "result" "local" "export")))))
        (_ #f)))

    ;; Pieces accumulate in reverse.

    (define (write-wat (wat Wat) (pieces (List String))) (→ (List String))
      (match wat
        ((Word text) (Cons text pieces))
        ((Node (Nil)) (Cons "()" pieces))
        ((Node (Cons first rest))
         (Cons ")"
               (fold-left (lambda (pieces item) (write-wat item (Cons " " pieces)))
                          (write-wat first (Cons "(" pieces))
                          rest)))))

    ;; Wasm strings are UTF-8 bytes; anything beyond printable ASCII is escaped.

    (define (wat-string (text String)) (→ Wat)
      (Word (string-append "\"" (string-concatenate (map escape-char (string->list text))) "\"")))

    (define (escape-char (c Char)) (→ String)
      (let ((code (char->integer c)))
        (if (and (>= code 32) (< code 127) (not (= code 34)) (not (= code 92)))
            (list->string (list c))
            (string-concatenate (map (lambda (byte)
                                       (string-append "\\"
                                                      (hex-digit (quotient byte 16))
                                                      (hex-digit (remainder byte 16))))
                                     (utf-8-bytes code))))))

    (define (hex-digit (value I64)) (→ String)
      (substring "0123456789abcdef" value (+ value 1)))

    (define (utf-8-bytes (code I64)) (→ (List I64))
      (cond ((< code 128) (list code))
            ((< code 2048) (list (+ 192 (quotient code 64)) (+ 128 (remainder code 64))))
            ((< code 65536)
             (list (+ 224 (quotient code 4096))
                   (+ 128 (remainder (quotient code 64) 64))
                   (+ 128 (remainder code 64))))
            (else (list (+ 240 (quotient code 262144)) (+ 128 (remainder (quotient code 4096) 64))
                        (+ 128 (remainder (quotient code 64) 64)) (+ 128 (remainder code 64))))))

    ;; Fills each `{name}` in a template of fixed WAT text.

    (define (fill (template String) (bindings (List (Pair String String)))) (→ String)
      (let loop ((chars (string->list template)) (pieces (Nil)))
        (match chars
          ((Nil) (string-concatenate (reverse pieces)))
          ((Cons #\{ rest)
           (let ((name (list->string (take-until rest #\}))))
             (match (assoc-ref bindings name)
               ((Some value) (loop (list-drop rest (+ (string-length name) 1)) (Cons value pieces)))
               ((None) (loop rest (Cons "{" pieces))))))
          ((Cons c rest) (loop rest (Cons (list->string (list c)) pieces))))))

    (define (take-until (chars (List Char)) (stop Char)) (→ (List Char))
      (let loop ((chars chars) (taken (Nil)))
        (match chars
          ((Cons c rest) (if (char=? c stop) (reverse taken) (loop rest (Cons c taken))))
          ((Nil) (reverse taken)))))

    (define (wat->text (tree Wat)) (→ String)
      (string-concatenate (reverse (write-wat tree (Nil)))))

    ;; ---- Fixed helper templates ----

    ;; This reads the compiler's folded templates, not arbitrary user WAT.
    ;; Quotes retain their byte escapes verbatim. The Wasm assembler remains
    ;; responsible for validating the final instructions and their types.

    (define (parse-wat (source String)) (→ Wat)
      (let ((parsed (read-node source (skip-space source 0))))
        (unless (= (skip-space source (● parsed second)) (string-length source))
          (panic "internal error: trailing helper template text"))
        (● parsed first)))


    (define (skip-space (source String) (start I64)) (→ I64)
      (let loop ((index start))
        (if (and (< index (string-length source))
                 (<= (char->integer (string-ref source index)) 32))
            (loop (+ index 1)) index)))


    (define (read-node (source String) (start I64)) (→ (Pair Wat I64))
      (when (>= start (string-length source))
        (panic "internal error: unfinished helper template"))
      (if (char=? (string-ref source start) #\()
          (read-items source (+ start 1) (Nil))
          (let ((end (word-end source start)))
            (new Pair (first (Word (substring source start end))) (second end)))))


    (define (read-items (source String) (start I64) (items (List Wat))) (→ (Pair Wat I64))
      (let ((index (skip-space source start)))
        (when (>= index (string-length source))
          (panic "internal error: unclosed helper template"))
        (if (char=? (string-ref source index) #\))
            (new Pair (first (Node (reverse items))) (second (+ index 1)))
            (let ((parsed (read-node source index)))
              (read-items source (● parsed second) (Cons (● parsed first) items))))))


    (define (word-end (source String) (start I64)) (→ I64)
      (if (char=? (string-ref source start) #\")
          (quote-end source (+ start 1))
          (let loop ((index start))
            (if (or (= index (string-length source))
                    (<= (char->integer (string-ref source index)) 32)
                    (char=? (string-ref source index) #\()
                    (char=? (string-ref source index) #\)))
                index (loop (+ index 1))))))


    (define (quote-end (source String) (index I64)) (→ I64)
      (when (>= index (string-length source))
        (panic "internal error: unclosed helper template string"))
      (cond ((char=? (string-ref source index) #\") (+ index 1))
            ((char=? (string-ref source index) #\\) (quote-end source (+ index 2)))
            (else (quote-end source (+ index 1)))))
    ))
