;; Source text to classified tokens, for coloring code. The reader decides
;; where every token starts and ends: this library walks the text with the
;; lexical rules of (snail shell compiler read) and its classification of
;; tokens, and adds only what a reader discards, the comments and whitespace
;; between data. Text the reader would reject still classifies: a string the
;; text ends inside is a string to the end. Every character belongs to one
;; token, so the tokens tile the text. The book's preprocessor
;; (bootstrap/highlight-book.sld) and the IDE (host/ide/ide.sld) both color
;; with these tokens. The IDE also derives display ranges for compiler
;; points with the same lexical boundaries.
(define-library (snail shell highlight)
  (export
   Class
   Blank
   Comment
   Punctuation
   StringLiteral
   CharacterLiteral
   NumberLiteral
   BooleanLiteral
   Keyword
   TypeName
   DefinedName
   Identifier
   Invalid
   class-name
   Token
   highlight-tokens
   highlight-range)
  (import
   (snail core base)
   (only (snail shell compiler read)
         Source
         make-source
         source-text
         Whitespace
         LineComment
         BlockComment
         DatumComment
         atmosphere-at
         Atmosphere
         Lexeme
         ListOpen
         ListClose
         QuoteMark
         BytesOpen
         StringLexeme
         CharacterLexeme
         TokenLexeme
         EndOfText
         lexeme-at
         BooleanToken
         IntegerToken
         FloatToken
         NameToken
         InvalidToken
         token-kind)
   (only (snail shell compiler core) core-keywords))
  (begin

    ;; ---- Classes ----

    ;; Punctuation is a list's brackets, a quote mark, and the `#u8(` that
    ;; opens a byte vector. A defined name is the name a definition
    ;; introduces. An invalid token is one the reader rejects outright: `.`
    ;; or an unknown `#` syntax. Inside a literal, the classifier checks no
    ;; more than the lexeme does: escapes, character names and the range of
    ;; an integer are the reader's to check.
    (enum Class
      (Blank)
      (Comment)
      (Punctuation)
      (StringLiteral)
      (CharacterLiteral)
      (NumberLiteral)
      (BooleanLiteral)
      (Keyword)
      (TypeName)
      (DefinedName)
      (Identifier)
      (Invalid))

    ;; The name a page styles a class by.
    (define (class-name (class Class)) (→ String)
      (match class
        ((Blank) "whitespace")
        ((Comment) "comment")
        ((Punctuation) "punctuation")
        ((StringLiteral) "string")
        ((CharacterLiteral) "character")
        ((NumberLiteral) "number")
        ((BooleanLiteral) "boolean")
        ((Keyword) "keyword")
        ((TypeName) "type")
        ((DefinedName) "definition")
        ((Identifier) "identifier")
        ((Invalid) "invalid")))

    ;; ---- Keywords ----

    ;; The core forms are the compiler's own list. The rest are listed here,
    ;; once: (snail core base)'s derived syntax, then the words the expander
    ;; matches by name in libraries, effects and signatures, then forms of
    ;; libraries that ship with the language.
    (define keywords (→ (List String))
      (append core-keywords
              (list "let*" "letrec" "cond" "case" "when" "unless" "and" "or" "do" "else"
                    "define-library"
                    "import"
                    "export"
                    "only"
                    "except"
                    "prefix"
                    "rename"
                    "cond-expand"
                    "ctl" "∀" "⊨" "deriving" "host" "→" "!"
                    "define-page-state" "define-record-type" "guard")))

    ;; A definition names what follows `(define`, `(define-syntax` or `(:`.
    (define defining-forms (→ (List String))
      (list "define" "define-syntax" ":"))

    ;; ---- Tokens ----

    ;; A token covers the characters from `start` up to `end`.
    (struct Token
      ((start I64)
       (end I64)
       (class Class)))

    ;; What the next name means: after an opening bracket, `define`,
    ;; `define-syntax` or `:` starts a definition, and then the next name is
    ;; the one it defines, also when a list comes first, as in
    ;; `(define twice (lambda (x) ...))`. A quote mark and atmosphere leave this as it
    ;; is; any other lexeme ends it.
    (enum Naming
      (Plain)
      (Opened)
      (Defining))

    ;; ---- Classifying ----

    ;; The tokens of `text`, in order.
    (define (highlight-tokens (text String)) (→ (List Token))
      (let ((source (make-source "" text)))
        (let loop ((index 0) (naming (Plain)) (tokens (Nil)))
          (match (next-token source index naming)
            ((Some (Pair token next)) (loop (● token end) next (Cons token tokens)))
            ((None) (reverse tokens))))))

    ;; The token at `index` and the naming after it, or nothing at the end of
    ;; the text. Atmosphere comes first, as it does for the reader, and what
    ;; `#;` comments out is one comment with it.
    (define (next-token (source Source) (index I64) (naming Naming))
      (→ (Option (Pair Token Naming)))
      (match (atmosphere-at source index)
        ((Some (Pair (DatumComment) end))
         (Some (Pair (Token index (datum-end source end) (Comment)) naming)))
        ((Some (Pair atmosphere end))
         (Some (Pair (Token index end (atmosphere-class atmosphere)) naming)))
        ((None)
         (match (lexeme-at source index)
           ((Pair (EndOfText) _) (None))
           ((Pair lexeme end)
            (let ((classified (lexeme-class source index end lexeme naming)))
              (Some (Pair (Token index end (● classified first)) (● classified second)))))))))

    (define (atmosphere-class (atmosphere Atmosphere)) (→ Class)
      (match atmosphere
        ((Whitespace) (Blank))
        (_ (Comment))))

    ;; A lexeme's class, and the naming after it.
    (define (lexeme-class (source Source) (start I64) (end I64) (lexeme Lexeme) (naming Naming))
      (→ (Pair Class Naming))
      (match lexeme
        ((ListOpen _) (Pair (Punctuation) (match naming ((Defining) (Defining)) (_ (Opened)))))
        ((ListClose _) (Pair (Punctuation) (Plain)))
        ((QuoteMark) (Pair (Punctuation) naming))
        ((BytesOpen) (Pair (Punctuation) (Plain)))
        ((StringLexeme _) (Pair (StringLiteral) (Plain)))
        ((CharacterLexeme) (Pair (CharacterLiteral) (Plain)))
        ((TokenLexeme) (token-class (source-text source start end) naming))
        ;; `next-token` stops at the end of the text.
        ((EndOfText) (Pair (Blank) naming))))

    (define (token-class (text String) (naming Naming)) (→ (Pair Class Naming))
      (match (token-kind text)
        ((BooleanToken _) (Pair (BooleanLiteral) (Plain)))
        ((IntegerToken) (Pair (NumberLiteral) (Plain)))
        ((FloatToken) (Pair (NumberLiteral) (Plain)))
        ((InvalidToken _) (Pair (Invalid) (Plain)))
        ((NameToken) (name-class text naming))))

    (define (name-class (name String) (naming Naming)) (→ (Pair Class Naming))
      (match naming
        ((Defining) (Pair (DefinedName) (Plain)))
        ((Opened)
         (if (member? name defining-forms)
             (Pair (Keyword) (Defining))
             (Pair (plain-name-class name) (Plain))))
        ((Plain) (Pair (plain-name-class name) (Plain)))))

    ;; A type's name starts with a capital letter.
    (define (plain-name-class (name String)) (→ Class)
      (let ((first (string-ref name 0)))
        (cond ((member? name keywords) (Keyword))
              ((and (not (char<? first #\A)) (not (char<? #\Z first))) (TypeName))
              (else (Identifier)))))

    ;; ---- Display ranges ----

    ;; A compiler point has no end. For display, mark its containing token;
    ;; an opening bracket or quote extends through its datum. These scalar
    ;; offsets are a half-open lexical range, not a compiler source span.
    ;; Whitespace keeps one cell, and EOF has an empty range for the view to
    ;; mark without borrowing the preceding token.
    (define (highlight-range (text String) (offset I64)) (→ (Pair I64 I64))
      (let ((source (make-source "" text)) (point (min (string-length text) (max 0 offset))))
        (let loop ((index 0))
          (match (next-token source index (Plain))
            ((None) (Pair point point))
            ((Some (Pair token _))
             (if (<= (● token end) point)
                 (loop (● token end))
                 (token-range source token point)))))))

    (define (token-range (source Source) (token Token) (point I64)) (→ (Pair I64 I64))
      (match (● token class)
        ((Blank) (Pair point (+ point 1)))
        ((Punctuation)
         (Pair (● token start)
               (max (● token end) (datum-end source (● token start)))))
        (_ (Pair (● token start) (● token end)))))

    ;; ---- Datum boundaries ----

    ;; The index after the datum that `#;` comments out, found as the reader
    ;; finds it to skip it: a list or byte vector runs to its closing
    ;; bracket, a quote mark goes on to the datum it quotes, and anything
    ;; else is one lexeme. Text the reader rejects still ends somewhere: a
    ;; closing bracket with no datum before it ends the comment, and so does
    ;; the end of the text.
    (define (datum-end (source Source) (index I64)) (→ I64)
      (let* ((start (atmosphere-end source index))
             (lexeme (lexeme-at source start))
             (end (● lexeme second)))
        (match (● lexeme first)
          ((EndOfText) start)
          ((ListClose _) start)
          ((QuoteMark) (datum-end source end))
          ((ListOpen _) (items-end source end))
          ((BytesOpen) (items-end source end))
          (_ end))))

    ;; The index after the closing bracket of a list whose items start at
    ;; `index`.
    (define (items-end (source Source) (index I64)) (→ I64)
      (let* ((start (atmosphere-end source index)) (lexeme (lexeme-at source start)))
        (match (● lexeme first)
          ((EndOfText) start)
          ((ListClose _) (● lexeme second))
          (_ (items-end source (datum-end source start))))))

    ;; Skips atmosphere as the reader does, with the data `#;` comments out.
    (define (atmosphere-end (source Source) (index I64)) (→ I64)
      (match (atmosphere-at source index)
        ((Some (Pair (DatumComment) end)) (atmosphere-end source (datum-end source end)))
        ((Some (Pair _ end)) (atmosphere-end source end))
        ((None) index)))

    ))
