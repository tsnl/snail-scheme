;; Compile an Ink conversation in a generate-library producer. Each choice
;; path runs through the reference player. Only the resulting dialogue is
;; imported by the game.
(define-library (snail shell game ink)
  (export ink-library)
  (import
   (snail core base)
   (snail core io)
   (snail shell json)
   (snail shell json read)
   (snail shell process)
   (snail shell resource)
   (snail shell syntax)
   (snail shell utf8)
   (snail shell game dialogue))
  (begin

    ;; ---- Recipe inputs ----

    ;; The first file is the story. Additional files keep their paths for
    ;; Ink INCLUDE. Each literal belongs to the recipe's dependency closure.
    (define-syntax ink-library
      (syntax-rules (max-turns)
        ((_ arguments fs processes resources name (max-turns limit) entry include ...)
         (compile-library arguments fs processes name limit
                          (list (new Pair
                                  (first entry)
                                  (second (read-resource resources (link-file entry))))
                                (new Pair
                                  (first include)
                                  (second (read-resource resources (link-file include))))
                                ...)))
        ((_ arguments fs processes resources name entry include ...)
         (ink-library arguments fs processes resources name (max-turns 256) entry include ...))))

    (define (split (text String) (separator Char)) (→ (List String))
      (let loop ((start 0) (i 0) (parts (Nil)))
        (cond ((= i (string-length text)) (reverse (Cons (substring text start i) parts)))
              ((char=? (string-ref text i) separator)
               (loop (+ i 1) (+ i 1) (Cons (substring text start i) parts)))
              (else (loop start (+ 1 i) parts)))))
    (define (trim (s String)) (→ String)
      (let loop ((a 0) (b (string-length s)))
        (cond ((= a b) "") ((char-whitespace? (string-ref s a)) (loop (+ a 1) b))
              ((char-whitespace? (string-ref s (- b 1))) (loop a (- b 1)))
              (else (substring s a b)))))
    (define (utf8 (b Bytes)) (→ String)
      (match (utf8->string b) ((Ok text) text) ((Err _) (panic "Ink expected UTF-8"))))
    (define (directory! (fs Fs) (path String)) (→ Unit)
      (match (make-directories fs path) ((Ok _) (unit))
             ((Err _) (panic (string-append "cannot create Ink build directory " path)))))
    (define (stage-source! (fs Fs) (work String) (source (Pair String Bytes))) (→ Unit)
      (let loop ((directory work) (parts (split (● source first) #\/)))
        (match parts
          ((Cons "." (Cons part rest)) (loop directory (Cons part rest)))
          ((Cons part rest)
           (when (member? part (list "" "." ".."))
             (panic (string-append "invalid Ink source path " (● source first))))
           (let ((path (string-append directory "/" part)))
             (if (null? rest) (write-bytes fs path (● source second))
                 (begin (directory! fs path) (loop path rest)))))
          ((Nil) (panic "missing Ink source name")))))

    ;; ---- Reference compiler and player ----

    (define (ink-command (processes Processes) (work String) (args (List String)) (input String))
      (→ String)
      ;; A divert can loop forever before the player reaches a choice.
      (let ((command (new Command (directory work) (program "timeout")
                          (arguments (append (list "30" "inklecate") args)))))
        (match ((● processes run) command (string->utf8 input))
          ((Err e) (panic (string-append "cannot run inklecate: " (● e code))))
          ((Ok result) (match (● result exit)
                         ((Exited 0) (utf8 (● result stdout)))
                         ((Exited 124) (panic "inklecate timed out after 30 seconds"))
                         (_ (panic (string-append "inklecate failed: "
                                                  (utf8 (● result stdout))
                                                  (utf8 (● result stderr))))))))))

    (define (required (object Json) (key String)) (→ Json)
      (match (json-member object key) ((Some value) value)
             (_ (panic (string-append "Ink JSON is missing " key)))))
    (define (items (value Json)) (→ (List Json))
      (match value ((JsonArray xs) xs) (_ (panic "Ink expected a JSON array"))))
    (define (text-of (value Json)) (→ String)
      (match value ((JsonString s) s) (_ (panic "Ink expected a JSON string"))))

    ;; Ink format 21 distinguishes prose (prefixed with ^), bare commands
    ;; and objects which name nested containers or an external function.
    (define (check-commands (value Json)) (→ Unit)
      (match value
        ((JsonString op) (when (member? op (list "rnd" "srnd" "lrnd" "seq"))
                           (panic "random output and shuffle sequences need a live Ink runtime")))
        ((JsonArray xs) (for-each check-commands xs))
        ((JsonObject members)
         (match (json-member value "x()")
           ((Some fn) (panic (string-append "EXTERNAL " (text-of fn) " needs a live Ink runtime")))
           (_ (for-each (lambda (field) (match (● field second)
                                          ((JsonArray _) (check-commands (● field second)))
                                          (_ (unit))))
                        members))))
        (_ (unit))))
    (define (compile-story! (fs Fs) (processes Processes) (work String) (entry String)) (→ Unit)
      (let* ((path (string-append work "/story.json"))
             (report
              (ink-command processes work (list "-o" path (string-append "inputs/" entry)) ""))
             (raw (if (file-exists? fs path) (read-file fs path)
                      (panic (string-append "inklecate failed: " report))))
             (json (if (and (> (string-length raw) 0) (= (char->integer (string-ref raw 0)) 65279))
                       (substring raw 1 (string-length raw)) raw)))
        (match (string->json json)
          ((Some story)
           (match (required story "inkVersion")
             ((JsonInteger 21) (check-commands (required story "root")))
             (_ (panic "expected Ink format 21 (inklecate 1.2.1)"))))
          (_ (panic "inklecate did not produce a JSON story")))))

    (record Turn
      ((lines (List String))
       (choices (List String))
       (ids (List String))))
    (define empty-turn (→ Turn) (new Turn (lines (Nil)) (choices (Nil)) (ids (Nil))))
    (define (id-tags (tags Json)) (→ (List String))
      (fold-right (lambda (tag ids)
                    (let ((s (text-of tag)))
                      (if (and (>= (string-length s) 3) (string=? (substring s 0 3) "id:"))
                          (Cons (trim (substring s 3 (string-length s))) ids) ids)))
                  (Nil) (items tags)))
    (define (spoken-lines (text String)) (→ (List String))
      (let ((lines (reverse (split text #\newline))))
        (reverse (match lines ((Cons "" rest) rest) (_ lines)))))

    ;; At EOF the CLI reports either the next choice or the end of the
    ;; story. A needInput message closes each choice-bearing turn.
    (define (play-turn (processes Processes) (work String) (path (List I64))) (→ Turn)
      (let* ((input (string-concatenate (map (lambda (i) (string-append (show i) "\n")) path)))
             (out (ink-command processes work (list "-p" "-j" "story.json") input)))
        (match (string->json-values out)
          ((Some messages) (read-turn messages (length path) empty-turn))
          (_ (panic "inklecate returned an invalid JSON transcript")))))
    (define (apply-message (turn Turn) (key String) (value Json)) (→ Turn)
      (match key
        ("text" (Turn-lines-set turn (append (● turn lines) (spoken-lines (text-of value)))))
        ("tags" (Turn-ids-set turn (append (● turn ids) (id-tags value))))
        ("choices" (let ((labels (map (lambda (c) (text-of (required c "text"))) (items value))))
                     (Turn-choices-set turn labels)))
        ("issues" (unless (null? (items value)) (panic (json->string value))) turn)
        ("compile-success"
         (match value ((JsonBool #t) turn) (_ (panic "inklecate could not load its story"))))
        ("error" (panic (json->string value)))
        ("cmdOutput" (panic (json->string value)))
        (_ turn)))
    (define (read-turn (messages (List Json)) (skip I64) (turn Turn)) (→ Turn)
      (match messages
        ((Nil) (if (= skip 0) turn (panic "Ink could not replay a choice path")))
        ((Cons (JsonObject (Cons (Pair "needInput" (JsonBool #t)) _)) rest)
         (if (= skip 0) turn (read-turn rest (- skip 1) empty-turn)))
        ((Cons (JsonObject (Cons (Pair key value) _)) rest)
         (read-turn rest skip (apply-message turn key value)))
        (_ (panic "invalid Ink play message"))))

    ;; ---- Finite choice histories ----

    (define (passage-id (turn Turn) (at String)) (→ String)
      (match (● turn ids)
        ((Nil) at)
        ((Cons id (Nil)) (if (string=? id "") (panic "empty Ink save id") id))
        (_ (panic "expected one Ink save id per turn"))))

    ;; Two histories can reach one tagged passage only if their observable
    ;; text and all their outgoing destinations agree.
    (define (same-list? (same? (Fn A A → Bool)) (xs (List A)) (ys (List A))) (→ Bool) (∀ (A))
      (match (new Pair (first xs) (second ys))
        ((Pair (Nil) (Nil)) #t)
        ((Pair (Cons x more) (Cons y others)) (and (same? x y) (same-list? same? more others)))
        (_ #f)))
    (define (remember (page Passage) (pages (List Passage))) (→ (List Passage))
      (match (find (lambda (p) (string=? (● p id) (● page id))) pages)
        ((None) (Cons page pages))
        ((Some old)
         (unless (and (same-list? string=? (● old lines) (● page lines))
                      (same-list? (lambda (a b)
                                    (and (string=? (● a text) (● b text))
                                         (string=? (● a next) (● b next))))
                                  (● old choices) (● page choices)))
           (panic (string-append "save id names different dialogue states: " (● page id))))
         pages)))

    (record History
      ((choices (List I64))
       (parents (List String))))
    (record Seen
      ((address String)
       (id String)
       (turn Turn)))

    (define (address (path (List I64))) (→ String)
      (string-concatenate (Cons "start" (map (lambda (i) (string-append "." (show i))) path))))
    ;; Visit breadth first, as choices are printed. Reserve their paths in
    ;; the budget before starting any more inklecate processes.
    (define (explore (processes Processes) (work String) (limit I64)) (→ (List Seen))
      (let loop ((queue (list (new History (choices (Nil)) (parents (Nil)))))
                 (count 1)
                 (seen (Nil)))
        (match queue
          ((Nil) (reverse seen))
          ((Cons history rest)
           (let* ((path (● history choices)) (turn (play-turn processes work path))
                  (at (address path)) (id (passage-id turn at))
                  (total (+ count (length (● turn choices)))))
             (when (member? id (● history parents)) (panic (string-append "cyclic passage: " id)))
             (when (> total limit)
               (panic (string-append "Ink conversation exceeds " (show limit) " turns at " at)))
             (let ((children
                    (map-indexed (lambda (i _) (new History (choices (append path (list (+ i 1))))
                                                    (parents (Cons id (● history parents)))))
                                 (● turn choices))))
               (loop (append rest children)
                     total
                     (Cons (new Seen (address at) (id id) (turn turn)) seen))))))))
    (define (resolve-page (node Seen) (names (List (Pair String String)))) (→ Passage)
      (let ((options (map-indexed
                      (lambda (i label)
                        (let ((at (string-append (● node address) "." (show (+ i 1)))))
                          (match (assoc-ref names at)
                            ((Some id) (new Reply (text label) (next id)))
                            (_ (panic (string-append "missing Ink choice " at))))))
                      (● node turn choices))))
        (new Passage (id (● node id)) (lines (● node turn lines)) (choices options))))
    (define (passages (seen (List Seen))) (→ (List Passage))
      (let ((names
             (map (lambda (node) (new Pair (first (● node address)) (second (● node id)))) seen)))
        (reverse
         (fold-left (lambda (pages node) (remember (resolve-page node names) pages)) (Nil) seen))))

    ;; ---- Typed library output ----

    (define (listing (xs (List Syntax))) (→ Syntax)
      (if (null? xs) (form "Nil" (Nil)) (form "list" xs)))
    (define (reply-syntax (r Reply)) (→ Syntax)
      (form "new" (list (SymbolSyntax "Reply") (form "text" (list (StringSyntax (● r text))))
                        (form "next" (list (StringSyntax (● r next)))))))
    (define (page-syntax (p Passage)) (→ Syntax)
      (form "new" (list (SymbolSyntax "Passage") (form "id" (list (StringSyntax (● p id))))
                        (form "lines" (list (listing (map StringSyntax (● p lines)))))
                        (form "choices" (list (listing (map reply-syntax (● p choices))))))))
    (define (dialogue-library (name (List String)) (start String) (pages (List Passage))) (→ Syntax)
      (let ((value
             (form "new" (list (SymbolSyntax "Dialogue") (form "start" (list (StringSyntax start)))
                               (form "pages" (list (listing (map page-syntax pages))))))))
        (library-syntax name (list "conversation")
                        (list (list "snail" "core" "base") (list "snail" "shell" "game" "dialogue"))
                        (list (form "define"
                                    (list (SymbolSyntax "conversation")
                                          (form "→" (list (SymbolSyntax "Dialogue")))
                                          value))))))

    ;; A producer runs in the caller's workspace. Its output path names
    ;; private scratch owned and cleaned by this build, including on failure.
    (define (compile-library (arguments Arguments)
                             (fs Fs)
                             (processes Processes)
                             (name (List String))
                             (limit I64)
                             (sources (List (Pair String Bytes))))
      (→ Syntax)
      (let* ((work (string-append (list-ref (command-line arguments) 1)
                                  ".ink-work"))
             (inputs (string-append work "/inputs")))
        (directory! fs inputs)
        (for-each (lambda (source) (stage-source! fs inputs source)) sources)
        (compile-story! fs processes work (● (list-ref sources 0) first))
        (let ((seen (explore processes work limit)))
          (dialogue-library name
                            (● (list-ref seen 0) id)
                            (passages seen)))))))
