;; (snail shell format) on the command line, which is how the tests hold
;; the formatter to the repository's Emacs formatting (tests/run.scm):
;;
;;   format-check [--width COLUMNS] --check FILE ...
;;
;; prints the first line that formatting would change in each file. Lines
;; break past `format-width` columns, or past COLUMNS when given.
(import
 (snail core base)
 (snail core io)
 (snail shell format))

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
