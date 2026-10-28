;; The book's highlighter, (snail shell highlight) as a program for
;; host/native/highlight-book.mjs, the preprocessor mdbook runs. The text of
;; a code block arrives a character at a time through `highlight_character`;
;; `highlight_html` classifies it and returns the length of its HTML, which
;; `highlight_result` gives back a character at a time. Each token but
;; whitespace becomes a span whose class, `tok-` and the class's name,
;; doc/highlight.css colors.
(import
 (snail core base)
 (snail shell highlight))

;; ---- Crossing ----

(: input (Ref (List Char)))
(define input (ref (Nil)))

(: result (Ref String))
(define result (ref ""))

(: highlight-character (-> I32 Unit ! mut))
(define (highlight-character code)
  (ref-set! input (Cons (i32->char code) (ref-get input))))

(: highlight-html (-> I32 ! mut))
(define (highlight-html)
  (let ((text (list->string (reverse (ref-get input)))))
    (ref-set! input (Nil))
    (ref-set! result (tokens-html (string->vector text) (highlight-tokens text)))
    (i64->i32 (string-length (ref-get result)))))

(: highlight-result (-> I32 I32 ! mut))
(define (highlight-result index)
  (char->i32 (string-ref (ref-get result) (i32->i64 index))))

(expose highlight-character "highlight_character")
(expose highlight-html "highlight_html")
(expose highlight-result "highlight_result")

;; ---- HTML ----

(: tokens-html (-> (Vector Char) (List Token) String))
(define (tokens-html chars tokens)
  (string-concatenate (map (lambda (token) (token-html chars token)) tokens)))

(: token-html (-> (Vector Char) Token String))
(define (token-html chars token)
  (let ((text (escape-html (subvector chars (Token-start token) (Token-end token)))))
    (match (Token-class token)
      ((Blank) text)
      (class (string-append "<span class=\"tok-" (class-name class) "\">" text "</span>")))))

;; Text as HTML shows it: `&`, `<` and `>` become character references.
(: escape-html (-> (Vector Char) String))
(define (escape-html chars)
  (string-concatenate
   (map (lambda (c)
          (cond ((char=? c #\&) "&amp;")
                ((char=? c #\<) "&lt;")
                ((char=? c #\>) "&gt;")
                (else (list->string (list c)))))
        (vector->list chars))))
