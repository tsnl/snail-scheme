;; The backend's folded WAT vocabulary. Fixed helper templates are parsed into
;; the same tree before physical lowering; a raw string cannot bypass rooting.
(define-library (snail shell compiler wat)
  (export
   Wat Word Node wat wat* int wat->string field->string wat->text
   wat-string escape-char hex-digit utf-8-bytes utf-8-length fill parse-wat backend-sort)
  (import
   (snail core base))
  (begin
    ;; ---- Deterministic declaration order ----

    ;; A compiler module has thousands of declarations. Merge iteratively so
    ;; its native call depth depends on log(count), never on the list length.
    ;; Taking the left element on ties preserves the source's stable order.
    (: backend-sort
       (All (T Callback)
            (requires (Copy T) (Copy Callback) (Fn Callback T T -> Bool))
            (impl (Fn Callback (List T) -> (List T)))))
    (define (backend-sort before? items)
      (let ((half (quotient (length items) 2)))
        (if (= half 0) items
            (merge-declarations before?
                                (backend-sort before? (take items half))
                                (backend-sort before? (list-drop items half)) (Nil)))))

    (: merge-declarations
       (All (T Callback)
            (requires (Copy T) (Copy Callback) (Fn Callback T T -> Bool))
            (impl (Fn Callback (List T) (List T) (List T) -> (List T)))))
    (define (merge-declarations before? left right taken)
      (match (Pair left right)
        ((Pair (Nil) _) (fold-left (lambda (rest item) (Cons item rest)) right taken))
        ((Pair _ (Nil)) (fold-left (lambda (rest item) (Cons item rest)) left taken))
        ((Pair (Cons a rest-a) (Cons b rest-b))
         (if (before? b a)
             (merge-declarations before? left rest-b (Cons b taken))
             (merge-declarations before? rest-a right (Cons a taken))))))

    ;; ---- Folded instructions and text ----

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
    (: wat* (impl (Fn String (List Wat) -> Wat)))
    (define (wat* head items)
      (Node (Cons (Word head) items)))

    (: int (impl (Fn I64 -> Wat)))
    (define (int n)
      (Word (i64->string n)))

    ;; Top-level module fields and function instructions start new lines.
    (: wat->string (impl (Fn Wat -> String)))
    (define (wat->string module)
      (match module
        ((Node (Cons _ fields))
         (string-concatenate
          (reverse (Cons ")\n"
                         (fold-left (lambda (pieces field)
                                      (Cons (field->string field) (Cons "\n  " pieces)))
                                    (list "(module")
                                    fields)))))
        (_ (panic "internal error: not a module"))))

    (: field->string (impl (Fn Wat -> String)))
    (define (field->string field)
      (match field
        ((Word text) text)
        (_ (string-concatenate (reverse (write-field field (Nil)))))))

    (: write-field (impl (Fn Wat (List String) -> (List String))))
    (define (write-field field pieces)
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

    (: own-line? (impl (Fn String Wat -> Bool)))
    (define (own-line? head part)
      (match part
        ((Node (Cons (Word inner) _))
         (or (string=? head "rec")
             (not (member? inner (list "type" "param" "result" "local" "export")))))
        (_ #f)))

    ;; Pieces accumulate in reverse.
    (: write-wat (impl (Fn Wat (List String) -> (List String))))
    (define (write-wat wat pieces)
      (match wat
        ((Word text) (Cons text pieces))
        ((Node (Nil)) (Cons "()" pieces))
        ((Node (Cons first rest))
         (Cons ")"
               (fold-left (lambda (pieces item) (write-wat item (Cons " " pieces)))
                          (write-wat first (Cons "(" pieces))
                          rest)))))

    ;; Wasm strings are UTF-8 bytes; anything beyond printable ASCII is escaped.
    (: wat-string (impl (Fn String -> Wat)))
    (define (wat-string text)
      (Word (string-append "\"" (string-concatenate (quoted-pieces text)) "\"")))

    ;; Type keys are mostly ASCII. Keep entire unchanged spans instead of
    ;; allocating one string and one list cell for every printable character.
    (: quoted-pieces (impl (Fn String -> (List String))))
    (define (quoted-pieces text)
      (let ((limit (string-length text)))
        (let loop ((start 0) (index 0) (pieces (Nil)))
          (cond ((= index limit) (reverse (Cons (substring text start index) pieces)))
                ((plain-character? (string-ref text index)) (loop start (+ index 1) pieces))
                (else (loop (+ index 1) (+ index 1)
                            (Cons (escape-char (string-ref text index))
                                  (Cons (substring text start index) pieces))))))))

    (: plain-character? (impl (Fn Char -> Bool)))
    (define (plain-character? c)
      (let ((code (char->integer c)))
        (and (>= code 32) (< code 127) (not (= code 34)) (not (= code 92)))))

    (: escape-char (impl (Fn Char -> String)))
    (define (escape-char c)
      (let ((code (char->integer c)))
        (if (plain-character? c)
            (list->string (list c))
            (string-concatenate (map (lambda (byte)
                                       (string-append "\\"
                                                      (hex-digit (quotient byte 16))
                                                      (hex-digit (remainder byte 16))))
                                     (utf-8-bytes code))))))

    (: hex-digit (impl (Fn I64 -> String)))
    (define (hex-digit value)
      (substring "0123456789abcdef" value (+ value 1)))

    ;; Layout-key lengths need no intermediate character or byte lists.
    (: utf-8-length (impl (Fn String -> I64)))
    (define (utf-8-length text)
      (let ((limit (string-length text)))
        (let loop ((index 0) (bytes 0))
          (if (= index limit) bytes
              (let ((code (char->integer (string-ref text index))))
                (loop (+ index 1)
                      (+ bytes (cond ((< code 128) 1) ((< code 2048) 2)
                                     ((< code 65536) 3) (else 4)))))))))

    (: utf-8-bytes (impl (Fn I64 -> (List I64))))
    (define (utf-8-bytes code)
      (cond ((< code 128) (list code))
            ((< code 2048) (list (+ 192 (quotient code 64)) (+ 128 (remainder code 64))))
            ((< code 65536)
             (list (+ 224 (quotient code 4096))
                   (+ 128 (remainder (quotient code 64) 64))
                   (+ 128 (remainder code 64))))
            (else (list (+ 240 (quotient code 262144)) (+ 128 (remainder (quotient code 4096) 64))
                        (+ 128 (remainder (quotient code 64) 64)) (+ 128 (remainder code 64))))))

    ;; Fills each `{name}` in a template of fixed WAT text.
    (: fill (impl (Fn String (List (Pair String String)) -> String)))
    (define (fill template bindings)
      (let loop ((chars (string->list template)) (pieces (Nil)))
        (match chars
          ((Nil) (string-concatenate (reverse pieces)))
          ((Cons #\{ rest)
           (let ((name (list->string (take-until rest #\}))))
             (match (assoc-ref bindings name)
               ((Some value) (loop (list-drop rest (+ (string-length name) 1)) (Cons value pieces)))
               ((None) (loop rest (Cons "{" pieces))))))
          ((Cons c rest) (loop rest (Cons (list->string (list c)) pieces))))))

    (: take-until (impl (Fn (List Char) Char -> (List Char))))
    (define (take-until chars stop)
      (let loop ((chars chars) (taken (Nil)))
        (match chars
          ((Cons c rest) (if (char=? c stop) (reverse taken) (loop rest (Cons c taken))))
          ((Nil) (reverse taken)))))


    (: wat->text (impl (Fn Wat -> String)))
    (define (wat->text tree)
      (string-concatenate (reverse (write-wat tree (Nil)))))

    ;; ---- Fixed helper templates ----

    ;; This reads the compiler's folded templates, not arbitrary user WAT.
    ;; Quotes retain their byte escapes verbatim. The Wasm assembler remains
    ;; responsible for validating the final instructions and their types.
    (: parse-wat (impl (Fn String -> Wat)))
    (define (parse-wat source)
      (let ((parsed (read-node source (skip-space source 0))))
        (unless (= (skip-space source (::second parsed)) (string-length source))
          (panic "internal error: trailing helper template text"))
        (::first parsed)))

    (: skip-space (impl (Fn String I64 -> I64)))
    (define (skip-space source start)
      (let loop ((index start))
        (if (and (< index (string-length source))
                 (<= (char->integer (string-ref source index)) 32))
            (loop (+ index 1)) index)))

    (: read-node (impl (Fn String I64 -> (Pair Wat I64))))
    (define (read-node source start)
      (when (>= start (string-length source))
        (panic "internal error: unfinished helper template"))
      (if (char=? (string-ref source start) #\()
          (read-items source (+ start 1) (Nil))
          (let ((end (word-end source start)))
            (Pair (Word (substring source start end)) end))))

    (: read-items (impl (Fn String I64 (List Wat) -> (Pair Wat I64))))
    (define (read-items source start items)
      (let ((index (skip-space source start)))
        (when (>= index (string-length source))
          (panic "internal error: unclosed helper template"))
        (if (char=? (string-ref source index) #\))
            (Pair (Node (reverse items)) (+ index 1))
            (let ((parsed (read-node source index)))
              (read-items source (::second parsed) (Cons (::first parsed) items))))))

    (: word-end (impl (Fn String I64 -> I64)))
    (define (word-end source start)
      (if (char=? (string-ref source start) #\")
          (quote-end source (+ start 1))
          (let loop ((index start))
            (if (or (= index (string-length source))
                    (<= (char->integer (string-ref source index)) 32)
                    (char=? (string-ref source index) #\()
                    (char=? (string-ref source index) #\)))
                index (loop (+ index 1))))))

    (: quote-end (impl (Fn String I64 -> I64)))
    (define (quote-end source index)
      (when (>= index (string-length source))
        (panic "internal error: unclosed helper template string"))
      (cond ((char=? (string-ref source index) #\") (+ index 1))
            ((char=? (string-ref source index) #\\) (quote-end source (+ index 2)))
            (else (quote-end source (+ index 1)))))
    ))
