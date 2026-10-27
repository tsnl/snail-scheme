;; The IDE's formatter, (snail-core format) as a program. In a page, the source
;; arrives a character at a time through `format_character`; `format_whole`
;; formats it, `format_indent` reindents some of its lines and
;; `format_highlight` classes each character for coloring, and each returns
;; the length of the result, which `format_result` gives back a character at
;; a time. On the command line,
;;
;;   format --check FILE ...
;;
;; prints the first line that formatting would change in each file, which is
;; how the tests hold the formatter to the repository's Emacs formatting.
(import
 (snail-core base)
 (snail-core io)
 (snail-core format))

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
  (keep-result (format-source (take-input))))

;; Lines `first` to `last`, counting from 0.
(: format-indent (-> I32 I32 I32 ! mut))
(define (format-indent first last)
  (keep-result (indent-lines (take-input) (i32->i64 first) (i32->i64 last))))

(: format-highlight (-> I32 ! mut))
(define (format-highlight)
  (keep-result (highlight-classes (take-input))))

(: format-result (-> I32 I32 ! mut))
(define (format-result index)
  (char->i32 (string-ref (ref-get result) (i32->i64 index))))

(expose format-character "format_character")
(expose format-whole "format_whole")
(expose format-indent "format_indent")
(expose format-highlight "format_highlight")
(expose format-result "format_result")

;; ---- On the command line ----

(: check-file (-> String Unit ! fs console))
(define (check-file path)
  (let ((text (read-file path)))
    (match (first-difference (lines-of text) (lines-of (format-source text)) 1)
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

(match (command-line)
  ((Cons _ (Cons "--check" paths)) (for-each check-file paths))
  (_ (unit)))
