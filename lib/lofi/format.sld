;; Indentation, formatting and highlighting of Lisp source, matching this
;; repository's formatter: Emacs's scheme-mode with the rules in
;; scripts/format-scheme.el.
;; Formatting first puts each import specification, struct field and record
;; field on its own line, then indents every line. A line's indentation
;; follows Emacs's `calculate-lisp-indent`: it goes under the first argument
;; of a call, under the first expression of the line its list's last element
;; starts on, or in by two columns for the body of a special form, as the
;; rule for the form's name says. Highlighting classes each character by the
;; same lexical rules. The IDE (src/ide/format.sld) formats on save, indents
;; a line when Tab is pressed, and highlights as the text changes.
(define-library (lofi format)
  (export
   format-source
   indent-lines
   highlight-classes)
  (import
   (lofi base))
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

    (struct Line
      ((text String)
       (mode Mode)
       (tokens (List Token))))

    ;; ---- Lexing ----

    (: lex (-> String (List Line)))
    (define (lex text)
      (let loop ((lines (split-lines text)) (mode (Code)) (out (Nil)))
        (match lines
          ((Cons line rest)
           (match (lex-line line mode)
             ((Pair tokens next) (loop rest next (Cons (Line line mode tokens) out)))))
          ((Nil) (reverse out)))))

    ;; A final newline leaves a final empty line.
    (: split-lines (-> String (List String)))
    (define (split-lines text)
      (let loop ((index (- (string-length text) 1)) (end (string-length text)) (out (Nil)))
        (cond ((< index 0) (Cons (substring text 0 end) out))
              ((= (string-ref text index) #\newline) (loop (- index 1) index (Cons (substring text (+ index 1) end) out)))
              (else (loop (- index 1) end out)))))

    ;; One step of lexing: the offset after what it read, the mode after
    ;; it, and the token it made, if any.
    (struct Step
      ((next I64)
       (mode Mode)
       (token (Option Token))))

    (: lex-line (-> String Mode (Pair (List Token) Mode)))
    (define (lex-line line mode)
      (let loop ((offset 0) (mode mode) (tokens (Nil)))
        (if (>= offset (string-length line))
            (Pair (reverse tokens) mode)
            (let ((step (lex-step line offset mode)))
              (loop (Step-next step) (Step-mode step)
                    (match (Step-token step)
                      ((Some token) (Cons token tokens))
                      ((None) tokens)))))))

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
              ((= c #\") (Step after (InString) (Some (Text offset))))
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
              ((at? line after "|") (Step (+ after 1) (InComment 1) (None)))
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
            ((= (string-ref line offset) #\\) (lex-string line (+ offset 2)))
            ((= (string-ref line offset) #\") (Step (+ offset 1) (Code) (None)))
            (else (lex-string line (+ offset 1)))))

    ;; Inside a block comment, which nests.
    (: lex-comment (-> String I64 I64 Step))
    (define (lex-comment line offset depth)
      (cond ((>= offset (string-length line)) (Step offset (InComment depth) (None)))
            ((at? line offset "|#")
             (if (= depth 1) (Step (+ offset 2) (Code) (None)) (lex-comment line (+ offset 2) (- depth 1))))
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

    ;; An open list: its parenthesis, whether a space follows it, and its
    ;; elements so far, the latest first. At the start of a line, every
    ;; element of the innermost open list is complete.
    (struct Frame
      ((column I64)
       (line I64)
       (spaced Bool)
       (elements (List Element))))

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
    ;; those scripts/format-scheme.el adds for Lofi's forms, with `guard` as
    ;; Emacs 31 indents it.
    (: rules (List (Pair String Rule)))
    (define rules
      (concatenate
       (list (map (lambda (name) (Pair name (Special 0)))
                  (list "begin" "delay" "make-environment" "match-lambda" "match-lambda*" "sequence" "with-output-to-string"))
             (map (lambda (name) (Pair name (Special 1)))
                  (list "access-components" "and-let*" "assignment-components" "call-with-input-file" "call-with-output-file"
                        "call-with-port" "call-with-values" "case" "combination-components" "comment-components"
                        "conditional-components" "declaration-components" "define-library" "define-record-type"
                        "define-values" "definition-components" "delay-components" "disjunction-components" "element"
                        "eval-when" "fluid-let" "in-package" "in-package-components" "lambda" "lambda-components"
                        "lambda-components*" "lambda-components**" "let*" "letrec" "letrec*" "letrec-syntax" "let-syntax"
                        "let*-values" "let-values" "library" "list-search-negative" "list-search-positive"
                        "list-transform-negative" "list-transform-positive" "local-declare" "macro" "make" "match-let*"
                        "match-letrec" "mode" "named-lambda" "open-block-components" "parameterize" "pathname-components"
                        "procedure-components" "root" "sequence-components" "style" "unassigned?-components"
                        "unbound?-components" "unless" "using-syntax" "variable-components" "when" "with-input-from-file"
                        "with-input-from-port" "with-input-from-string" "with-mode" "with-output-to-file"
                        "with-output-to-port" "with-syntax" "with-values" "λ"))
             (map (lambda (name) (Pair name (Special 2))) (list "do" "receive" "syntax-case" "syntax-table-define"))
             (list (Pair "dynamic-wind" (Special 3)) (Pair "let" (LetRule)) (Pair "match-let" (LetRule))
                   (Pair "syntax-rules" (Definition)))
             (map (lambda (name) (Pair name (Special 1))) (list "struct" "enum" "typeclass" "instance" "effect" "match" "guard"))
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
      (match (reverse (Frame-elements frame))
        ((Cons head rest)
         (let ((last (first-of (Frame-elements frame))))
           (match (Element-head head)
             ((Named name) (named-indent frame name rest (normal-indent frame head rest last)))
             (_ (unnamed-indent head last)))))
        ((Nil) (+ (Frame-column frame) 1))))

    (: first-of (-> (List Element) Element))
    (define (first-of elements)
      (match elements
        ((Cons element _) element)
        ((Nil) (panic "format: a list without elements"))))

    ;; The column `calculate-lisp-indent` finds before any rule applies.
    ;; While the last element is on the head's line, a line goes under the
    ;; head's first argument, or under the head if there is none or a space
    ;; follows the parenthesis; later it goes under the first expression on
    ;; the last element's line.
    (: normal-indent (-> Frame Element (List Element) Element I64))
    (define (normal-indent frame head arguments last)
      (cond ((not (= (Element-line last) (Element-line head))) (Element-first last))
            ((Frame-spaced frame) (Element-column head))
            (else (match arguments
                    ((Cons argument _) (Element-column argument))
                    ((Nil) (Element-column head))))))

    ;; A list whose head is not a name lines up with its head while its
    ;; elements share the head's line.
    (: unnamed-indent (-> Element Element I64))
    (define (unnamed-indent head last)
      (if (= (Element-line last) (Element-line head)) (Element-column head) (Element-first last)))

    (: named-indent (-> Frame String (List Element) I64 I64))
    (define (named-indent frame name arguments normal)
      (match (indent-rule name)
        ((Call) normal)
        ((Definition)
         (if (= (Element-line (first-of (Frame-elements frame))) (Frame-line frame)) (+ (Frame-column frame) 2) normal))
        ((Special distinguished) (special-indent frame distinguished (length arguments) normal))
        ((LetRule) (special-indent frame (if (names-loop? frame arguments) 2 1) (length arguments) normal))))

    ;; Emacs's `lisp-indent-specform`. A distinguished argument goes in by
    ;; four columns when it is one of the first two; the first body form goes
    ;; in by two, unless the line above sits further left.
    (: special-indent (-> Frame I64 I64 I64 I64))
    (define (special-indent frame distinguished arguments normal)
      (let ((left (- distinguished arguments)) (body (+ (Frame-column frame) 2)))
        (cond ((> left 0) (if (<= arguments 1) (+ (Frame-column frame) 4) normal))
              ((or (and (= distinguished 0) (= arguments 0)) (and (= left 0) (<= body normal))) body)
              (else normal))))

    ;; A named `let`: a name follows `let` on its line.
    (: names-loop? (-> Frame (List Element) Bool))
    (define (names-loop? frame arguments)
      (match (Pair (reverse (Frame-elements frame)) arguments)
        ((Pair (Cons head _) (Cons (Element (Named name) _ line _) _))
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
           (match (if (and (<= first index) (<= index last)) (reindent line frames) (Pair (Line-text line) 0))
             ((Pair indented shift) (loop rest (+ index 1) (scan-line frames (Line-tokens line) shift index) (Cons indented out)))))
          ((Nil) (string-join (reverse out) "\n")))))

    ;; A line's new text, and how far its tokens moved. A blank line
    ;; becomes empty; a line inside a string or block comment, or one that
    ;; starts with three semicolons, stays as it is.
    (: reindent (-> Line (List Frame) (Pair String I64)))
    (define (reindent line frames)
      (let* ((text (Line-text line)) (start (indentation text)) (rest (substring text start (string-length text))))
        (cond ((not (code-mode? (Line-mode line))) (Pair text 0))
              ((string=? rest "") (Pair "" 0))
              ((at? rest 0 ";;;") (Pair text 0))
              (else (let ((column (stack-indent frames)))
                      (Pair (string-append (make-string column #\space) rest) (- column start)))))))

    (: indentation (-> String I64))
    (define (indentation text)
      (let loop ((index 0))
        (if (and (< index (string-length text)) (member? (string-ref text index) (list #\space #\tab))) (loop (+ index 1)) index)))

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
      (Scan-frames (fold-left (lambda (scan token) (scan-token scan token shift line)) (Scan frames (None) (None)) tokens)))

    (: scan-token (-> Scan Token I64 I64 Scan))
    (define (scan-token scan token shift line)
      (match token
        ((Open offset spaced)
         (let ((added (add-expression scan (Listed) (+ offset shift) line)))
           (Scan-frames-set added (Cons (Frame (+ offset shift) line spaced (Nil)) (Scan-frames added)))))
        ((Close _) (Scan-frames-set scan (drop (Scan-frames scan) 1)))
        ((Prefix offset) (Scan (Scan-frames scan) (Some (or-else (Scan-first scan) (+ offset shift)))
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
        (Scan (add-element (Scan-frames scan) (Element head start line first)) (Some first) (None))))

    (: add-element (-> (List Frame) Element (List Frame)))
    (define (add-element frames element)
      (match frames
        ((Cons frame rest) (Cons (Frame-elements-set frame (Cons element (Frame-elements frame))) rest))
        ((Nil) (Nil))))

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
      (list->vector (concatenate (map-indexed (lambda (index line) (map (lambda (token) (Placed index token)) (Line-tokens line)))
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
      (if (or (= index 0) (not (= (Placed-line (vector-ref tokens (- index 1))) (Placed-line (vector-ref tokens index)))))
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
                 ((Found found #t) (loop (or-else (expression-end tokens index) (vector-length tokens)) found))
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
             (loop rest (+ index 1) (drop breaks (length here)) (append (reverse (split-line (Line-text line) here)) out))))
          ((Nil) (reverse out)))))

    (: line-offsets (-> (List Placed) I64 (List I64)))
    (define (line-offsets breaks index)
      (match breaks
        ((Cons placed rest)
         (if (= (Placed-line placed) index) (Cons (token-offset (Placed-token placed)) (line-offsets rest index)) (Nil)))
        ((Nil) (Nil))))

    (: split-line (-> String (List I64) (List String)))
    (define (split-line text offsets)
      (let loop ((start 0) (offsets offsets) (out (Nil)))
        (match offsets
          ((Cons offset rest) (loop offset rest (Cons (trim-right (substring text start offset)) out)))
          ((Nil) (reverse (Cons (substring text start (string-length text)) out))))))

    (: trim-right (-> String String))
    (define (trim-right text)
      (let loop ((end (string-length text)))
        (if (and (> end 0) (member? (string-ref text (- end 1)) (list #\space #\tab))) (loop (- end 1)) (substring text 0 end))))

    ;; ---- Highlighting ----

    ;; Whether the next name is one a definition introduces: after `(define`,
    ;; `(define-syntax` or `(:`, the next name, or the first name of the next
    ;; list.
    (enum Naming
      (Plain)
      (Opened)
      (Defining)
      (DefiningList))

    ;; A run of characters of one class, and the naming after it.
    (struct Run
      ((end I64)
       (class Char)
       (naming Naming)))

    ;; The class of each character, for an editor to color: `c` a comment,
    ;; `s` a string, `h` a character, `n` a number, `b` a boolean, `k` a core
    ;; form or derived syntax, `t` a type or constructor, whose names are
    ;; capitalized, `d` the name a definition introduces, `p` a parenthesis,
    ;; `q` a quotation prefix, and `.` anything else. Strings and block
    ;; comments may span lines.
    (: highlight-classes (-> String String))
    (define (highlight-classes text)
      (let loop ((offset 0) (naming (Plain)) (out (Nil)))
        (if (>= offset (string-length text))
            (string-concatenate (reverse out))
            (let ((run (highlight-run text offset naming)))
              (loop (Run-end run) (Run-naming run) (Cons (make-string (- (Run-end run) offset) (Run-class run)) out))))))

    (: highlight-run (-> String I64 Naming Run))
    (define (highlight-run text offset naming)
      (let ((c (string-ref text offset)) (after (+ offset 1)))
        (cond ((char-whitespace? c) (Run after #\. naming))
              ((= c #\;) (Run (text-line-end text offset) #\c naming))
              ((at? text offset "#|") (Run (block-comment-end text (+ offset 2) 1) #\c naming))
              ((= c #\") (Run (string-end text after) #\s (Plain)))
              ((or (= c #\() (= c #\[)) (Run after #\p (if (defining? naming) (DefiningList) (Opened))))
              ((or (= c #\)) (= c #\])) (Run after #\p (Plain)))
              ((member? c (list #\' #\` #\,)) (Run after #\q naming))
              ((at? text offset "#\\") (Run (atom-end text (min (+ offset 3) (string-length text))) #\h (Plain)))
              ((or (at? text offset "#(") (at? text offset "#;")) (Run after #\q naming))
              (else (atom-run text offset (atom-end text after) naming)))))

    (: atom-run (-> String I64 I64 Naming Run))
    (define (atom-run text start end naming)
      (let ((name (substring text start end)))
        (cond ((defining? naming) (Run end #\d (Plain)))
              ((and (opened? naming) (member? name (list "define" "define-syntax" ":"))) (Run end #\k (Defining)))
              (else (Run end (atom-class name) (Plain))))))

    (: atom-class (-> String Char))
    (define (atom-class name)
      (let ((first (string-ref name 0)))
        (cond ((member? name (list "#t" "#f" "#true" "#false")) #\b)
              ((or (char-numeric? first) (and (> (string-length name) 1) (member? first (list #\+ #\- #\.))
                                              (char-numeric? (string-ref name 1))))
               #\n)
              ((member? name keywords) #\k)
              ((and (not (char<? first #\A)) (not (char<? #\Z first))) #\t)
              (else #\.))))

    ;; The core forms, (lofi base)'s derived syntax, and the words of
    ;; libraries, signatures and declarations.
    (: keywords (List String))
    (define keywords
      (list "define" "lambda" "if" "begin" "let" "define-syntax" "syntax-rules" "quote" ":" "struct" "enum" "type" "typeclass"
            "instance" "match" "ann" "type-convert" "extern" "effect" "handle" "expose" "case-id" "let*" "letrec" "cond" "case"
            "when" "unless" "and" "or" "do" "else" "define-library" "import" "export" "only" "except" "prefix" "rename"
            "All" "requires" "deriving" "host" "->" "!" "define-application" "define-record-type" "guard"))

    (: defining? (-> Naming Bool))
    (define (defining? naming)
      (match naming
        ((Defining) #t)
        ((DefiningList) #t)
        (_ #f)))

    (: opened? (-> Naming Bool))
    (define (opened? naming)
      (match naming
        ((Opened) #t)
        (_ #f)))

    (: text-line-end (-> String I64 I64))
    (define (text-line-end text offset)
      (if (or (>= offset (string-length text)) (= (string-ref text offset) #\newline)) offset (text-line-end text (+ offset 1))))

    (: string-end (-> String I64 I64))
    (define (string-end text offset)
      (cond ((>= offset (string-length text)) offset)
            ((= (string-ref text offset) #\\) (string-end text (min (+ offset 2) (string-length text))))
            ((= (string-ref text offset) #\") (+ offset 1))
            (else (string-end text (+ offset 1)))))

    (: block-comment-end (-> String I64 I64 I64))
    (define (block-comment-end text offset depth)
      (cond ((or (= depth 0) (>= offset (string-length text))) offset)
            ((at? text offset "|#") (block-comment-end text (+ offset 2) (- depth 1)))
            ((at? text offset "#|") (block-comment-end text (+ offset 2) (+ depth 1)))
            (else (block-comment-end text (+ offset 1) depth))))

    ;; ---- Formatting ----

    (: format-source (-> String String))
    (define (format-source text)
      (let* ((lines (lex text)) (broken (string-join (break-lines lines (declaration-breaks (placed-tokens lines))) "\n")))
        (indent-lines broken 0 (string-length broken))))))
