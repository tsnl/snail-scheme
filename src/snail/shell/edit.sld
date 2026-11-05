;; Structural editing of incomplete Scheme. Reader-backed highlighting
;; keeps delimiters in comments and literals out of the matching stack.
;; These are pure edits in Unicode scalar offsets; the field applies each
;; replacement as one undoable operation and owns its selection afterward.
(define-library (snail shell edit)
  (export
   Change
   Change-start
   Change-end
   Change-text
   Change-selection-start
   Change-selection-end
   Delimiters
   Delimiters-start
   Delimiters-open
   Delimiters-close
   delimiter-pairs
   matching-pair
   enclosing-pair
   delimiter-change)
  (import
   (snail core base)
   (snail shell highlight)
   (only (snail shell compiler read)
         make-source
         atmosphere-at
         LineComment
         BlockComment
         DatumComment
         lexeme-at
         StringLexeme))
  (begin

    ;; ---- Edits and pairs ----

    ;; An empty replacement of an empty range only moves the selection.
    (struct Change
      ((start I64)
       (end I64)
       (text String)
       (selection-start I64)
       (selection-end I64)))

    ;; `start` includes a reader prefix such as #u8; `open` and `close`
    ;; locate the delimiter characters themselves.
    (struct Delimiters
      ((start I64)
       (open I64)
       (close I64)))

    (: opening? (-> Char Bool))
    (define (opening? char)
      (or (char=? char #\() (char=? char #\[)))

    (: closing (-> Char Char))
    (define (closing char)
      (if (char=? char #\[) #\] #\)))

    ;; A mismatched closer clears the stack: no recovered pair crosses
    ;; that error. Complete pairs before it and new forms after it survive.
    (: delimiter-pairs (-> String (List Delimiters)))
    (define (delimiter-pairs text)
      (pairs-in text (highlight-tokens text)))

    (: pairs-in (-> String (List Token) (List Delimiters)))
    (define (pairs-in text tokens)
      (let loop ((tokens tokens) (stack (Nil)) (pairs (Nil)))
        (match tokens
          ((Nil) pairs)
          ((Cons token rest)
           (match (Token-class token)
             ((Punctuation)
              (let* ((at (- (Token-end token) 1)) (char (string-ref text at)))
                (cond ((opening? char) (loop rest (Cons token stack) pairs))
                      ((or (char=? char #\)) (char=? char #\]))
                       (match stack
                         ((Cons open outer)
                          (let ((before (- (Token-end open) 1)))
                            (if (char=? char (closing (string-ref text before)))
                                (loop rest outer
                                      (Cons (Delimiters (Token-start open) before at) pairs))
                                (loop rest (Nil) pairs))))
                         ((Nil) (loop rest (Nil) pairs))))
                      (else (loop rest stack pairs)))))
             (_ (loop rest stack pairs)))))))

    ;; Prefer the delimiter at the caret to the one immediately before it.
    (: matching-pair (-> (List Delimiters) I64 (Option Delimiters)))
    (define (matching-pair pairs caret)
      (match (pair-at pairs caret)
        ((Some found) (Some found))
        ((None) (pair-at pairs (- caret 1)))))

    (: pair-at (-> (List Delimiters) I64 (Option Delimiters)))
    (define (pair-at pairs at)
      (find (lambda (pair)
              (or (= at (Delimiters-open pair)) (= at (Delimiters-close pair))))
            pairs))

    ;; The smallest delimited range strictly containing the selection.
    ;; Repeating this operation selects successive enclosing lists.
    (: enclosing-pair (-> (List Delimiters) I64 I64 (Option Delimiters)))
    (define (enclosing-pair pairs from to)
      (fold-left (lambda (best pair)
                   (let ((start (Delimiters-start pair)) (end (+ (Delimiters-close pair) 1)))
                     (if (and (<= start from) (<= to end)
                              (or (< start from) (< to end))
                              (match best
                                ((Some outer) (> start (Delimiters-start outer)))
                                ((None) #t)))
                         (Some pair)
                         best)))
                 (None)
                 pairs))

    ;; ---- Literal boundaries ----

    (: protected-token? (-> Token Bool))
    (define (protected-token? token)
      (match (Token-class token)
        ((StringLiteral) #t)
        ((CharacterLiteral) #t)
        ((Comment) #t)
        (_ #f)))

    ;; At a token's end, a complete string/block comment has ended, but a
    ;; line comment or unfinished literal still owns the insertion. At the
    ;; end of a datum comment be conservative until whitespace separates it.
    (: extends-token? (-> String Token Bool))
    (define (extends-token? text token)
      (let ((source (make-source "" text)) (start (Token-start token)))
        (match (Token-class token)
          ((StringLiteral)
           (match (Pair-first (lexeme-at source start))
             ((StringLexeme closed) (not closed))
             (_ #f)))
          ((CharacterLiteral) (= (- (Token-end token) start) 2))
          ((Comment)
           (match (atmosphere-at source start)
             ((Some (Pair (LineComment) _)) #t)
             ((Some (Pair (BlockComment closed) _)) (not closed))
             ((Some (Pair (DatumComment) _)) #t)
             (_ #f)))
          (_ #f))))

    (: literal-insertion? (-> String (List Token) I64 Bool))
    (define (literal-insertion? text tokens at)
      (any? (lambda (token)
              (and (protected-token? token) (< (Token-start token) at)
                   (or (< at (Token-end token))
                       (and (= at (Token-end token)) (extends-token? text token)))))
            tokens))

    ;; ---- Typing and deletion ----

    (: replacement (-> I64 I64 String Change))
    (define (replacement from to text)
      (let ((caret (+ from (string-length text))))
        (Change from to text caret caret)))

    (: selection (-> I64 I64 Change))
    (define (selection from to)
      (Change from from "" from to))

    ;; Keys are the field's explicit editing chords. Other shortcuts and
    ;; composition input stay with the browser. Plain deletion removes one
    ;; scalar, as delete-char does, without splitting UTF-16 surrogate pairs.
    (: delimiter-change (-> String String I64 I64 Change))
    (define (delimiter-change text key from to)
      (let ((tokens (highlight-tokens text)))
        (cond ((or (string=? key "(") (string=? key "["))
               (opening-change text tokens key from to))
              ((or (string=? key ")") (string=? key "]"))
               (closing-change text tokens key from to))
              ((or (string=? key "Backspace") (string=? key "Delete"))
               (deleting-change text (pairs-in text tokens) key from to))
              ((string=? key "ArrowUp")
               (match (enclosing-pair (pairs-in text tokens) from to)
                 ((Some pair) (selection (Delimiters-start pair) (+ (Delimiters-close pair) 1)))
                 ((None) (selection from to))))
              (else (matching-change (pairs-in text tokens) from to)))))

    (: opening-change (-> String (List Token) String I64 I64 Change))
    (define (opening-change text tokens key from to)
      (if (or (literal-insertion? text tokens from) (literal-insertion? text tokens to))
          (replacement from to key)
          (Change from to
                  (string-append key (substring text from to)
                                 (make-string 1 (closing (string-ref key 0))))
                  (+ from 1) (+ to 1))))

    (: closing-change (-> String (List Token) String I64 I64 Change))
    (define (closing-change text tokens key from to)
      (if (and (= from to) (< to (string-length text))
               (char=? (string-ref text to) (string-ref key 0))
               (any? (lambda (token)
                       (and (= (Token-start token) to)
                            (match (Token-class token) ((Punctuation) #t) (_ #f))))
                     tokens))
          (selection (+ to 1) (+ to 1))
          (replacement from to key)))

    (: deleting-change (-> String (List Delimiters) String I64 I64 Change))
    (define (deleting-change text pairs key from to)
      (let* ((backward (string=? key "Backspace"))
             (at (if backward (- from 1) from)))
        (if (< from to)
            (replacement from to "")
            (match (pair-at pairs at)
              ((Some pair)
               (if (and (= (Delimiters-start pair) (Delimiters-open pair))
                        (= (+ (Delimiters-open pair) 1) (Delimiters-close pair)))
                   (replacement (Delimiters-open pair) (+ (Delimiters-close pair) 1) "")
                   (single-deletion text backward from)))
              ((None) (single-deletion text backward from))))))

    (: single-deletion (-> String Bool I64 Change))
    (define (single-deletion text backward at)
      (replacement (if backward (max 0 (- at 1)) at)
                   (if backward at (min (string-length text) (+ at 1)))
                   ""))

    (: matching-change (-> (List Delimiters) I64 I64 Change))
    (define (matching-change pairs from to)
      (match (matching-pair pairs from)
        ((Some pair)
         (let* ((open (Delimiters-open pair)) (close (Delimiters-close pair))
                (at (if (or (= from close) (= from (+ close 1))) open close)))
           (selection at at)))
        ((None) (selection from to))))))
