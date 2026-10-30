;; The book's code highlighter, the mdbook preprocessor book.toml names,
;; which scripts/highlight-book runs on Node once stage 0 has built it.
;; mdbook asks `supports RENDERER` first, then writes [context, book] as
;; JSON to standard input and reads the book back from standard output.
;; Each fenced block whose language is `scheme` becomes the HTML that
;; (snail shell highlight) makes of it by the compiler's own lexical rules;
;; other blocks are left to highlight.js.
(import
 (snail core base)
 (snail core io)
 (snail shell highlight)
 (snail shell json)
 (snail shell json read))

;; ---- The book ----

;; The book's chapters, each with its content highlighted. Separators and
;; part titles have no content; a chapter's sub-items are chapters too.
(: highlight-book (-> Json Json))
(define (highlight-book input)
  (match input
    ((JsonArray (Cons _ (Cons book (Nil))))
     (with-members book
                   (lambda (name value)
                     (if (or (string=? name "items") (string=? name "sections"))
                         (map-items value)
                         value))))
    (_ (panic "the book's highlighter expected [context, book]"))))

(: map-items (-> Json Json))
(define (map-items items)
  (match items
    ((JsonArray list) (JsonArray (map highlight-item list)))
    (other other)))

(: highlight-item (-> Json Json))
(define (highlight-item item)
  (match (json-member item "Chapter")
    ((Some _)
     (with-members item
                   (lambda (name chapter)
                     (if (string=? name "Chapter") (highlight-chapter chapter) chapter))))
    ((None) item)))

(: highlight-chapter (-> Json Json))
(define (highlight-chapter chapter)
  (with-members chapter
                (lambda (name value)
                  (cond ((string=? name "content")
                         (match value
                           ((JsonString content) (JsonString (highlight-blocks content)))
                           (other other)))
                        ((string=? name "sub_items") (map-items value))
                        (else value)))))

;; An object with each member's value replaced by what `change` makes of
;; it, in order; anything else as it is.
(: with-members (-> Json (-> String Json Json) Json))
(define (with-members json change)
  (match json
    ((JsonObject members)
     (JsonObject (map (lambda (member)
                        (Pair (Pair-first member)
                              (change (Pair-first member) (Pair-second member))))
                      members)))
    (other other)))

;; ---- Fenced blocks ----

;; As CommonMark has it: a fence is three or more backticks or tildes, and
;; the first word of its info string names the language; a fence of the
;; same character, at least as long and with nothing after it, closes the
;; block, or else the chapter's end does; and as many spaces as the opening
;; fence's indentation are removed from each line. Containers are not
;; parsed, so a fence may be indented by any amount, as it is in a list
;; item. A `scheme` block becomes one line of HTML, its newlines written
;; `&#10;`, so it keeps its place in a list item. Its class, `nohighlight`,
;; is the one highlight.js leaves alone.
(struct Fence
  ((indent I64)
   (marker Char)
   (length I64)
   (info String)))

(: highlight-blocks (-> String String))
(define (highlight-blocks markdown)
  (string-join (reverse (blocks (lines-of markdown) (Nil))) "\n"))

;; The lines after `lines`, in reverse, onto `out`.
(: blocks (-> (List String) (List String) (List String)))
(define (blocks lines out)
  (match lines
    ((Nil) out)
    ((Cons line rest)
     (match (fence-of line)
       ((None) (blocks rest (Cons line out)))
       ((Some fence)
        (let* ((split (until-closing fence rest (Nil)))
               (body (Pair-first split))
               (after (Pair-second split)))
          (blocks (match after
                    ((Cons _ next) next)
                    ((Nil) (Nil)))
                  (if (string=? (language fence) "scheme")
                      (Cons (highlighted fence body) out)
                      (append (reverse (Cons line (append body (first-only after)))) out)))))))))

;; A block's lines before the fence that closes it, and the lines from that
;; fence on, none when the chapter ends first.
(: until-closing (-> Fence (List String) (List String) (Pair (List String) (List String))))
(define (until-closing fence lines body)
  (match lines
    ((Cons line rest)
     (if (closes? fence line)
         (Pair (reverse body) lines)
         (until-closing fence rest (Cons line body))))
    ((Nil) (Pair (reverse body) (Nil)))))

