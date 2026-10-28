;; Indentation, formatting and highlighting of Lisp source, matching this
;; repository's formatter: Emacs's scheme-mode with the rules in
;; scripts/format-scheme.el.
;; Formatting first puts each import specification, struct field and record
;; field on its own line, then indents every line. A line's indentation
;; follows Emacs's `calculate-lisp-indent`: it goes under the first argument
;; of a call, under the first expression of the line its list's last element
;; starts on, or in by two columns for the body of a special form, as the
;; rule for the form's name says. A line whose code runs past the width,
;; `format-width` unless the caller says otherwise, is broken before the
;; next is indented: a call before its arguments, a binding form before
;; each binding and body form. Nothing ever joins lines. The IDE
;; (host/ide/format.sld) formats on save and indents a line when Tab is
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

    ;; A line starts in code, inside a string, or inside a block comment;
    ;; lines that start inside either keep their indentation.
    (enum Mode
      (Code)
      (InString)
      (InComment ((depth I64))))

    ;; A line, the mode it starts in, its tokens, and the offset just past
    ;; its last token, where its code ends before any comment.
    (struct Line
      ((text String)
       (mode Mode)
       (tokens (List Token))
       (end I64)))

    ;; ---- Lexing ----

    (: lex (-> String (List Line)))
    (define (lex text)
      (let loop ((lines (split-lines text)) (mode (Code)) (out (Nil)))
        (match lines
          ((Cons line rest)
           (match (lex-line line mode)
             ((Pair lexed next) (loop rest next (Cons lexed out)))))
          ((Nil) (reverse out)))))

    ;; A final newline leaves a final empty line.
    (: split-lines (-> String (List String)))
    (define (split-lines text)
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
    (: lex-line (-> String Mode (Pair Line Mode)))
    (define (lex-line line mode)
      (let loop ((offset 0) (state mode) (tokens (Nil)) (end 0))
        (if (>= offset (string-length line))
            (Pair (Line line mode (reverse tokens) end) state)
            (let ((step (lex-step line offset state)))
              (match (Step-token step)
                ((Some token)
                 (loop (Step-next step)
                       (Step-mode step)
                       (Cons token tokens)
                       (Step-next step)))
                ((None)
                 (loop (Step-next step) (Step-mode step) tokens end)))))))

    (: lex-step (-> String I64 Mode Step))
    (define (lex-step line offset mode)
      (match mode
        ((Code) (lex-code line offset))
        ((InString) (lex-string line offset))
        ((InComment depth) (lex-comment line offset depth))))

    (: lex-code (-> String I64 Step))
    (define (lex-code line offset)
      (let ((c (string-ref line offset)) (after (+ offset 1)))
        (cond ((char-whitespace? c) (Step after (Code) (None)))
              ((= c #\;) (Step (string-length line) (Code) (None)))
              ((or (= c #\() (= c #\[)) (code-token after (Open offset (spaced? line after))))
              ((or (= c #\)) (= c #\])) (code-token after (Close offset)))
              ((= c #\") (Step-token-set (lex-string line after) (Some (Text offset))))
              ((or (= c #\') (= c #\`)) (code-token after (Prefix offset)))
              ((= c #\,) (code-token (if (at? line after "@") (+ after 1) after) (Prefix offset)))
              ((= c #\#) (lex-hash line offset))
              (else (lex-atom line offset offset)))))

    (: code-token (-> I64 Token Step))
    (define (code-token next token)
      (Step next (Code) (Some token)))

    ;; `#(` opens a vector, `#|` a block comment, and `#;` comments out the
    ;; next datum, which counts here as a prefix; `#\` starts a character,
    ;; whatever character follows it.
    (: lex-hash (-> String I64 Step))
    (define (lex-hash line offset)
      (let ((after (+ offset 1)))
        (cond ((at? line after "(") (code-token after (Prefix offset)))
              ((at? line after "|") (lex-comment line (+ after 1) 1))
              ((at? line after ";") (code-token (+ after 1) (Prefix offset)))
              ((at? line after "\\") (lex-atom line offset (min (+ after 2) (string-length line))))
              (else (lex-atom line offset after)))))

    (: lex-atom (-> String I64 I64 Step))
    (define (lex-atom line start from)
      (let ((end (atom-end line from)))
        (code-token end (Atom start (substring line start end)))))

    (: atom-end (-> String I64 I64))
    (define (atom-end line offset)
      (if (or (>= offset (string-length line)) (delimiter? (string-ref line offset)))
          offset
          (atom-end line (+ offset 1))))

    (: delimiter? (-> Char Bool))
    (define (delimiter? c)
      (or (char-whitespace? c) (member? c (list #\( #\) #\[ #\] #\" #\; #\' #\` #\,))))

    ;; Inside a string, past its closing quote, or to the end of the line,
    ;; which the string continues beyond.
    (: lex-string (-> String I64 Step))
    (define (lex-string line offset)
      (cond ((>= offset (string-length line)) (Step offset (InString) (None)))
            ((= (string-ref line offset) #\\)
             (lex-string line (min (+ offset 2) (string-length line))))
            ((= (string-ref line offset) #\") (Step (+ offset 1) (Code) (None)))
            (else (lex-string line (+ offset 1)))))

    ;; Inside a block comment, which nests.
    (: lex-comment (-> String I64 I64 Step))
    (define (lex-comment line offset depth)
      (cond ((>= offset (string-length line)) (Step offset (InComment depth) (None)))
            ((at? line offset "|#")
             (if (= depth 1)
                 (Step (+ offset 2) (Code) (None))
                 (lex-comment line (+ offset 2) (- depth 1))))
            ((at? line offset "#|") (lex-comment line (+ offset 2) (+ depth 1)))
            (else (lex-comment line (+ offset 1) depth))))

    (: spaced? (-> String I64 Bool))
    (define (spaced? line offset)
      (and (< offset (string-length line)) (member? (string-ref line offset) (list #\space #\tab))))

    (: at? (-> String I64 String Bool))
    (define (at? line offset text)
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

    ;; The rules of Emacs 29's scheme-mode, as scheme.el gives them, then
    ;; those scripts/format-scheme.el adds for Snail-Core's forms, with `guard` as
    ;; Emacs 31 indents it.
    (: rules (List (Pair String Rule)))
    (define rules
      (concatenate
       (list (map (lambda (name) (Pair name (Special 0)))
                  (list "begin"
                        "delay"
                        "make-environment"
                        "match-lambda"
                        "match-lambda*"
                        "sequence"
                        "with-output-to-string"))
             (map (lambda (name) (Pair name (Special 1)))
                  (list "access-components"
                        "and-let*"
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
                        "fluid-let"
                        "in-package"
                        "in-package-components"
                        "lambda"
                        "lambda-components"
                        "lambda-components*"
                        "lambda-components**"
                        "let*"
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
                        "match-let*"
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
                        "with-output-to-port" "with-syntax" "with-values" "λ"))
             (map (lambda (name) (Pair name (Special 2)))
                  (list "do" "receive" "syntax-case" "syntax-table-define"))
             (list (Pair "dynamic-wind" (Special 3))
                   (Pair "let" (LetRule))
                   (Pair "match-let" (LetRule))
                   (Pair "syntax-rules" (Definition)))
             (map (lambda (name) (Pair name (Special 1)))
                  (list "struct" "enum" "typeclass" "instance" "effect" "match" "guard"))
             (list (Pair "handle" (Special 2))))))

    ;; A name without a rule that starts with `def` and is longer than
    ;; three characters is a definition. Emacs ignores case here, so
    ;; `Defined` is one too.
    (: indent-rule (-> String Rule))
    (define (indent-rule name)
      (match (assoc-ref rules name)
        ((Some rule) rule)
        ((None) (if (and (> (string-length name) 3) (def-prefix? name)) (Definition) (Call)))))

    (: def-prefix? (-> String Bool))
    (define (def-prefix? name)
      (every? (lambda (pair) (member? (string-ref name (Pair-first pair)) (Pair-second pair)))
              (list (Pair 0 (list #\d #\D)) (Pair 1 (list #\e #\E)) (Pair 2 (list #\f #\F)))))

    ;; ---- Indentation ----

    ;; The column of a line that starts inside `frame`: just inside the
    ;; parenthesis when nothing follows it yet, else as the head's rule says.
    (: frame-indent (-> Frame I64))
    (define (frame-indent frame)
      (match (Frame-elements frame)
        ((Some elements)
         (match (Element-head (Elements-head elements))
           ((Named name) (named-indent frame elements name (normal-indent frame elements)))
           (_ (unnamed-indent (Elements-head elements) (Elements-last elements)))))
        ((None) (+ (Frame-column frame) 1))))

    ;; On the head's line, align under the first argument, or the head when
    ;; there is no argument or a space follows the parenthesis. Later align
    ;; under the first expression on the last element's line.
    (: normal-indent (-> Frame Elements I64))
    (define (normal-indent frame elements)
      (let ((head (Elements-head elements)) (last (Elements-last elements)))
        (cond ((not (= (Element-line last) (Element-line head))) (Element-first last))
              ((Frame-spaced frame) (Element-column head))
              (else (match (Elements-first elements)
                      ((Some argument) (Element-column argument))
                      ((None) (Element-column head)))))))

    ;; A list whose head is not a name lines up with its head while its
    ;; elements share the head's line.
    (: unnamed-indent (-> Element Element I64))
    (define (unnamed-indent head last)
      (if (= (Element-line last) (Element-line head)) (Element-column head) (Element-first last)))

    (: named-indent (-> Frame Elements String I64 I64))
    (define (named-indent frame elements name normal)
      (match (indent-rule name)
        ((Call) normal)
        ((Definition)
         (if (= (Element-line (Elements-last elements)) (Frame-line frame))
             (+ (Frame-column frame) 2)
             normal))
        ((Special distinguished)
         (special-indent frame distinguished (Elements-count elements) normal))
        ((LetRule)
         (special-indent frame (if (names-loop? elements) 2 1) (Elements-count elements) normal))))

    ;; Emacs's `lisp-indent-specform`. A distinguished argument goes in by
    ;; four columns when it is one of the first two; the first body form goes
    ;; in by two, unless the line above sits further left.
    (: special-indent (-> Frame I64 I64 I64 I64))
    (define (special-indent frame distinguished arguments normal)
      (let ((left (- distinguished arguments)) (body (+ (Frame-column frame) 2)))
        (cond ((> left 0) (if (<= arguments 1) (+ (Frame-column frame) 4) normal))
              ((or (and (= distinguished 0) (= arguments 0)) (and (= left 0) (<= body normal)))
               body)
              (else normal))))

    ;; A named `let`: a name follows `let` on its line.
    (: names-loop? (-> Elements Bool))
    (define (names-loop? elements)
      (match elements
        ((Elements head (Some (Element (Named name) _ line _)) _ _)
         (and (= line (Element-line head)) (member? (string-ref name 0) loop-name-starts)))
        (_ #f)))

    (: loop-name-starts (List Char))
    (define loop-name-starts
      (string->list "-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+*/?!@$%^&_:~"))

    ;; ---- Indenting lines ----

    ;; Reindents lines `first` to `last`, counting from 0, and keeps the
    ;; others as they are. Lines are indented in order, each from the lists
    ;; open where it starts, as the lines above it now stand.
    (: indent-lines (-> String I64 I64 String))
    (define (indent-lines text first last)
      (let loop ((lines (lex text)) (index 0) (frames (Nil)) (out (Nil)))
        (match lines
          ((Cons line rest)
           (match (if (and (<= first index) (<= index last))
                      (reindent line frames)
                      (Pair (Line-text line) 0))
             ((Pair indented shift)
              (loop rest
                    (+ index 1)
                    (scan-line frames (Line-tokens line) shift index)
                    (Cons indented out)))))
          ((Nil) (string-join (reverse out) "\n")))))

    ;; A line's new text, and how far its tokens moved. A blank line
    ;; becomes empty; a line inside a string or block comment, or one that
    ;; starts with three semicolons, stays as it is.
    (: reindent (-> Line (List Frame) (Pair String I64)))
    (define (reindent line frames)
      (let* ((text (Line-text line))
             (start (indentation text))
             (rest (substring text start (string-length text))))
        (cond ((not (code-mode? (Line-mode line))) (Pair text 0))
              ((string=? rest "") (Pair "" 0))
              ((at? rest 0 ";;;") (Pair text 0))
              (else (let ((column (stack-indent frames)))
                      (Pair (string-append (make-string column #\space) rest) (- column start)))))))

    (: indentation (-> String I64))
    (define (indentation text)
      (let loop ((index 0))
        (if
         (and (< index (string-length text)) (member? (string-ref text index) (list #\space #\tab)))
         (loop (+ index 1))
         index)))

    (: code-mode? (-> Mode Bool))
    (define (code-mode? mode)
      (match mode
        ((Code) #t)
        (_ #f)))

    (: stack-indent (-> (List Frame) I64))
    (define (stack-indent frames)
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
    (: scan-line (-> (List Frame) (List Token) I64 I64 (List Frame)))
    (define (scan-line frames tokens shift line)
      (Scan-frames (fold-left (lambda (scan token) (scan-token scan token shift line))
                              (Scan frames (None) (None))
                              tokens)))

    (: scan-token (-> Scan Token I64 I64 Scan))
    (define (scan-token scan token shift line)
      (match token
        ((Open offset spaced)
         (let ((added (add-expression scan (Listed) (+ offset shift) line)))
           (Scan-frames-set added
                            (Cons (Frame (+ offset shift) line spaced (None))
                                  (Scan-frames added)))))
        ((Close _) (Scan-frames-set scan (list-drop (Scan-frames scan) 1)))
        ((Prefix offset)
         (Scan (Scan-frames scan) (Some (or-else (Scan-first scan) (+ offset shift)))
               (Some (or-else (Scan-prefix scan) (+ offset shift)))))
        ((Atom offset text) (add-expression scan (atom-head text) (+ offset shift) line))
        ((Text offset) (add-expression scan (Other) (+ offset shift) line))))

    ;; A character is not a name.
    (: atom-head (-> String Head))
    (define (atom-head text)
      (if (at? text 0 "#\\") (Other) (Named text)))

    ;; An expression starts at `column`, or at the prefix before it, as an
    ;; element of the innermost list.
    (: add-expression (-> Scan Head I64 I64 Scan))
    (define (add-expression scan head column line)
      (let* ((start (or-else (Scan-prefix scan) column)) (first (or-else (Scan-first scan) start)))
        (Scan (add-element (Scan-frames scan) (Element head start line first))
              (Some first)
              (None))))

    (: add-element (-> (List Frame) Element (List Frame)))
    (define (add-element frames element)
      (match frames
        ((Cons frame rest)
         (Cons (Frame-elements-set frame (Some (extend (Frame-elements frame) element))) rest))
        ((Nil) (Nil))))

    ;; The first element is the head; each later one is the latest argument,
    ;; and the earliest of those is remembered.
    (: extend (-> (Option Elements) Element Elements))
    (define (extend elements element)
      (match elements
        ((None) (Elements element (None) element 0))
        ((Some (Elements head first _ count))
         (Elements head (match first ((None) (Some element)) (_ first)) element (+ count 1)))))

    (: or-else (-> (Option I64) I64 I64))
    (define (or-else value default)
      (match value
        ((Some found) found)
        ((None) default)))

    ;; ---- Declarations ----

    ;; A token with the line it is on.
    (struct Placed
      ((line I64)
       (token Token)))

    (: placed-tokens (-> (List Line) (Vector Placed)))
    (define (placed-tokens lines)
      (list->vector (concatenate (map-indexed (lambda (index line)
                                                (map (lambda (token) (Placed index token))
                                                     (Line-tokens line)))
                                              lines))))

    (: token-offset (-> Token I64))
    (define (token-offset token)
      (match token
        ((Open offset _) offset)
        ((Close offset) offset)
        ((Prefix offset) offset)
        ((Atom offset _) offset)
        ((Text offset) offset)))

    ;; The index after the expression that starts at token `index`, if one
    ;; starts there and ends.
    (: expression-end (-> (Vector Placed) I64 (Option I64)))
    (define (expression-end tokens index)
      (if (>= index (vector-length tokens))
          (None)
          (match (Placed-token (vector-ref tokens index))
            ((Prefix _) (expression-end tokens (+ index 1)))
            ((Open _ _) (list-end tokens (+ index 1) 1))
            ((Close _) (None))
            (_ (Some (+ index 1))))))

    (: list-end (-> (Vector Placed) I64 I64 (Option I64)))
    (define (list-end tokens index depth)
      (cond ((= depth 0) (Some index))
            ((>= index (vector-length tokens)) (None))
            (else (match (Placed-token (vector-ref tokens index))
                    ((Open _ _) (list-end tokens (+ index 1) (+ depth 1)))
                    ((Close _) (list-end tokens (+ index 1) (- depth 1)))
                    (_ (list-end tokens (+ index 1) depth))))))

    (: skip-expressions (-> (Vector Placed) I64 I64 (Option I64)))
    (define (skip-expressions tokens index count)
      (if (= count 0)
          (Some index)
          (match (expression-end tokens index)
            ((Some next) (skip-expressions tokens next (- count 1)))
            ((None) (None)))))

    (: open-at? (-> (Vector Placed) I64 Bool))
    (define (open-at? tokens index)
      (and (< index (vector-length tokens))
           (match (Placed-token (vector-ref tokens index))
             ((Open _ _) #t)
             (_ #f))))

    ;; The name right after the parenthesis at token `index`.
    (: form-name (-> (Vector Placed) I64 (Option String)))
    (define (form-name tokens index)
      (if (and (open-at? tokens index) (< (+ index 1) (vector-length tokens)))
          (match (Pair (vector-ref tokens index) (vector-ref tokens (+ index 1)))
            ((Pair (Placed line (Open offset _)) (Placed next-line (Atom next-offset name)))
             (if (and (= line next-line) (= next-offset (+ offset 1))) (Some name) (None)))
            (_ (None)))
          (None)))

    ;; Breaks found so far, and whether the expressions they lie in ended.
    (struct Found
      ((breaks (List Placed))
       (ended Bool)))

    ;; Each list from token `index` on starts its own line, up to the first
    ;; element that is not a list.
    (: break-entries (-> (Vector Placed) I64 (List Placed) Found))
    (define (break-entries tokens index breaks)
      (if (open-at? tokens index)
          (let ((breaks (break-before tokens index breaks)))
            (match (expression-end tokens index)
              ((Some next) (break-entries tokens next breaks))
              ((None) (Found breaks #f))))
          (Found breaks #t)))

    (: break-before (-> (Vector Placed) I64 (List Placed) (List Placed)))
    (define (break-before tokens index breaks)
      (if (or (= index 0)
              (not (= (Placed-line (vector-ref tokens (- index 1)))
                      (Placed-line (vector-ref tokens index)))))
          breaks
          (Cons (vector-ref tokens index) breaks)))

    ;; A struct's field list starts its own line, and so does each field
    ;; after the first.
    (: break-struct (-> (Vector Placed) I64 (List Placed) (List Placed)))
    (define (break-struct tokens index breaks)
      (match (skip-expressions tokens (+ index 1) 2)
        ((Some fields)
         (if (open-at? tokens fields)
             (break-fields tokens (+ fields 1) (break-before tokens fields breaks))
             breaks))
        ((None) breaks)))

    (: break-fields (-> (Vector Placed) I64 (List Placed) (List Placed)))
    (define (break-fields tokens index breaks)
      (if (open-at? tokens index)
          (match (expression-end tokens index)
            ((Some next) (Found-breaks (break-entries tokens next breaks)))
            ((None) breaks))
          breaks))

    (: break-record (-> (Vector Placed) I64 (List Placed) (List Placed)))
    (define (break-record tokens index breaks)
      (match (skip-expressions tokens (+ index 1) 4)
        ((Some fields) (Found-breaks (break-entries tokens fields breaks)))
        ((None) breaks)))

    ;; Where Emacs's formatter breaks lines, in order: before each import
    ;; specification, a struct's field list and its fields after the first,
    ;; and a record type's fields. An import that does not end stops the
    ;; search, since everything after it is part of it.
    (: declaration-breaks (-> (Vector Placed) (List Placed)))
    (define (declaration-breaks tokens)
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
    (: break-lines (-> (List Line) (List Placed) (List String)))
    (define (break-lines lines breaks)
      (let loop ((lines lines) (index 0) (breaks breaks) (out (Nil)))
        (match lines
          ((Cons line rest)
           (let ((here (line-offsets breaks index)))
             (loop rest
                   (+ index 1)
                   (list-drop breaks (length here))
                   (append (reverse (split-line (Line-text line) here)) out))))
          ((Nil) (reverse out)))))

    (: line-offsets (-> (List Placed) I64 (List I64)))
    (define (line-offsets breaks index)
      (match breaks
        ((Cons placed rest)
         (if (= (Placed-line placed) index)
             (Cons (token-offset (Placed-token placed)) (line-offsets rest index))
             (Nil)))
        ((Nil) (Nil))))

    (: split-line (-> String (List I64) (List String)))
    (define (split-line text offsets)
      (let loop ((start 0) (offsets offsets) (out (Nil)))
        (match offsets
          ((Cons offset rest)
           (loop offset rest (Cons (trim-right (substring text start offset)) out)))
          ((Nil) (reverse (Cons (substring text start (string-length text)) out))))))

    (: trim-right (-> String String))
    (define (trim-right text)
      (let loop ((end (string-length text)))
        (if (and (> end 0) (member? (string-ref text (- end 1)) (list #\space #\tab)))
            (loop (- end 1))
            (substring text 0 end))))

    ;; ---- Long lines ----

    ;; A line whose code runs past the width, a comment after it not
    ;; counting, breaks before the next line is indented, as in
    ;; scripts/format-scheme.el. Each list with an element after the line's
    ;; first token can break the line before some of its elements, as its
    ;; shape says, and the outermost that can, does. The pieces are indented
    ;; as the lines they now are and broken in turn, so a line is final once
    ;; it fits or nothing on it can break.

    (: format-width I64)
    (define format-width 100)

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

    ;; Binding forms besides `let`, with the element each keeps its bindings
    ;; in. The body follows the bindings.
    (: binding-forms (List (Pair String I64)))
    (define binding-forms
      (list (Pair "let*" 1)
            (Pair "letrec" 1)
            (Pair "letrec*" 1)
            (Pair "let-values" 1)
            (Pair "let*-values" 1)
            (Pair "parameterize" 1)
            (Pair "do" 1)
            (Pair "handle" 2)
            (Pair "learning" 2)
            (Pair "expanding" 2)
            (Pair "naming" 2)))

    ;; A name's shape follows its indentation rule: a special form keeps
    ;; only its first distinguished argument beside its name, and a
    ;; definition its first. A named `let` keeps its bindings after the name.
    (: shape (-> Elements Shape))
    (define (shape elements)
      (match (Element-head (Elements-head elements))
        ((Named name)
         (match (assoc-ref binding-forms name)
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

    (: above? (-> Group Bool))
    (define (above? group)
      (= (Group-key group) -1))

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
    (: breakable? (-> Extent I64 Bool))
    (define (breakable? extent start)
      (and (not (= start (Extent-first extent)))
           (member? (string-ref (Extent-text extent) (- start 1))
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
    (: enclosing-groups (-> (List Frame) (List Group)))
    (define (enclosing-groups frames)
      (match frames
        ((Cons _ rest)
         (Cons (Group (length frames) -1 #f (None) #f) (enclosing-groups rest)))
        ((Nil) (list (Group 0 -1 #f (None) #f)))))

    (: next-index (-> Frame I64))
    (define (next-index frame)
      (match (Frame-elements frame)
        ((Some elements) (+ (Elements-count elements) 1))
        ((None) 0)))

    ;; An element of the list `group` describes starts at `start`, below the
    ;; lists `frames`; `opens` says it is a list, and `bang` that it is a
    ;; `!`. Nothing breaks where the line cannot, or after a `!`.
    (: arrive (-> Extent (List Frame) Group I64 Bool Bool Arrival))
    (define (arrive extent frames group start opens bang)
      (let ((after (Group-effects-set group (or bang (Group-effects group))))
            (breaks
             (and (breakable? extent start) (not (Group-effects group)))))
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
    (: arrive-opened (-> Extent Frame Group I64 Bool Bool Arrival))
    (define (arrive-opened extent frame group start opens breaks)
      (let ((index (next-index frame)))
        (cond ((Group-bindings group)
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

    (: frame-shape (-> Frame Shape))
    (define (frame-shape frame)
      (match (Frame-elements frame)
        ((Some elements) (shape elements))
        ((None) (Body 1))))

    ;; Element `index` of a list of `shape`: the binding form's bindings, or
    ;; where it breaks.
    (: shaped-arrival (-> Extent Shape Group I64 I64 Bool Arrival))
    (define (shaped-arrival extent shape group index start opens)
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

    (: candidate-at (-> Group I64 Bool Place (List Candidate)))
    (define (candidate-at group start breaks place)
      (if breaks
          (list (Candidate (Group-depth group) (Group-key group) start place))
          (Nil)))

    ;; A call's first argument, which would move under the call's head.
    (: fallback-at (-> Extent Group I64 I64 (List Candidate)))
    (define (fallback-at extent group start index)
      (match (Group-head group)
        ((Some head)
         (let ((moved (+ head (- (Extent-end extent) start))))
           (candidate-at group
                         start
                         (= index 1)
                         (Fallback (<= moved (Extent-width extent))))))
        ((None) (Nil))))

    ;; The innermost list learns of an element starting at `start`.
    (: arrive-innermost (-> Extent Breaking I64 Bool Bool (Option Arrival)))
    (define (arrive-innermost extent breaking start opens bang)
      (match (Breaking-groups breaking)
        ((Cons group _)
         (Some (arrive extent
                       (Scan-frames (Breaking-scan breaking))
                       group
                       start
                       opens
                       bang)))
        ((Nil) (None))))

    (: settle (-> Breaking Scan (Option Arrival) Breaking))
    (define (settle breaking scan arrival)
      (match arrival
        ((Some (Arrival group candidates _))
         (Breaking scan
                   (Cons group (list-drop (Breaking-groups breaking) 1))
                   (append candidates (Breaking-candidates breaking))))
        ((None) (Breaking-scan-set breaking scan))))

    ;; The group of a list that opens at `key`: the binding form's, when the
    ;; list holds its bindings.
    (: opened-group (-> (Option Arrival) I64 I64 Group))
    (define (opened-group arrival depth key)
      (match arrival
        ((Some (Arrival owner _ #t))
         (Group (Group-depth owner) (Group-key owner) #t (None) #f))
        (_ (Group depth key #f (None) #f))))

    ;; A list closes; a parenthesis too many leaves the top level in place.
    (: close-group (-> (List Group) (List Group)))
    (define (close-group groups)
      (match groups
        ((Cons _ (Cons next rest)) (Cons next rest))
        (_ groups)))

    ;; A list opens at `key`, starting at `start`: it arrives in the list
    ;; it is in, and its own group goes on top.
    (: open-list (-> Extent Breaking Scan I64 I64 Breaking))
    (define (open-list extent breaking scan start key)
      (let* ((arrival (arrive-innermost extent breaking start #t #f))
             (settled (settle breaking scan arrival)))
        (Breaking-groups-set
         settled
         (Cons (opened-group arrival (length (Scan-frames scan)) key)
               (Breaking-groups settled)))))

    ;; One token of the line, `shift` columns from its offset, on line
    ;; `line`: lists open and close, and each element arrives in its list.
    (: break-token (-> Extent I64 I64 Breaking Token Breaking))
    (define (break-token extent shift line breaking token)
      (let ((start (or-else (Scan-prefix (Breaking-scan breaking))
                            (+ (token-offset token) shift)))
            (scan (scan-token (Breaking-scan breaking) token shift line)))
        (match token
          ((Prefix _) (Breaking-scan-set breaking scan))
          ((Close _)
           (Breaking scan
                     (close-group (Breaking-groups breaking))
                     (Breaking-candidates breaking)))
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
    (: line-candidates (-> Extent Line I64 (List Frame) I64 (List Candidate)))
    (define (line-candidates extent line shift frames index)
      (reverse
       (Breaking-candidates
        (fold-left (lambda (breaking token)
                     (break-token extent shift index breaking token))
                   (Breaking (Scan frames (None) (None))
                             (enclosing-groups frames)
                             (Nil))
                   (Line-tokens line)))))

    ;; ---- Choosing breaks ----

    ;; The outermost of `candidates` that `eligible` accepts, the leftmost
    ;; of those equally deep.
    (: outermost (-> (List Candidate) (-> Candidate Bool) (Option Candidate)))
    (define (outermost candidates eligible)
      (fold-left (lambda (best candidate)
                   (if (and (eligible candidate)
                            (match best
                              ((Some found) (outside? candidate found))
                              ((None) #t)))
                       (Some candidate)
                       best))
                 (None)
                 candidates))

    (: outside? (-> Candidate Candidate Bool))
    (define (outside? a b)
      (or (< (Candidate-depth a) (Candidate-depth b))
          (and (= (Candidate-depth a) (Candidate-depth b))
               (< (Candidate-key a) (Candidate-key b)))))

    (: same-list? (-> Candidate Candidate Bool))
    (define (same-list? a b)
      (and (= (Candidate-depth a) (Candidate-depth b))
           (= (Candidate-key a) (Candidate-key b))))

    (: breaks? (-> Candidate Bool))
    (define (breaks? candidate)
      (match (Candidate-place candidate)
        ((Break) #t)
        ((Fallback fits) #f)))

    (: fits? (-> Candidate Bool))
    (define (fits? candidate)
      (match (Candidate-place candidate)
        ((Break) #t)
        ((Fallback fits) fits)))

    ;; The outermost list that can break, breaks: before each of its breaks,
    ;; or else before its fallback. A fallback whose move would not fit is a
    ;; last resort, taken only when nothing else on the line can break.
    (: chosen-breaks (-> (List Candidate) (List I64)))
    (define (chosen-breaks candidates)
      (match (outermost candidates fits?)
        ((Some best) (list-breaks candidates best))
        ((None)
         (match (outermost candidates (lambda (candidate) #t))
           ((Some best) (list-breaks candidates best))
           ((None) (Nil))))))

    (: list-breaks (-> (List Candidate) Candidate (List I64)))
    (define (list-breaks candidates best)
      (let* ((own (filter (lambda (candidate) (same-list? candidate best))
                          candidates))
             (breaks (filter breaks? own)))
        (map Candidate-offset (if (null? breaks) own breaks))))

    ;; Where to break a line indented by `shift`, as offsets in the indented
    ;; line, when its code runs past `width`.
    (: line-breaks (-> Line String I64 (List Frame) I64 I64 (List I64)))
    (define (line-breaks line text shift frames index width)
      (match (Line-tokens line)
        ((Cons token _)
         (let ((extent (Extent text
                               (+ (token-offset token) shift)
                               (+ (Line-end line) shift)
                               width)))
           (if (and (code-mode? (Line-mode line)) (> (Extent-end extent) width))
               (chosen-breaks (line-candidates extent line shift frames index))
               (Nil))))
        ((Nil) (Nil))))

    ;; Indents each line as `indent-lines` does, first breaking it when its
    ;; code runs past `width`. The pieces of a broken line are lines in
    ;; their turn; the first is already indented.
    (: fit-lines (-> String I64 String))
    (define (fit-lines text width)
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
                          (scan-line frames (Line-tokens line) shift index)
                          (Cons indented out))
                    (loop
                     (append (map code-line (split-line indented breaks)) rest)
                     index
                     frames
                     out))))))
          ((Nil) (string-join (reverse out) "\n")))))

    (: code-line (-> String Line))
    (define (code-line text)
      (Pair-first (lex-line text (Code))))

    ;; ---- Formatting ----

    ;; Declarations first, then indentation, breaking lines past `width`.
    (: format-source (-> String I64 String))
    (define (format-source text width)
      (let* ((lines (lex text))
             (broken (string-join (break-lines lines
                                               (declaration-breaks
                                                (placed-tokens lines)))
                                  "\n")))
        (fit-lines broken width)))))
