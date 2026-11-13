;; Small, pure terminal layouts. Cards have an open right edge: long
;; messages, tabs and wide Unicode characters need no guessed display width.
(define-library (snail shell console)
  (export
   console-card)
  (import
   (snail core base))
  (begin

    ;; ---- Cards ----

    (define (console-card (heading String) (body String)) (→ String)
      (string-append "╭─ "
                     (card-lines heading)
                     "\n│\n│  "
                     (card-lines body)
                     "\n╰─"))

    ;; Every embedded newline stays inside the card, including empty lines.
    (define (card-lines (text String)) (→ String)
      (match (string-index text #\newline)
        ((Some index)
         (string-append (substring text 0 index)
                        "\n│  "
                        (card-lines (substring text (+ index 1) (string-length text)))))
        ((None) text)))

    ))
