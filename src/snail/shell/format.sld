;; The repository's Lisp formatter, shared by scripts/format-scheme and the
;; IDE. Formatting is a pure operation on text, including unfinished source.
;; Formatting first puts each import specification, struct field and record
;; field on its own line, then indents every line. A line's indentation goes
;; under the first argument of a call, under the first expression of the
;; line its list's last element starts on, or in by two columns for the body
;; of a special form, as the
;; rule for the form's name says. A line whose code runs past the width,
;; `format-width` unless the caller says otherwise, is broken before the
;; next is indented: a call before its arguments, a binding form before
;; each binding and body form. Nothing ever joins lines. The IDE
;; (host/ide/ide.sld) formats on save and indents a line when Tab is
;; pressed; it colors the text with (snail shell highlight), which follows
;; the compiler's reader.
(define-library (snail shell format)
  (export
   format-source
   format-width
   indent-lines)
  (import
   (snail core base))
  (begin

    ;; ---- Tokens ----

    ;; What indentation needs to know of a line: where each list opens and
    ;; closes and where each other expression starts, by offset in the line.
    ;; A string is one token where it starts; comments are dropped. An open
    ;; parenthesis notes whether a space follows it.
    (enum Token
      (Open ((offset I64) (spaced Bool)))
      (Close ((offset I64)))
      (Prefix ((offset I64)))
      (Atom ((offset I64) (text String)))
      (Text ((offset I64))))

    ;; Lines starting inside quoted text or a comment keep their indentation.
    ;; A datum comment owns its own lexer mode and list depth, so nested #;
    ;; comments do not consume the datum the outer comment is waiting for.
    (enum Mode
      (Code)
      (InQuoted ((delimiter Char)))
      (InComment ((depth I64)))
      (InDatum ((depth I64) (mode Mode))))

    ;; A line, the mode it starts in, its tokens, and the offset just past
    ;; its last token, where its code ends before any comment.
    (struct Line
      ((text String)
       (mode Mode)
       (tokens (List Token))
       (end I64)))

    ;; ---- Lexing ----

    (define (lex (text String)) (→ (List Line))
      (let loop ((lines (split-lines text)) (mode (Code)) (out (Nil)))
        (match lines
          ((Cons line rest)
           (match (lex-line line mode)
             ((Pair lexed next) (loop rest next (Cons lexed out)))))
          ((Nil) (reverse out)))))

    ;; A final newline leaves a final empty line.

    (define (split-lines (text String)) (→ (List String))
      (let loop ((index (- (string-length text) 1)) (end (string-length text)) (out (Nil)))
        (cond ((< index 0) (Cons (substring text 0 end) out))
              ((= (string-ref text index) #\newline)
               (loop (- index 1) index (Cons (substring text (+ index 1) end) out)))
              (else (loop (- index 1) end out)))))

    ;; One step of lexing: the offset after what it read, the mode after
    ;; it, and the token it made, if any.
    (struct Step
      ((next I64)
       (mode Mode)
       (token (Option Token))))

    ;; A line that starts in `mode`, and the mode the next line starts in.

    (define (lex-line (line String) (mode Mode)) (→ (Pair Line Mode))
      (let loop ((offset 0) (state mode) (tokens (Nil)) (end 0))
        (if (>= offset (string-length line))
            (Pair (Line line mode (reverse tokens) end) state)
            (let ((step (lex-step line offset state)))
              (match (● step token)
                ((Some token)
                 (loop (● step next)
                       (● step mode)
                       (Cons token tokens)
                       (● step next)))
                ((None)
                 (loop (● step next) (● step mode) tokens end)))))))

    (define (lex-step (line String) (offset I64) (mode Mode)) (→ Step)
      (match mode
        ((Code) (lex-code line offset))
        ((InQuoted delimiter) (lex-quoted line offset delimiter))
        ((InComment depth) (lex-comment line offset depth))
        ((InDatum depth mode) (lex-datum line offset depth mode))))

    (define (lex-code (line String) (offset I64)) (→ Step)
      (let ((c (string-ref line offset)) (after (+ offset 1)))
        (cond ((char-whitespace? c) (Step after (Code) (None)))
              ((= c #\;) (Step (string-length line) (Code) (None)))
              ((or (= c #\() (= c #\[)) (code-token after (Open offset (spaced? line after))))
              ((or (= c #\)) (= c #\])) (code-token after (Close offset)))
              ((or (= c #\") (= c #\|))
               (Step-token-set (lex-quoted line after c) (Some (Text offset))))
              ((or (= c #\') (= c #\`)) (code-token after (Prefix offset)))
              ((= c #\,) (code-token (if (at? line after "@") (+ after 1) after) (Prefix offset)))
              ((= c #\#) (lex-hash line offset))
              (else (lex-atom line offset offset)))))

    (define (code-token (next I64) (token Token)) (→ Step)
      (Step next (Code) (Some token)))

    ;; `#(` opens a vector, `#|` a block comment, and `#;` comments out the
    ;; next datum; `#\` starts a character,
    ;; whatever character follows it.

    (define (lex-hash (line String) (offset I64)) (→ Step)
      (let ((after (+ offset 1)))
        (cond ((at? line after "(") (code-token after (Prefix offset)))
              ((at? line after "u8(") (code-token (+ after 2) (Prefix offset)))
              ((at? line after "|") (lex-comment line (+ after 1) 1))
              ((at? line after ";") (Step (+ after 1) (InDatum 0 (Code)) (None)))
              ((at? line after "\\") (lex-atom line offset (min (+ after 2) (string-length line))))
              (else (lex-atom line offset after)))))

    (define (lex-atom (line String) (start I64) (from I64)) (→ Step)
      (let ((end (atom-end line from)))
        (code-token end (Atom start (substring line start end)))))

    (define (atom-end (line String) (offset I64)) (→ I64)
      (if (or (>= offset (string-length line)) (delimiter? (string-ref line offset)))
          offset
          (atom-end line (+ offset 1))))

    (define (delimiter? (c Char)) (→ Bool)
      (or (char-whitespace? c) (member? c (list #\( #\) #\[ #\] #\" #\| #\; #\' #\` #\,))))

    ;; Strings and |quoted identifiers| preserve their contents, including
    ;; escapes and newlines. Only their opening delimiter makes a token.

    (define (lex-quoted (line String) (offset I64) (delimiter Char)) (→ Step)
      (cond ((>= offset (string-length line)) (Step offset (InQuoted delimiter) (None)))
            ((= (string-ref line offset) #\\)
             (lex-quoted line (min (+ offset 2) (string-length line)) delimiter))
            ((= (string-ref line offset) delimiter) (Step (+ offset 1) (Code) (None)))
            (else (lex-quoted line (+ offset 1) delimiter))))

    ;; Discard one datum's tokens. Depth zero waits for its expression; -1
    ;; waits only for quoted text to close. Positive depths count open lists.
    ;; Prefixes wait for their datum, while nested comments stay in `mode`.

    (define (lex-datum (line String) (offset I64) (depth I64) (mode Mode)) (→ Step)
      (let* ((step (lex-step line offset mode))
             (next-depth (match (● step token)
                           ((Some (Open _ _)) (+ depth 1))
                           ((Some (Close _)) (- depth 1))
                           ((Some (Prefix _)) depth)
                           ((Some _) (if (= depth 0) -1 depth))
                           ((None) depth)))
             (closed (match (● step token) ((Some (Close _)) (<= depth 1)) (_ #f))))
        (Step (● step next)
              (if (or closed (and (< next-depth 0) (code-mode? (● step mode))))
                  (Code)
                  (InDatum next-depth (● step mode)))
              (None))))

    ;; Inside a block comment, which nests.

    (define (lex-comment (line String) (offset I64) (depth I64)) (→ Step)
      (cond ((>= offset (string-length line)) (Step offset (InComment depth) (None)))
            ((at? line offset "|#")
             (if (= depth 1)
                 (Step (+ offset 2) (Code) (None))
                 (lex-comment line (+ offset 2) (- depth 1))))
            ((at? line offset "#|") (lex-comment line (+ offset 2) (+ depth 1)))
            (else (lex-comment line (+ offset 1) depth))))

    (define (spaced? (line String) (offset I64)) (→ Bool)
      (and (< offset (string-length line)) (member? (string-ref line offset) (list #\space #\tab))))

    (define (at? (line String) (offset I64) (text String)) (→ Bool)
      (and (<= (+ offset (string-length text)) (string-length line))
           (string=? (substring line offset (+ offset (string-length text))) text)))

    ;; ---- Open lists ----

    ;; What an element of a list is, which matters for its first element:
    ;; a name selects an indentation rule.
    (enum Head
      (Named ((name String)))
      (Listed)
      (Other))

    ;; Where an element starts, and the column of the first expression on
    ;; that line, which may lie in another list.
    (struct Element
      ((head Head)
       (column I64)
       (line I64)
       (first I64)))

    ;; What indentation uses from an open list's elements, so a frame holds
    ;; a bounded record rather than every element. `count` and `first` cover
    ;; the arguments, excluding the head; `last` is the head until an
    ;; argument appears.
    (struct Elements
      ((head Element)
       (first (Option Element))
       (last Element)
       (count I64)))

    ;; An open list: its parenthesis, whether a space follows it, and what
    ;; its elements so far contribute. At the start of a line, every element
    ;; of the innermost open list is complete.
    (struct Frame
      ((column I64)
       (line I64)
       (spaced Bool)
       (elements (Option Elements))))

    ;; ---- Indentation rules ----

    ;; A call's arguments line up; a definition's body goes in by two
    ;; columns; a special form's first `distinguished` arguments go in by
    ;; four and its body by two. `let` has two distinguished arguments when
    ;; it names a loop.
    (enum Rule
      (Call)
      (Definition)
      (Special ((distinguished I64)))
      (LetRule))

    ;; Conventional Scheme indentation and Snail Scheme's forms. Binding names
    ;; follow the let/-let and let*/-let* convention below, without a table entry.

    (define (known-rule (name String)) (→ (Option Rule))
      (case name
        (("begin"
          "delay"
          "make-environment"
          "match-lambda"
          "match-lambda*"
          "sequence"
          "with-output-to-string")
         (Some (Special 0)))
        (("access-components"
          "assignment-components"
          "call-with-input-file"
          "call-with-output-file"
          "call-with-port"
          "call-with-values"
          "case"
          "combination-components"
          "comment-components"
          "conditional-components"
          "declaration-components"
          "define-library"
          "define-record-type"
          "define-values"
          "definition-components"
          "delay-components"
          "disjunction-components"
          "element"
          "eval-when"
          "in-package"
          "in-package-components"
          "lambda"
          "lambda-components"
          "lambda-components*"
          "lambda-components**"
          "letrec"
          "letrec*"
          "letrec-syntax"
          "let-syntax"
          "let*-values"
          "let-values"
          "library"
          "list-search-negative"
          "list-search-positive"
          "list-transform-negative"
          "list-transform-positive"
          "local-declare"
          "macro"
          "make"
          "match-letrec"
          "mode"
          "named-lambda"
          "open-block-components"
          "parameterize"
          "pathname-components"
          "procedure-components"
          "root"
          "sequence-components"
          "style"
          "unassigned?-components"
          "unbound?-components"
          "unless"
          "using-syntax"
          "variable-components"
          "when"
          "with-input-from-file"
          "with-input-from-port"
          "with-input-from-string"
          "with-mode"
          "with-output-to-file"
          "with-output-to-port"
          "with-syntax"
          "with-values"
          "λ")
         (Some (Special 1)))
        (("do" "receive" "syntax-case" "syntax-table-define") (Some (Special 2)))
        (("dynamic-wind") (Some (Special 3)))
        (("scheme-define" "declare") (Some (Definition)))
        (("syntax-rules") (Some (Definition)))
        (("struct" "enum" "typeclass" "instance" "effect" "match" "guard") (Some (Special 1)))
        (("handle") (Some (Special 2)))
        (else (None))))

    ;; A binding macro advertises its layout in its name. A name without a
    ;; rule that starts with `def` (case insensitive) is a definition.

    (define (indent-rule (name String)) (→ Rule)
      (cond ((binding-name? name "let") (LetRule))
            ((binding-name? name "let*") (Special 1))
            (else
             (match (known-rule name)
               ((Some rule) rule)
               ((None)
                (if (and (> (string-length name) 3) (def-prefix? name)) (Definition) (Call)))))))

    (define (binding-name? (name String) (base String)) (→ Bool)
      (let* ((suffix (string-append "-" base))
             (start (- (string-length name) (string-length suffix))))
        (or (string=? name base)
            (and (>= start 0) (string=? (substring name start (string-length name)) suffix)))))

    (define (def-prefix? (name String)) (→ Bool)
      (every? (lambda (pair) (member? (string-ref name (● pair first)) (● pair second)))
              (list (Pair 0 (list #\d #\D)) (Pair 1 (list #\e #\E)) (Pair 2 (list #\f #\F)))))

    ;; ---- Indentation ----

    ;; The column of a line that starts inside `frame`: just inside the
    ;; parenthesis when nothing follows it yet, else as the head's rule says.

    (define (frame-indent (frame Frame)) (→ I64)
      (match (● frame elements)
        ((Some elements)
         (match (● (● elements head) head)
           ((Named name) (named-indent frame elements name (normal-indent frame elements)))
           (_ (unnamed-indent (● elements head) (● elements last)))))
        ((None) (+ (● frame column) 1))))

    ;; On the head's line, align under the first argument, or the head when
    ;; there is no argument or a space follows the parenthesis. Later align
    ;; under the first expression on the last element's line.

    (define (normal-indent (frame Frame) (elements Elements)) (→ I64)
      (let ((head (● elements head)) (last (● elements last)))
        (cond ((not (= (● last line) (● head line))) (● last first))
              ((● frame spaced) (● head column))
              (else (match (● elements first)
                      ((Some argument) (● argument column))
                      ((None) (● head column)))))))

    ;; A list whose head is not a name lines up with its head while its
    ;; elements share the head's line.

    (define (unnamed-indent (head Element) (last Element)) (→ I64)
      (if (= (● last line) (● head line)) (● head column) (● last first)))

    (define (named-indent (frame Frame) (elements Elements) (name String) (normal I64)) (→ I64)
      (match (indent-rule name)
        ((Call) normal)
        ((Definition)
         (if (= (● (● elements last) line) (● frame line))
             (+ (● frame column) 2)
             normal))
        ((Special distinguished)
         (special-indent frame distinguished (● elements count) normal))
        ((LetRule)
         (special-indent frame (if (names-loop? elements) 2 1) (● elements count) normal))))

    ;; A distinguished argument goes in by four columns when it is one of
    ;; the first two; the first body form goes
    ;; in by two, unless the line above sits further left.

    (define (special-indent (frame Frame) (distinguished I64) (arguments I64) (normal I64)) (→ I64)
      (let ((left (- distinguished arguments)) (body (+ (● frame column) 2)))
        (cond ((> left 0) (if (<= arguments 1) (+ (● frame column) 4) normal))
              ((or (and (= distinguished 0) (= arguments 0)) (and (= left 0) (<= body normal)))
               body)
              (else normal))))

    ;; A named `let`: a name follows `let` on its line.

    (define (names-loop? (elements Elements)) (→ Bool)
      (match elements
        ((Elements head (Some (Element (Named name) _ line _)) _ _)
         (and (= line (● head line)) (member? (string-ref name 0) (loop-name-starts))))
        (_ #f)))

    (define (loop-name-starts) (→ (List Char))
      (string->list "-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+*/?!@$%^&_:~"))

    ;; ---- Indenting lines ----

    ;; Reindents lines `first` to `last`, counting from 0, and keeps the
    ;; others as they are. Lines are indented in order, each from the lists
    ;; open where it starts, as the lines above it now stand.

    (define (indent-lines (text String) (first I64) (last I64)) (→ String)
      (let loop ((lines (lex text)) (index 0) (frames (Nil)) (out (Nil)))
        (match lines
          ((Cons line rest)
           (match (if (and (<= first index) (<= index last))
                      (reindent line frames)
                      (Pair (● line text) 0))
             ((Pair indented shift)
              (loop rest
                    (+ index 1)
                    (scan-line frames (● line tokens) shift index)
                    (Cons indented out)))))
          ((Nil) (string-join (reverse out) "\n")))))

    ;; A line's new text, and how far its tokens moved. A blank line
    ;; becomes empty; a line inside a string or block comment, or one that
    ;; starts with three semicolons, stays as it is.

    (define (reindent (line Line) (frames (List Frame))) (→ (Pair String I64))
      (let* ((text (● line text))
             (start (indentation text))
             (rest (substring text start (string-length text))))
        (cond ((not (code-mode? (● line mode))) (Pair text 0))
              ((string=? rest "") (Pair "" 0))
              ((at? rest 0 ";;;") (Pair text 0))
              (else (let ((column (stack-indent frames)))
                      (Pair (string-append (make-string column #\space) rest) (- column start)))))))

    (define (indentation (text String)) (→ I64)
      (let loop ((index 0))
        (if
         (and (< index (string-length text)) (member? (string-ref text index) (list #\space #\tab)))
         (loop (+ index 1))
         index)))

    (define (code-mode? (mode Mode)) (→ Bool)
      (match mode
        ((Code) #t)
        (_ #f)))

    (define (stack-indent (frames (List Frame))) (→ I64)
      (match frames
        ((Cons frame _) (frame-indent frame))
        ((Nil) 0)))

    ;; ---- Scanning lines ----

    ;; The open lists while a line is scanned, the column of its first
    ;; expression, and the column of a prefix waiting for its expression.
    (struct Scan
      ((frames (List Frame))
       (first (Option I64))
       (prefix (Option I64))))

    ;; The lists open after a line, whose tokens sit `shift` columns from
    ;; their offsets.

    (define (scan-line (frames (List Frame)) (tokens (List Token)) (shift I64) (line I64))
      (→ (List Frame))
      (● (fold-left (lambda (scan token) (scan-token scan token shift line))
                    (Scan frames (None) (None))
                    tokens) frames))

    (define (scan-token (scan Scan) (token Token) (shift I64) (line I64)) (→ Scan)
      (match token
        ((Open offset spaced)
         (let ((added (add-expression scan (Listed) (+ offset shift) line)))
           (Scan-frames-set added
                            (Cons (Frame (+ offset shift) line spaced (None))
                                  (● added frames)))))
        ((Close _) (Scan-frames-set scan (list-drop (● scan frames) 1)))
        ((Prefix offset)
         (Scan (● scan frames) (Some (or-else (● scan first) (+ offset shift)))
               (Some (or-else (● scan prefix) (+ offset shift)))))
        ((Atom offset text) (add-expression scan (atom-head text) (+ offset shift) line))
        ((Text offset) (add-expression scan (Other) (+ offset shift) line))))

    ;; A character is not a name.

    (define (atom-head (text String)) (→ Head)
      (if (at? text 0 "#\\") (Other) (Named text)))

    ;; An expression starts at `column`, or at the prefix before it, as an
    ;; element of the innermost list.

    (define (add-expression (scan Scan) (head Head) (column I64) (line I64)) (→ Scan)
      (let* ((start (or-else (● scan prefix) column)) (first (or-else (● scan first) start)))
        (Scan (add-element (● scan frames) (Element head start line first))
              (Some first)
              (None))))

    (define (add-element (frames (List Frame)) (element Element)) (→ (List Frame))
      (match frames
        ((Cons frame rest)
         (Cons (Frame-elements-set frame (Some (extend (● frame elements) element))) rest))
        ((Nil) (Nil))))

    ;; The first element is the head; each later one is the latest argument,
    ;; and the earliest of those is remembered.

    (define (extend (elements (Option Elements)) (element Element)) (→ Elements)
      (match elements
        ((None) (Elements element (None) element 0))
        ((Some (Elements head first _ count))
         (Elements head (match first ((None) (Some element)) (_ first)) element (+ count 1)))))

    (define (or-else (value (Option I64)) (default I64)) (→ I64)
      (match value
        ((Some found) found)
        ((None) default)))

    ;; ---- Declarations ----

    ;; A token with its line and that line's leading whitespace. A token
    ;; after a comment is not at the start of its line, even if no earlier
    ;; token was emitted on that line.
    (struct Placed
      ((line I64)
       (token Token)
       (indent I64)))

    (define (placed-tokens (lines (List Line))) (→ (Vector Placed))
      (list->vector (concatenate (map-indexed (lambda (index line)
                                                (let ((indent (indentation (● line text))))
                                                  (map (lambda (token) (Placed index token indent))
                                                       (● line tokens))))
                                              lines))))

    (define (token-offset (token Token)) (→ I64)
      (match token
        ((Open offset _) offset)
        ((Close offset) offset)
        ((Prefix offset) offset)
        ((Atom offset _) offset)
        ((Text offset) offset)))

    ;; The index after the expression that starts at token `index`, if one
    ;; starts there and ends.

    (define (expression-end (tokens (Vector Placed)) (index I64)) (→ (Option I64))
      (if (>= index (vector-length tokens))
          (None)
          (match (● (vector-ref tokens index) token)
            ((Prefix _) (expression-end tokens (+ index 1)))
            ((Open _ _) (list-end tokens (+ index 1) 1))
            ((Close _) (None))
            (_ (Some (+ index 1))))))

    (define (list-end (tokens (Vector Placed)) (index I64) (depth I64)) (→ (Option I64))
      (cond ((= depth 0) (Some index))
            ((>= index (vector-length tokens)) (None))
            (else (match (● (vector-ref tokens index) token)
                    ((Open _ _) (list-end tokens (+ index 1) (+ depth 1)))
                    ((Close _) (list-end tokens (+ index 1) (- depth 1)))
                    (_ (list-end tokens (+ index 1) depth))))))

    (define (skip-expressions (tokens (Vector Placed)) (index I64) (count I64)) (→ (Option I64))
      (if (= count 0)
          (Some index)
          (match (expression-end tokens index)
            ((Some next) (skip-expressions tokens next (- count 1)))
            ((None) (None)))))

    (define (open-at? (tokens (Vector Placed)) (index I64)) (→ Bool)
      (and (< index (vector-length tokens))
           (match (● (vector-ref tokens index) token)
             ((Open _ _) #t)
             (_ #f))))

    ;; The name right after the parenthesis at token `index`.

    (define (form-name (tokens (Vector Placed)) (index I64)) (→ (Option String))
      (if (and (open-at? tokens index) (< (+ index 1) (vector-length tokens)))
          (match (Pair (vector-ref tokens index) (vector-ref tokens (+ index 1)))
            ((Pair (Placed line (Open offset _) _) (Placed next-line (Atom next-offset name) _))
             (if (and (= line next-line) (= next-offset (+ offset 1))) (Some name) (None)))
            (_ (None)))
          (None)))

    ;; Breaks found so far, and whether the expressions they lie in ended.
    (struct Found
      ((breaks (List Placed))
       (ended Bool)))

    ;; Each list from token `index` on starts its own line, up to the first
    ;; element that is not a list.

    (define (break-entries (tokens (Vector Placed)) (index I64) (breaks (List Placed))) (→ Found)
      (if (open-at? tokens index)
          (let ((breaks (break-before tokens index breaks)))
            (match (expression-end tokens index)
              ((Some next) (break-entries tokens next breaks))
              ((None) (Found breaks #f))))
          (Found breaks #t)))

    (define (break-before (tokens (Vector Placed)) (index I64) (breaks (List Placed)))
      (→ (List Placed))
      (let ((placed (vector-ref tokens index)))
        (if (<= (token-offset (● placed token)) (● placed indent))
            breaks
            (Cons placed breaks))))

    ;; A struct's field list starts its own line, and so does each field
    ;; after the first.

    (define (break-struct (tokens (Vector Placed)) (index I64) (breaks (List Placed)))
      (→ (List Placed))
      (match (skip-expressions tokens (+ index 1) 2)
        ((Some fields)
         (if (open-at? tokens fields)
             (break-fields tokens (+ fields 1) (break-before tokens fields breaks))
             breaks))
        ((None) breaks)))

    (define (break-fields (tokens (Vector Placed)) (index I64) (breaks (List Placed)))
      (→ (List Placed))
      (if (open-at? tokens index)
          (match (expression-end tokens index)
            ((Some next) (● (break-entries tokens next breaks) breaks))
            ((None) breaks))
          breaks))

    (define (break-record (tokens (Vector Placed)) (index I64) (breaks (List Placed)))
      (→ (List Placed))
      (match (skip-expressions tokens (+ index 1) 4)
        ((Some fields) (● (break-entries tokens fields breaks) breaks))
        ((None) breaks)))

    ;; Declaration breaks, in order: before each import
    ;; specification, a struct's field list and its fields after the first,
    ;; and a record type's fields. An import that does not end stops the
    ;; search, since everything after it is part of it.

    (define (declaration-breaks (tokens (Vector Placed))) (→ (List Placed))
      (let loop ((index 0) (breaks (Nil)))
        (if (>= index (vector-length tokens))
            (reverse breaks)
            (match (form-name tokens index)
              ((Some "import")
               (match (break-entries tokens (+ index 2) breaks)
                 ((Found found #t)
                  (loop (or-else (expression-end tokens index) (vector-length tokens)) found))
                 ((Found found #f) (reverse found))))
              ((Some "struct") (loop (+ index 2) (break-struct tokens index breaks)))
              ((Some "define-record-type") (loop (+ index 2) (break-record tokens index breaks)))
              (_ (loop (+ index 1) breaks))))))

    ;; The lines with a break before each token in `breaks`, which are in
    ;; order, and the spaces before each break removed.

    (define (break-lines (lines (List Line)) (breaks (List Placed))) (→ (List String))
      (let loop ((lines lines) (index 0) (breaks breaks) (out (Nil)))
        (match lines
          ((Cons line rest)
           (let ((here (line-offsets breaks index)))
             (loop rest
                   (+ index 1)
                   (list-drop breaks (length here))
                   (append (reverse (split-line (● line text) here)) out))))
          ((Nil) (reverse out)))))

    (define (line-offsets (breaks (List Placed)) (index I64)) (→ (List I64))
      (match breaks
        ((Cons placed rest)
         (if (= (● placed line) index)
             (Cons (token-offset (● placed token)) (line-offsets rest index))
             (Nil)))
        ((Nil) (Nil))))

    (define (split-line (text String) (offsets (List I64))) (→ (List String))
      (let loop ((start 0) (offsets offsets) (out (Nil)))
        (match offsets
          ((Cons offset rest)
           (loop offset rest (Cons (trim-right (substring text start offset)) out)))
          ((Nil) (reverse (Cons (substring text start (string-length text)) out))))))

    (define (trim-right (text String)) (→ String)
      (let loop ((end (string-length text)))
        (if (and (> end 0) (member? (string-ref text (- end 1)) (list #\space #\tab)))
            (loop (- end 1))
            (substring text 0 end))))

    ;; ---- Long lines ----

    ;; A line whose code runs past the width, a comment after it not
    ;; counting, breaks before the next line is indented. Each list with an
    ;; element after the line's first token can break the line before some
    ;; of its elements, as its
    ;; shape says, and the outermost that can, does. The pieces are indented
    ;; as the lines they now are and broken in turn, so a line is final once
    ;; it fits or nothing on it can break.

    (define (format-width) (→ I64) 100)

    ;; How a list breaks, by its head. A call breaks before each argument
    ;; after its first, or before its first when no other is on the line. A
    ;; special form or definition breaks before each element from `from` on.
    ;; A binding form breaks before each element after its list at
    ;; `bindings`, and before each binding after the first. Elements count
    ;; from the head, at 0.
    (enum Shape
      (Arguments)
      (Body ((from I64)))
      (Binding ((bindings I64))))

    ;; Binding forms outside the naming convention, with the element each
    ;; keeps its bindings in. The body follows the bindings.

    (define (binding-forms) (→ (List (Pair String I64)))
      (list (Pair "letrec" 1)
            (Pair "letrec*" 1)
            (Pair "let-values" 1)
            (Pair "let*-values" 1)
            (Pair "parameterize" 1)
            (Pair "do" 1)
            (Pair "handle" 2)
            (Pair "learning" 2)
            (Pair "expanding" 2)
            (Pair "naming" 2)
            (Pair "specializing" 2)))

    ;; A name's shape follows its indentation rule: a special form keeps
    ;; only its first distinguished argument beside its name, and a
    ;; definition its first. A named `let` keeps its bindings after the name.

    (define (shape (elements Elements)) (→ Shape)
      (match (● (● elements head) head)
        ((Named name)
         (match (if (binding-name? name "let*") (Some 1) (assoc-ref (binding-forms) name))
           ((Some bindings) (Binding bindings))
           ((None)
            (match (indent-rule name)
              ((Call) (Arguments))
              ((Definition) (Body 2))
              ((Special distinguished) (Body (min (+ distinguished 1) 2)))
              ((LetRule) (Binding (if (names-loop? elements) 2 1)))))))
        (_ (Body 1))))

    ;; A list open while a line is scanned for breaks. Its breaks count as
    ;; those of the list at `depth` with `key`, the offset of its
    ;; parenthesis, or the binding form's when it holds a binding form's
    ;; `bindings`. A list that opened above the line, as the top level did,
    ;; has key -1: its head is behind it, so it breaks before each element.
    ;; `head` is where the first element starts, if on the line. After a
    ;; `!`, which starts the effects of a function type, nothing breaks.
    (struct Group
      ((depth I64)
       (key I64)
       (bindings Bool)
       (head (Option I64))
       (effects Bool)))

    (define (above? (group Group)) (→ Bool)
      (= (● group key) -1))

    ;; Somewhere a list could break the line: one of the places its shape
    ;; breaks, or a call's first argument, which breaks only when nothing
    ;; else does and preferably only where what it moves then fits.
    (enum Place
      (Break)
      (Fallback ((fits Bool))))

    (struct Candidate
      ((depth I64)
       (key I64)
       (offset I64)
       (place Place)))

    ;; The line being broken, where its code starts and ends, and the width.
    (struct Extent
      ((text String)
       (first I64)
       (end I64)
       (width I64)))

    ;; A line breaks only where spaces are, so tokens written together stay
    ;; together, and never before its first token.

    (define (breakable? (extent Extent) (start I64)) (→ Bool)
      (and (not (= start (● extent first)))
           (member? (string-ref (● extent text) (- start 1))
                    (list #\space #\tab))))

    ;; The scan of a line for breaks: the lists open, as indentation and as
    ;; breaking see them, and the candidates found so far, latest first.
    ;; The top level is always at the bottom of the groups.
    (struct Breaking
      ((scan Scan)
       (groups (List Group))
       (candidates (List Candidate))))

    ;; What an element tells the list it is in: the list's group afterwards,
    ;; the candidates it adds, and whether the element, a list, holds the
    ;; bindings of the binding form it is in.
    (struct Arrival
      ((group Group)
       (candidates (List Candidate))
       (bindings Bool)))

    ;; The lists open where a line starts, above the top level at depth 0.

    (define (enclosing-groups (frames (List Frame))) (→ (List Group))
      (match frames
        ((Cons _ rest)
         (Cons (Group (length frames) -1 #f (None) #f) (enclosing-groups rest)))
        ((Nil) (list (Group 0 -1 #f (None) #f)))))

    (define (next-index (frame Frame)) (→ I64)
      (match (● frame elements)
        ((Some elements) (+ (● elements count) 1))
        ((None) 0)))

    ;; An element of the list `group` describes starts at `start`, below the
    ;; lists `frames`; `opens` says it is a list, and `bang` that it is a
    ;; `!`. Nothing breaks where the line cannot, or after a `!`.

    (define (arrive (extent Extent)
                    (frames (List Frame))
                    (group Group)
                    (start I64)
                    (opens Bool)
                    (bang Bool))
      (→ Arrival)
      (let ((after (Group-effects-set group (or bang (● group effects))))
            (breaks
             (and (breakable? extent start) (not (● group effects)))))
        (if (above? group)
            (Arrival after (candidate-at group start breaks (Break)) #f)
            (match frames
              ((Cons frame _)
               (arrive-opened extent frame after start opens breaks))
              ;; A list that opened on the line is the innermost frame.
              ((Nil) (Arrival after (Nil) #f))))))

    ;; The next element of a list that opened on the line, which `frame`
    ;; describes: its head, a binding form's binding, or wherever the list's
    ;; shape breaks.

    (define (arrive-opened (extent Extent)
                           (frame Frame)
                           (group Group)
                           (start I64)
                           (opens Bool)
                           (breaks Bool))
      (→ Arrival)
      (let ((index (next-index frame)))
        (cond ((● group bindings)
               (Arrival group
                        (candidate-at group
                                      start
                                      (and (>= index 1)
                                           (breakable? extent start))
                                      (Break))
                        #f))
              ((= index 0)
               (Arrival (Group-head-set group (Some start)) (Nil) #f))
              (breaks (shaped-arrival extent
                                      (frame-shape frame)
                                      group
                                      index
                                      start
                                      opens))
              (else (Arrival group (Nil) #f)))))

    (define (frame-shape (frame Frame)) (→ Shape)
      (match (● frame elements)
        ((Some elements) (shape elements))
        ((None) (Body 1))))

    ;; Element `index` of a list of `shape`: the binding form's bindings, or
    ;; where it breaks.

    (define (shaped-arrival (extent Extent)
                            (shape Shape)
                            (group Group)
                            (index I64)
                            (start I64)
                            (opens Bool))
      (→ Arrival)
      (match shape
        ((Binding bindings)
         (if (and (= index bindings) opens)
             (Arrival group (Nil) #t)
             (Arrival group
                      (candidate-at group start (> index bindings) (Break))
                      #f)))
        ((Body from)
         (Arrival group (candidate-at group start (>= index from) (Break)) #f))
        ((Arguments)
         (Arrival group
                  (if (>= index 2)
                      (candidate-at group start #t (Break))
                      (fallback-at extent group start index))
                  #f))))

    (define (candidate-at (group Group) (start I64) (breaks Bool) (place Place))
      (→ (List Candidate))
      (if breaks
          (list (Candidate (● group depth) (● group key) start place))
          (Nil)))

    ;; A call's first argument, which would move under the call's head.

    (define (fallback-at (extent Extent) (group Group) (start I64) (index I64)) (→ (List Candidate))
      (match (● group head)
        ((Some head)
         (let ((moved (+ head (- (● extent end) start))))
           (candidate-at group
                         start
                         (= index 1)
                         (Fallback (<= moved (● extent width))))))
        ((None) (Nil))))

    ;; The innermost list learns of an element starting at `start`.

    (define (arrive-innermost (extent Extent)
                              (breaking Breaking)
                              (start I64)
                              (opens Bool)
                              (bang Bool))
      (→ (Option Arrival))
      (match (● breaking groups)
        ((Cons group _)
         (Some (arrive extent
                       (● (● breaking scan) frames)
                       group
                       start
                       opens
                       bang)))
        ((Nil) (None))))

    (define (settle (breaking Breaking) (scan Scan) (arrival (Option Arrival))) (→ Breaking)
      (match arrival
        ((Some (Arrival group candidates _))
         (Breaking scan
                   (Cons group (list-drop (● breaking groups) 1))
                   (append candidates (● breaking candidates))))
        ((None) (Breaking-scan-set breaking scan))))

    ;; The group of a list that opens at `key`: the binding form's, when the
    ;; list holds its bindings.

    (define (opened-group (arrival (Option Arrival)) (depth I64) (key I64)) (→ Group)
      (match arrival
        ((Some (Arrival owner _ #t))
         (Group (● owner depth) (● owner key) #t (None) #f))
        (_ (Group depth key #f (None) #f))))

    ;; A list closes; a parenthesis too many leaves the top level in place.

    (define (close-group (groups (List Group))) (→ (List Group))
      (match groups
        ((Cons _ (Cons next rest)) (Cons next rest))
        (_ groups)))

    ;; A list opens at `key`, starting at `start`: it arrives in the list
    ;; it is in, and its own group goes on top.

    (define (open-list (extent Extent) (breaking Breaking) (scan Scan) (start I64) (key I64))
      (→ Breaking)
      (let* ((arrival (arrive-innermost extent breaking start #t #f))
             (settled (settle breaking scan arrival)))
        (Breaking-groups-set
         settled
         (Cons (opened-group arrival (length (● scan frames)) key)
               (● settled groups)))))

    ;; One token of the line, `shift` columns from its offset, on line
    ;; `line`: lists open and close, and each element arrives in its list.

    (define (break-token (extent Extent) (shift I64) (line I64) (breaking Breaking) (token Token))
      (→ Breaking)
      (let ((start (or-else (● (● breaking scan) prefix)
                            (+ (token-offset token) shift)))
            (scan (scan-token (● breaking scan) token shift line)))
        (match token
          ((Prefix _) (Breaking-scan-set breaking scan))
          ((Close _)
           (Breaking scan
                     (close-group (● breaking groups))
                     (● breaking candidates)))
          ((Open offset _)
           (open-list extent breaking scan start (+ offset shift)))
          ((Atom offset text)
           (let ((bang (and (string=? text "!") (= start (+ offset shift)))))
             (settle breaking
                     scan
                     (arrive-innermost extent breaking start #f bang))))
          ((Text _)
           (settle breaking
                   scan
                   (arrive-innermost extent breaking start #f #f))))))

    ;; The candidates of a line, in order, below the lists `frames`.

    (define (line-candidates (extent Extent)
                             (line Line)
                             (shift I64)
                             (frames (List Frame))
                             (index I64))
      (→ (List Candidate))
      (reverse
       (● (fold-left (lambda (breaking token)
                       (break-token extent shift index breaking token))
                     (Breaking (Scan frames (None) (None))
                               (enclosing-groups frames)
                               (Nil))
                     (● line tokens)) candidates)))

    ;; ---- Choosing breaks ----

    ;; The outermost of `candidates` that `eligible` accepts, the leftmost
    ;; of those equally deep.

    (define (outermost (candidates (List Candidate)) (eligible (Fn Candidate → Bool)))
      (→ (Option Candidate))
      (fold-left (lambda (best candidate)
                   (if (and (eligible candidate)
                            (match best
                              ((Some found) (outside? candidate found))
                              ((None) #t)))
                       (Some candidate)
                       best))
                 (None)
                 candidates))

    (define (outside? (a Candidate) (b Candidate)) (→ Bool)
      (or (< (● a depth) (● b depth))
          (and (= (● a depth) (● b depth))
               (< (● a key) (● b key)))))

    (define (same-list? (a Candidate) (b Candidate)) (→ Bool)
      (and (= (● a depth) (● b depth))
           (= (● a key) (● b key))))

    (define (breaks? (candidate Candidate)) (→ Bool)
      (match (● candidate place)
        ((Break) #t)
        ((Fallback fits) #f)))

    (define (fits? (candidate Candidate)) (→ Bool)
      (match (● candidate place)
        ((Break) #t)
        ((Fallback fits) fits)))

    ;; The outermost list that can break, breaks: before each of its breaks,
    ;; or else before its fallback. A fallback whose move would not fit is a
    ;; last resort, taken only when nothing else on the line can break.

    (define (chosen-breaks (candidates (List Candidate))) (→ (List I64))
      (match (outermost candidates fits?)
        ((Some best) (list-breaks candidates best))
        ((None)
         (match (outermost candidates (lambda (candidate) #t))
           ((Some best) (list-breaks candidates best))
           ((None) (Nil))))))

    (define (list-breaks (candidates (List Candidate)) (best Candidate)) (→ (List I64))
      (let* ((own (filter (lambda (candidate) (same-list? candidate best))
                          candidates))
             (breaks (filter breaks? own)))
        (map (lambda (record) (● record offset)) (if (null? breaks) own breaks))))

    ;; Where to break a line indented by `shift`, as offsets in the indented
    ;; line, when its code runs past `width`.

    (define (line-breaks (line Line)
                         (text String)
                         (shift I64)
                         (frames (List Frame))
                         (index I64)
                         (width I64))
      (→ (List I64))
      (match (● line tokens)
        ((Cons token _)
         (let ((extent (Extent text
                               (+ (token-offset token) shift)
                               (+ (● line end) shift)
                               width)))
           (if (and (code-mode? (● line mode)) (> (● extent end) width))
               (chosen-breaks (line-candidates extent line shift frames index))
               (Nil))))
        ((Nil) (Nil))))

    ;; Indents each line as `indent-lines` does, first breaking it when its
    ;; code runs past `width`. The pieces of a broken line are lines in
    ;; their turn; the first is already indented.

    (define (fit-lines (text String) (width I64)) (→ String)
      (let loop ((lines (lex text)) (index 0) (frames (Nil)) (out (Nil)))
        (match lines
          ((Cons line rest)
           (match (reindent line frames)
             ((Pair indented shift)
              (let ((breaks
                     (line-breaks line indented shift frames index width)))
                (if (null? breaks)
                    (loop rest
                          (+ index 1)
                          (scan-line frames (● line tokens) shift index)
                          (Cons indented out))
                    (loop
                     (append (map code-line (split-line indented breaks)) rest)
                     index
                     frames
                     out))))))
          ((Nil) (string-join (reverse out) "\n")))))

    (define (code-line (text String)) (→ Line)
      (● (lex-line text (Code)) first))

    ;; ---- Formatting ----

    ;; Declarations first, then indentation, breaking lines past `width`.

    (define (format-source (text String) (width I64)) (→ String)
      (let* ((lines (lex text))
             (broken (string-join (break-lines lines
                                               (declaration-breaks
                                                (placed-tokens lines)))
                                  "\n")))
        (fit-lines broken width)))))
