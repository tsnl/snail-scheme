;; Source text to classified tokens, for coloring code. The reader decides
;; where every token starts and ends: this library walks the text with the
;; lexical rules of (snail shell compiler read) and its classification of
;; tokens, and adds only what a reader discards, the comments and whitespace
;; between data. Text the reader would reject still classifies: a string the
;; text ends inside is a string to the end. Every character belongs to one
;; token, so the tokens tile the text. The book's preprocessor
;; (bootstrap/highlight-book.sld) and the IDE (host/ide/ide.sld) both color
;; with these tokens.
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
   Token-start
   Token-end
   Token-class
   highlight-tokens)
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
    (: class-name (-> Class String))
    (define (class-name class)
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
    (: keywords (List String))
    (define keywords
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
                    "ctl" "All" "requires" "deriving" "host" "->" "!"
                    "define-application" "define-record-type" "guard")))

    ;; A definition names what follows `(define`, `(define-syntax` or `(:`.
    (: defining-forms (List String))
    (define defining-forms
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
    ;; `(define (twice x) ...)`. A quote mark and atmosphere leave this as it
    ;; is; any other lexeme ends it.
    (enum Naming
      (Plain)
      (Opened)
      (Defining))

    ;; ---- Classifying ----

    ;; The tokens of `text`, in order.
    (: highlight-tokens (-> String (List Token)))
    (define (highlight-tokens text)
      (let ((source (make-source "" text)))
        (let loop ((index 0) (naming (Plain)) (tokens (Nil)))
          (match (next-token source index naming)
            ((Some (Pair token next)) (loop (Token-end token) next (Cons token tokens)))
            ((None) (reverse tokens))))))

    ;; The token at `index` and the naming after it, or nothing at the end of
    ;; the text. Atmosphere comes first, as it does for the reader, and what
    ;; `#;` comments out is one comment with it.
    (: next-token (-> Source I64 Naming (Option (Pair Token Naming))))
    (define (next-token source index naming)
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
              (Some (Pair (Token index end (Pair-first classified)) (Pair-second classified)))))))))

    (: atmosphere-class (-> Atmosphere Class))
    (define (atmosphere-class atmosphere)
      (match atmosphere
        ((Whitespace) (Blank))
        (_ (Comment))))

    ;; A lexeme's class, and the naming after it.
    (: lexeme-class (-> Source I64 I64 Lexeme Naming (Pair Class Naming)))
    (define (lexeme-class source start end lexeme naming)
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

    (: token-class (-> String Naming (Pair Class Naming)))
    (define (token-class text naming)
      (match (token-kind text)
        ((BooleanToken _) (Pair (BooleanLiteral) (Plain)))
        ((IntegerToken) (Pair (NumberLiteral) (Plain)))
        ((FloatToken) (Pair (NumberLiteral) (Plain)))
        ((InvalidToken _) (Pair (Invalid) (Plain)))
        ((NameToken) (name-class text naming))))

    (: name-class (-> String Naming (Pair Class Naming)))
    (define (name-class name naming)
      (match naming
        ((Defining) (Pair (DefinedName) (Plain)))
        ((Opened)
         (if (member? name defining-forms)
             (Pair (Keyword) (Defining))
             (Pair (plain-name-class name) (Plain))))
        ((Plain) (Pair (plain-name-class name) (Plain)))))

    ;; A type's name starts with a capital letter.
    (: plain-name-class (-> String Class))
    (define (plain-name-class name)
      (let ((first (string-ref name 0)))
        (cond ((member? name keywords) (Keyword))
              ((and (not (char<? first #\A)) (not (char<? #\Z first))) (TypeName))
              (else (Identifier)))))

    ;; ---- Datum comments ----

    ;; The index after the datum that `#;` comments out, found as the reader
    ;; finds it to skip it: a list or byte vector runs to its closing
    ;; bracket, a quote mark goes on to the datum it quotes, and anything
    ;; else is one lexeme. Text the reader rejects still ends somewhere: a
    ;; closing bracket with no datum before it ends the comment, and so does
    ;; the end of the text.
    (: datum-end (-> Source I64 I64))
    (define (datum-end source index)
      (let* ((start (atmosphere-end source index))
             (lexeme (lexeme-at source start))
             (end (Pair-second lexeme)))
        (match (Pair-first lexeme)
          ((EndOfText) start)
          ((ListClose _) start)
          ((QuoteMark) (datum-end source end))
          ((ListOpen _) (items-end source end))
          ((BytesOpen) (items-end source end))
          (_ end))))

    ;; The index after the closing bracket of a list whose items start at
    ;; `index`.
    (: items-end (-> Source I64 I64))
    (define (items-end source index)
      (let* ((start (atmosphere-end source index)) (lexeme (lexeme-at source start)))
        (match (Pair-first lexeme)
          ((EndOfText) start)
          ((ListClose _) (Pair-second lexeme))
          (_ (items-end source (datum-end source start))))))

    ;; Skips atmosphere as the reader does, with the data `#;` comments out.
    (: atmosphere-end (-> Source I64 I64))
    (define (atmosphere-end source index)
      (match (atmosphere-at source index)
        ((Some (Pair (DatumComment) end)) (atmosphere-end source (datum-end source end)))
        ((Some (Pair _ end)) (atmosphere-end source end))
        ((None) index)))

    ))