(: first-only (-> (List String) (List String)))
(define (first-only lines)
  (match lines
    ((Cons line _) (list line))
    ((Nil) (Nil))))

(: highlighted (-> Fence (List String) String))
(define (highlighted fence body)
  (let ((code (string-concatenate
               (map (lambda (line) (string-append (without-indent line (Fence-indent fence)) "\n"))
                    body))))
    (string-append (make-string (Fence-indent fence) #\space)
                   "<pre><code class=\"nohighlight\">"
                   (newlines-as-references (code-html code))
                   "</code></pre>")))

(: fence-of (-> String (Option Fence)))
(define (fence-of line)
  (let* ((indent (count-while line 0 (lambda (c) (char=? c #\space))))
         (marker (if (< indent (string-length line)) (string-ref line indent) #\space))
         (end (count-while line indent (lambda (c) (char=? c marker))))
         (info (substring line end (string-length line))))
    (if (and (or (char=? marker #\`) (char=? marker #\~))
             (>= (- end indent) 3)
             (not (and (char=? marker #\`) (contains-char? info #\`))))
        (Some (Fence indent marker (- end indent) info))
        (None))))

;; A line of spaces, then at least as many of the fence's character, then
;; only spaces and tabs.
(: closes? (-> Fence String Bool))
(define (closes? fence line)
  (let* ((indent (count-while line 0 (lambda (c) (char=? c #\space))))
         (end (count-while line indent (lambda (c) (char=? c (Fence-marker fence))))))
    (and (>= (- end indent) (Fence-length fence))
         (= (count-while line end (lambda (c) (or (char=? c #\space) (char=? c #\tab))))
            (string-length line)))))

;; The info string's first word, which ends at whitespace or a comma.
(: language (-> Fence String))
(define (language fence)
  (let* ((info (Fence-info fence))
         (start (count-while info 0 char-whitespace?))
         (end (count-while info start (lambda (c) (not (or (char-whitespace? c) (char=? c #\,)))))))
    (substring info start end)))

;; ---- Text ----

;; The index of the first character from `start` that `keep?` refuses, or
;; the text's length.
(: count-while (-> String I64 (-> Char Bool) I64))
(define (count-while text start keep?)
  (if (and (< start (string-length text)) (keep? (string-ref text start)))
      (count-while text (+ start 1) keep?)
      start))

(: contains-char? (-> String Char Bool))
(define (contains-char? text char)
  (match (string-index text char)
    ((Some _) #t)
    ((None) #f)))

(: without-indent (-> String I64 String))
(define (without-indent line indent)
  (let ((spaces (count-while line 0 (lambda (c) (char=? c #\space)))))
    (substring line (min spaces indent) (string-length line))))

(: lines-of (-> String (List String)))
(define (lines-of text)
  (match (string-index text #\newline)
    ((Some index)
     (Cons (substring text 0 index) (lines-of (substring text (+ index 1) (string-length text)))))
    ((None) (list text))))

(: newlines-as-references (-> String String))
(define (newlines-as-references text)
  (string-join (lines-of text) "&#10;"))

;; ---- HTML ----

;; Each token but whitespace becomes a span whose class, `tok-` and the
;; class's name, doc/highlight.css colors.
(: code-html (-> String String))
(define (code-html code)
  (let ((chars (string->vector code)))
    (string-concatenate (map (lambda (token) (token-html chars token)) (highlight-tokens code)))))

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

;; ---- The invocation ----

(: read-input (-> (List String) String ! console))
(define (read-input lines)
  (match (read-line)
    ((None) (string-join (reverse lines) "\n"))
    ((Some line) (read-input (Cons line lines)))))

(match (command-line)
  ((Cons _ (Cons "supports" (Cons renderer (Nil))))
   (unless (string=? renderer "html")
     (panic (string-append "the book's highlighter supports the html renderer, not " renderer))))
  ((Cons _ (Nil))
   (match (string->json (read-input (Nil)))
     ((Some input) (write-string (json->string (highlight-book input))))
     ((None) (panic "the book's highlighter expected JSON on its standard input"))))
  (_ (panic "usage: highlight-book [supports RENDERER]")))
