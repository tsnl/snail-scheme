;; The IDE's formatter, (snail shell format) as a program, with the
;; classifier the book is colored by, (snail shell highlight). In a page, the
;; source arrives a character at a time through `format_character`;
;; `format_whole` formats it, `format_indent` reindents some of its lines and
;; `format_highlight` classes each character for coloring, and each returns
;; the length of the result, which `format_result` gives back a character at
;; a time. On the command line,
;;
;;   format [--width COLUMNS] --check FILE ...
;;
;; prints the first line that formatting would change in each file, which is
;; how the tests hold the formatter to the repository's Emacs formatting.
;; Lines break past `format-width` columns, or past COLUMNS when given.
(import
 (snail core base)
 (snail core io)
 (snail shell format)
 (snail shell highlight))

;; ---- In a page ----

(: input (Ref (List Char)))
(define input (ref (Nil)))

(: result (Ref String))
(define result (ref ""))

(: format-character (-> I32 Unit ! mut))
(define (format-character code)
  (ref-set! input (Cons (i32->char code) (ref-get input))))

(: take-input (-> String ! mut))
(define (take-input)
  (let ((text (list->string (reverse (ref-get input)))))
    (ref-set! input (Nil))
    text))

(: keep-result (-> String I32 ! mut))
(define (keep-result text)
  (ref-set! result text)
  (i64->i32 (string-length text)))

(: format-whole (-> I32 ! mut))
(define (format-whole)
  (keep-result (format-source (take-input) format-width)))

;; Lines `first` to `last`, counting from 0.
(: format-indent (-> I32 I32 I32 ! mut))
(define (format-indent first last)
  (keep-result (indent-lines (take-input) (i32->i64 first) (i32->i64 last))))

(: format-highlight (-> I32 ! mut))
(define (format-highlight)
  (keep-result (class-letters (highlight-tokens (take-input)))))

;; One letter per character, naming its token's class for the editor's
;; `hl-` styles in host/ide/ide.css. Whitespace and plain names are `.`.
(: class-letters (-> (List Token) String))
(define (class-letters tokens)
  (string-concatenate
   (map (lambda (token)
          (make-string (- (Token-end token) (Token-start token))
                       (class-letter (Token-class token))))
        tokens)))

(: class-letter (-> Class Char))
(define (class-letter class)
  (match class
    ((Blank) #\.)
    ((Comment) #\c)
    ((Punctuation) #\p)
    ((StringLiteral) #\s)
    ((CharacterLiteral) #\h)
    ((NumberLiteral) #\n)
    ((BooleanLiteral) #\b)
    ((Keyword) #\k)
    ((TypeName) #\t)
    ((DefinedName) #\d)
    ((Identifier) #\.)
    ((Invalid) #\e)))

(: format-result (-> I32 I32 ! mut))
(define (format-result index)
  (char->i32 (string-ref (ref-get result) (i32->i64 index))))

(expose format-character "format_character")
(expose format-whole "format_whole")
(expose format-indent "format_indent")
(expose format-highlight "format_highlight")
(expose format-result "format_result")

;; ---- On the command line ----

(: check-file (-> I64 String Unit ! fs console))
(define (check-file width path)
  (let ((text (read-file path)))
    (match (first-difference (lines-of text)
                             (lines-of (format-source text width))
                             1)
      ((Some report) (write-line (string-append path ":" report)))
      ((None) (unit)))))

(: lines-of (-> String (List String)))
(define (lines-of text)
  (let loop ((chars (string->list text)) (line (Nil)) (out (Nil)))
    (match chars
      ((Cons #\newline rest) (loop rest (Nil) (Cons (list->string (reverse line)) out)))
      ((Cons c rest) (loop rest (Cons c line) out))
      ((Nil) (reverse (Cons (list->string (reverse line)) out))))))

;; The number of the first line that differs, with both versions of it.
(: first-difference (-> (List String) (List String) I64 (Option String)))
(define (first-difference before after number)
  (match (Pair before after)
    ((Pair (Nil) (Nil)) (None))
    ((Pair (Cons a more) (Cons b rest))
     (if (string=? a b)
         (first-difference more rest (+ number 1))
         (Some (string-append (i64->string number) ": needs formatting\n  was: " a "\n  now: " b))))
    (_ (Some (string-append (i64->string number) ": needs formatting: the line count changes")))))

(: check-files (-> I64 (List String) Unit ! fs console))
(define (check-files width paths)
  (for-each (lambda (path) (check-file width path)) paths))

(match (command-line)
  ((Cons _ (Cons "--width" (Cons columns (Cons "--check" paths))))
   (match (string->i64 columns)
     ((Some width) (check-files width paths))
     ((None) (write-line "format: --width takes a number of columns"))))
  ((Cons _ (Cons "--check" paths)) (check-files format-width paths))
  (_ (unit)))
