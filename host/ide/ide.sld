;; The editor `snail dev` serves: a client of one native project, written
;; as a document interface ((snail shell ui)) that `define-ui` hosts in the
;; page. Disk owns saved files and buffers own drafts. The service
;; (src/snail/shell/project/service.sld) answers for the project's listing
;; and its files, and its event stream reports the compiler's status, the
;; run targets' processes, and that files changed.
;;
;; A reply can arrive after newer evidence, so each observation remembers
;; when it was asked for and counts only while nothing newer has been: a
;; read carries its buffer's read sequence, a listing the project's, and a
;; diagnostic's point the read that confirmed the text it was made from.
;; tests/browser/ide.mjs and tests/browser/ide-runs.mjs drive it against a
;; real `snail dev`.
(import
 (snail core base)
 (snail shell utf8)
 (only (snail shell task) tasks)
 (snail shell dom)
 (snail shell fetch)
 (snail shell json)
 (snail shell json read)
 (snail shell format)
 (snail shell highlight)
 (snail shell ui)
 (snail shell ui page))

;; ---- Text ----

;; Offsets count scalars, as the dom effect's do.

(: newline-text String)
(define newline-text (make-string 1 #\newline))

(: starts-with? (-> String String Bool))
(define (starts-with? text prefix)
  (and (>= (string-length text) (string-length prefix))
       (string=? (substring text 0 (string-length prefix)) prefix)))

(: ends-with? (-> String String Bool))
(define (ends-with? text suffix)
  (let ((length (string-length text)) (size (string-length suffix)))
    (and (>= length size) (string=? (substring text (- length size) length) suffix))))

;; The last newline at or before `index`, or -1.
(: newline-before (-> String I64 I64))
(define (newline-before text index)
  (let loop ((at (min index (- (string-length text) 1))))
    (cond ((< at 0) -1)
          ((char=? (string-ref text at) #\newline) at)
          (else (loop (- at 1))))))

;; Where the line holding `index` starts.
(: line-start (-> String I64 I64))
(define (line-start text index)
  (+ (newline-before text (- index 1)) 1))

;; Where the line holding `index` ends: its newline, or the text's end.
(: line-end (-> String I64 I64))
(define (line-end text index)
  (let loop ((at (max index 0)))
    (cond ((>= at (string-length text)) (string-length text))
          ((char=? (string-ref text at) #\newline) at)
          (else (loop (+ at 1))))))

;; Where line `line`, counting from 1, starts, or the text's end.
(: line-offset (-> String I64 I64))
(define (line-offset text line)
  (let loop ((offset 0) (number 1))
    (if (>= number line)
        offset
        (let ((end (line-end text offset)))
          (if (>= end (string-length text)) end (loop (+ end 1) (+ number 1)))))))

;; The newlines from `from` up to `to`.
(: count-lines (-> String I64 I64 I64))
(define (count-lines text from to)
  (let loop ((at from) (count 0))
    (cond ((>= at to) count)
          ((char=? (string-ref text at) #\newline) (loop (+ at 1) (+ count 1)))
          (else (loop (+ at 1) count)))))

(: blank? (-> Char Bool))
(define (blank? char)
  (or (char=? char #\space) (char=? char #\tab)))

;; How many spaces and tabs run from `index`.
(: indentation (-> String I64 I64))
(define (indentation text index)
  (let loop ((at index))
    (if (and (< at (string-length text)) (blank? (string-ref text at)))
        (loop (+ at 1))
        (- at index))))

(: spaces (-> I64 String))
(define (spaces count)
  (make-string count #\space))

;; The lines of a text, without their newlines.
(: lines-of (-> String (List String)))
(define (lines-of text)
  (let loop ((end (string-length text)) (index (- (string-length text) 1)) (lines (Nil)))
    (cond ((< index 0) (Cons (substring text 0 end) lines))
          ((char=? (string-ref text index) #\newline)
           (loop index (- index 1) (Cons (substring text (+ index 1) end) lines)))
          (else (loop end (- index 1) lines)))))

;; Lines `first` to `last` of a text, counting from 0, as one text.
(: lines-between (-> String I64 I64 String))
(define (lines-between text first last)
  (string-join (take (list-tail (lines-of text) first) (+ (- last first) 1)) newline-text))

;; The text a field shows, which keeps only newlines of a file's line
;; ends.
(: display-text (-> String String))
(define (display-text text)
  (match (string-index text #\return)
    ((Some _)
     (let loop ((chars (string->list text)) (shown (Nil)))
       (match chars
         ((Cons #\return (Cons #\newline rest)) (loop rest (Cons #\newline shown)))
         ((Cons #\return rest) (loop rest (Cons #\newline shown)))
         ((Cons char rest) (loop rest (Cons char shown)))
         ((Nil) (list->string (reverse shown))))))
    ((None) text)))

;; The length of the longest line.
(: longest-line (-> String I64))
(define (longest-line text)
  (let loop ((at 0) (longest 0))
    (if (> at (string-length text))
        longest
        (let ((end (line-end text at))) (loop (+ end 1) (max longest (- end at)))))))

;; ---- Editing ----

;; An edit to a field, as typing would make it: the range it replaces,
;; what replaces it, and the selection after. One that replaces nothing
;; with nothing only selects.
(struct Change
  ((start I64)
   (end I64)
   (text String)
   (selection-start I64)
   (selection-end I64)))

;; Makes the change in the field, so the page can undo it, and answers
;; whether the field took it; one it did not take leaves the selection.
(: apply-change (-> Node Change Bool ! dom))
(define (apply-change field change)
  (let ((taken (or (and (= (Change-start change) (Change-end change))
                        (string=? (Change-text change) ""))
                   (insert-text field
                                (i64->i32 (Change-start change))
                                (i64->i32 (Change-end change))
                                (Change-text change)))))
    (when taken
      (select-range field
                    (i64->i32 (Change-selection-start change))
                    (i64->i32 (Change-selection-end change))))
    taken))

;; Tab reindents the caret's line, or every line the selection touches but
;; a last one it only reaches the start of. As in Emacs, a caret in the
;; indentation moves to the line's first character, and a caret in the
;; text stays with it; a selection then selects the lines.
(: indent-change (-> String I64 I64 Change))
(define (indent-change text from selected-to)
  (let* ((to (if (and (> selected-to from) (char=? (string-ref text (- selected-to 1)) #\newline))
                 (- selected-to 1)
                 selected-to))
         (start (line-start text from))
         (end (line-end text to))
         (lines (reindented text from to start end))
         (same (string=? lines (substring text start end)))
         (before (indentation text start))
         (after (indentation lines 0))
         (column (- from start))
         (caret (+ start (if (<= column before) after (- (+ column after) before)))))
    (Change start
            (if same start end)
            (if same "" lines)
            (if (= from to) caret start)
            (if (= from to) caret (+ start (string-length lines))))))

;; The lines from `start` to `end` reindented. The formatter reads them
;; from the start of their top-level form; a blank line holding the caret
;; gets the indentation it would have with something on it.
(: reindented (-> String I64 I64 I64 I64 String))
(define (reindented text from to start end)
  (if (and (= from to) (= (indentation text start) (- end start)))
      (spaces (line-indentation text start))
      (let* ((base (form-start text start))
             (first (count-lines text base start))
             (last (+ first (count-lines text start end))))
        (lines-between (indent-lines (substring text base end) first last) first last))))

;; The column the line at `start` would be indented to, found by putting
;; a placeholder on it, since a formatted blank line stays empty.
(: line-indentation (-> String I64 I64))
(define (line-indentation text start)
  (let* ((placed (string-append (substring text 0 start)
                                "x"
                                (substring text
                                           (+ start (indentation text start))
                                           (string-length text))))
         (end (line-end placed start))
         (base (form-start placed start))
         (line (count-lines placed base start)))
    (indentation (lines-between (indent-lines (substring placed base end) line line) line line) 0)))

;; Emacs takes a top-level form to start at a line that opens a list in
;; its first column, looking above the line it indents, so that line may
;; belong to the form before it.
(: form-start (-> String I64 I64))
(define (form-start text start)
  (if (> start 0) (top-level-start text (line-start text (- start 1))) 0))

;; The start of the line at or above `start` that opens a list in its
;; first column, or of the text.
(: top-level-start (-> String I64 I64))
(define (top-level-start text start)
  (if (or (= start 0) (and (< start (string-length text)) (char=? (string-ref text start) #\()))
      start
      (top-level-start text (line-start text (- start 1)))))

;; Enter starts a new line indented for what follows the caret, and, as
;; Emacs's electric indentation does, drops the spaces it leaves at the
;; end of the line before.
(: newline-change (-> String I64 I64 Change))
(define (newline-change text from to)
  (let* ((start (trailing-start text from))
         (skip (indentation text to))
         (joined (string-append (substring text 0 start)
                                newline-text
                                (substring text (+ to skip) (string-length text))))
         (indent (line-indentation joined (+ start 1)))
         (caret (+ (+ start 1) indent)))
    (Change start (+ to skip) (string-append newline-text (spaces indent)) caret caret)))

;; Where the spaces and tabs just before `index` start.
(: trailing-start (-> String I64 I64))
(define (trailing-start text index)
  (if (and (> index 0) (blank? (string-ref text (- index 1))))
      (trailing-start text (- index 1))
      index))

;; Formatting replaces only what changed, and the caret keeps its line and
;; its place after the line's indentation.
(: format-change (-> String String I64 Change))
(define (format-change text formatted caret)
  (let* ((line (count-lines text 0 caret))
         (start (line-start text caret))
         (past (- (- caret start) (indentation text start)))
         (prefix (shared-prefix text formatted))
         (suffix (shared-suffix text formatted prefix))
         (at (line-offset formatted (+ line 1)))
         (moved (min (+ (+ at (indentation formatted at)) (max 0 past)) (line-end formatted at))))
    (Change prefix
            (- (string-length text) suffix)
            (substring formatted prefix (- (string-length formatted) suffix))
            moved
            moved)))

;; How many scalars two texts share at their start, and then, of what
;; follows that, at their end.
(: shared-prefix (-> String String I64))
(define (shared-prefix a b)
  (let loop ((at 0))
    (if (and (< at (string-length a))
             (< at (string-length b))
             (char=? (string-ref a at) (string-ref b at)))
        (loop (+ at 1))
        at)))

(: shared-suffix (-> String String I64 I64))
(define (shared-suffix a b prefix)
  (let loop ((count 0))
    (if (and (< count (- (string-length a) prefix))
             (< count (- (string-length b) prefix))
             (char=? (string-ref a (- (string-length a) (+ count 1)))
                     (string-ref b (- (string-length b) (+ count 1)))))
        (loop (+ count 1))
        count)))

;; ---- Buffers ----

;; A file's text as disk had it when a read or save saw it, and the
;; revision the service gave that text.
(struct Snapshot
  ((text String)
   (revision String)))

;; An open file: its draft, and the disk contents it was made from, none
;; until a read has accepted some; the revision disk was last seen at,
;; none before the first read and once a read found the file gone;
;; whether a save is in flight; the sequence of its latest read; what that
;; read found wrong; and what the last save, format or reload did wrong.
(struct Buffer
  ((path String)
   (text String)
   (baseline (Option Snapshot))
   (observed (Option String))
   (saving Bool)
   (read I64)
   (problem String)
   (failure String)))

(: new-buffer (-> String Buffer))
(define (new-buffer path)
  (Buffer path "" (None) (None) #f 0 "" ""))

;; The draft has changes of its own.
(: dirty? (-> Buffer Bool))
(define (dirty? buffer)
  (match (Buffer-baseline buffer)
    ((Some baseline) (not (string=? (Buffer-text buffer) (Snapshot-text baseline))))
    ((None) #f)))

;; Disk has moved on from the contents the draft was made from.
(: conflict? (-> Buffer Bool))
(define (conflict? buffer)
  (match (Pair (Buffer-baseline buffer) (Buffer-observed buffer))
    ((Pair (Some baseline) (Some revision)) (not (string=? revision (Snapshot-revision baseline))))
    ((Pair (Some _) (None)) #t)
    (_ #f)))

(: loaded? (-> Buffer Bool))
(define (loaded? buffer)
  (match (Buffer-baseline buffer)
    ((Some _) #t)
    ((None) #f)))

;; The compiler reads Scheme sources, which the editor indents, formats
;; and colors.
(: source-file? (-> String Bool))
(define (source-file? path)
  (any? (lambda (extension) (ends-with? path extension)) (list ".sld" ".scm" ".datum")))

;; ---- Panes ----

;; An editor pane: the file it shows, none when it is empty, and how far
;; its text is scrolled, which places the lines its highlighting draws.
(struct Pane
  ((id I64)
   (path (Option String))
   (scroll F64)))

;; How the panes share the room: one pane, or two nodes side by side
;; (`row`) or one above the other (`column`), the first taking `ratio` of
;; the room. A split has an id of its own, for dragging its divider.
(enum Layout
  (Leaf ((pane I64)))
  (Split ((id I64)
          (direction String)
          (ratio F64)
          (first Layout)
          (second Layout))))

(: leaf? (-> Layout I64 Bool))
(define (leaf? layout pane)
  (match layout
    ((Leaf id) (= id pane))
    (_ #f)))

;; The layout with the leaf of `pane` replaced by `replacement`.
(: leaf-replaced (-> Layout I64 Layout Layout))
(define (leaf-replaced layout pane replacement)
  (match layout
    ((Leaf id) (if (= id pane) replacement layout))
    ((Split id direction ratio first second)
     (Split id
            direction
            ratio
            (leaf-replaced first pane replacement)
            (leaf-replaced second pane replacement)))))

;; The node beside the leaf of `pane` in its split, if it is in one.
(: sibling (-> Layout I64 (Option Layout)))
(define (sibling layout pane)
  (match layout
    ((Leaf _) (None))
    ((Split _ _ _ first second)
     (cond ((leaf? first pane) (Some second))
           ((leaf? second pane) (Some first))
           (else (match (sibling first pane)
                   ((Some found) (Some found))
                   ((None) (sibling second pane))))))))

;; The layout without the leaf of `pane`, its sibling in its split's place.
(: without-leaf (-> Layout I64 Layout))
(define (without-leaf layout pane)
  (match layout
    ((Leaf _) layout)
    ((Split id direction ratio first second)
     (cond ((leaf? first pane) second)
           ((leaf? second pane) first)
           (else
            (Split id direction ratio (without-leaf first pane) (without-leaf second pane)))))))

(: first-leaf (-> Layout I64))
(define (first-leaf layout)
  (match layout
    ((Leaf id) id)
    ((Split _ _ _ first _) (first-leaf first))))

;; ---- Placing panes ----

;; A part of the panes' room, in fractions of it.
(struct Area
  ((left F64)
   (top F64)
   (width F64)
   (height F64)))

(: whole Area)
(define whole
  (Area 0.0 0.0 1.0 1.0))

;; The two parts of `area` a split in `direction` at `ratio` makes.
(: halves (-> Area String F64 (Pair Area Area)))
(define (halves area direction ratio)
  (if (string=? direction "column")
      (let ((first (* (Area-height area) ratio)))
        (Pair (Area-height-set area first)
              (Area (Area-left area)
                    (+ (Area-top area) first)
                    (Area-width area)
                    (- (Area-height area) first))))
      (let ((first (* (Area-width area) ratio)))
        (Pair (Area-width-set area first)
              (Area (+ (Area-left area) first)
                    (Area-top area)
                    (- (Area-width area) first)
                    (Area-height area))))))

;; Each pane's part of `area`, by the pane's id.
(: pane-areas (-> Layout Area (List (Pair I64 Area))))
(define (pane-areas layout area)
  (match layout
    ((Leaf id) (list (Pair id area)))
    ((Split _ direction ratio first second)
     (match (halves area direction ratio)
       ((Pair one other) (append (pane-areas first one) (pane-areas second other)))))))

;; A split, by its id, with its direction and ratio and the part of the
;; room it divides.
(struct Division
  ((split I64)
   (direction String)
   (ratio F64)
   (area Area)))

(: divisions (-> Layout Area (List Division)))
(define (divisions layout area)
  (match layout
    ((Leaf _) (Nil))
    ((Split id direction ratio first second)
     (match (halves area direction ratio)
       ((Pair one other)
        (Cons (Division id direction ratio area)
              (append (divisions first one) (divisions second other))))))))

(: division-of (-> Layout I64 (Option Division)))
(define (division-of layout split)
  (find (lambda (division) (= (Division-split division) split)) (divisions layout whole)))

;; The layout with split `split` dividing at `ratio`, kept to a tenth of
;; the room either side.
(: ratio-set (-> Layout I64 F64 Layout))
(define (ratio-set layout split ratio)
  (match layout
    ((Leaf _) layout)
    ((Split id direction old first second)
     (if (= id split)
         (Split id direction (max 0.1 (min 0.9 ratio)) first second)
         (Split id direction old (ratio-set first split ratio) (ratio-set second split ratio))))))

(: field-id (-> I64 String))
(define (field-id pane)
  (string-append "text-" (show pane)))

(: scroller-id (-> I64 String))
(define (scroller-id pane)
  (string-append "editor-" (show pane)))

;; ---- Requests ----

;; Why a request failed: the reply's status, or -1 when there was no
;; reply, and the service's message, or the connection's.
(struct Failure
  ((status I32)
   (message String)))

;; The service's JSON answer, or why there is none. A reply without
;; content answers null.
(: api (-> String String (List Header) String (Result Json Failure) ! fetch tasks))
(define (api method url headers body)
  (match (request method url headers body)
    ((Ok reply) (reply-json reply))
    ((Err why) (Err (Failure -1 why)))))

(: reply-json (-> Reply (Result Json Failure)))
(define (reply-json reply)
  (let ((status (Reply-status reply)))
    (match (if (= status 204) (Some (JsonNull)) (string->json (Reply-body reply)))
      ((Some json)
       (if (and (>= status 200) (< status 300))
           (Ok json)
           (Err (Failure status (json-text json "message")))))
      ((None)
       (Err
        (Failure status (string-append "the service answered " (show status) " without JSON")))))))

;; `text` as one component of a URL, as `encodeURIComponent` writes it:
;; its UTF-8 bytes, each but the unreserved characters escaped.
(: url-component (-> String String))
(define (url-component text)
  (string-concatenate
   (map (lambda (byte) (url-byte (u8->i32 byte))) (vector->list (string->utf8 text)))))

(: url-byte (-> I32 String))
(define (url-byte byte)
  (if (or (and (>= byte 65) (<= byte 90))
          (and (>= byte 97) (<= byte 122))
          (and (>= byte 48) (<= byte 57))
          (member? byte (list 33 39 40 41 42 45 46 95 126)))
      (make-string 1 (i32->char byte))
      (string-append "%"
                     (hex-digit (i32-shift-right/logical byte 4))
                     (hex-digit (i32-and byte 15)))))

(: hex-digit (-> I32 String))
(define (hex-digit value)
  (make-string 1 (string-ref "0123456789ABCDEF" (i32->i64 value))))

(: file-url (-> String String))
(define (file-url path)
  (string-append "/api/file?path=" (url-component path)))

;; ---- The service's JSON ----

(: json-text (-> Json String String))
(define (json-text json name)
  (match (json-member json name)
    ((Some (JsonString text)) text)
    (_ "")))

(: json-number (-> Json String (Option I64)))
(define (json-number json name)
  (match (json-member json name)
    ((Some (JsonInteger value)) (Some value))
    (_ (None))))

(: json-flag (-> Json String Bool))
(define (json-flag json name)
  (match (json-member json name)
    ((Some (JsonBool value)) value)
    (_ #f)))

(: json-items (-> Json String (List Json)))
(define (json-items json name)
  (match (json-member json name)
    ((Some (JsonArray items)) items)
    (_ (Nil))))

;; A file as the service sends it, which must have its text and revision.
(: file-reply (-> (Result Json Failure) (Result Snapshot Failure)))
(define (file-reply reply)
  (match reply
    ((Ok json)
     (match (Pair (json-member json "text") (json-member json "revision"))
       ((Pair (Some (JsonString text)) (Some (JsonString revision))) (Ok (Snapshot text revision)))
       (_ (Err (Failure 200 "the service sent a file without its text and revision")))))
    ((Err failure) (Err failure))))

;; The project as the service lists it: its name, its directory, and the
;; text files under it, by path from the directory.
(struct Project
  ((name String)
   (directory String)
   (files (List String))))

(: project-reply (-> (Result Json Failure) (Result Project Failure)))
(define (project-reply reply)
  (match reply
    ((Ok json)
     (Ok (Project (json-text json "name")
                  (json-text json "directory")
                  (concatenate (map (lambda (item)
                                      (match item
                                        ((JsonString path) (list path))
                                        (_ (Nil))))
                                    (json-items json "files"))))))
    ((Err failure) (Err failure))))

;; ---- Builds ----

;; Where the compiler places a diagnostic: a file, and a line and a column
;; of scalars, counting from 1.
(struct Point
  ((file String)
   (line I64)
   (column I64)))

;; What reads have said of the text a diagnostic was made from: nothing
;; yet; nothing that counts, since a save changed the text, so no read can
;; tie the old failure to it again; or that the read of `sequence` found
;; disk at `revision`.
(enum Observation
  (Unobserved)
  (Invalidated)
  (Observed ((revision String)
             (sequence I64))))

(struct Diagnostic
  ((severity String)
   (message String)
   (source (Option Point))
   (observation Observation)))

(: diagnostic-of (-> Json Diagnostic))
(define (diagnostic-of json)
  (Diagnostic (json-text json "severity")
              (json-text json "message")
              (match (json-member json "source")
                ((Some (JsonObject members))
                 (let ((source (JsonObject members)))
                   (match (Pair (json-number source "line") (json-number source "column"))
                     ((Pair (Some line) (Some column))
                      (Some (Point (json-text source "file") line column)))
                     (_ (None)))))
                (_ (None)))
              (Unobserved)))

;; The compiler's status as the toolbar shows it: its words, its state for
;; styling (`starting`, `building`, `built` or `failed`), and the attempt
;; it reports.
(struct Status
  ((text String)
   (state String)
   (attempt String)))

(: compiler-status (-> Json Status))
(define (compiler-status json)
  (let ((phase (json-text json "phase")))
    (Status (cond ((string=? phase "starting") "Starting the compiler…")
                  ((string=? phase "building") "Building…")
                  ((string=? phase "succeeded") "Built")
                  ((string=? phase "failed") "Build failed")
                  ((string=? phase "fatal") "Compiler stopped")
                  (else phase))
            (cond ((or (string=? phase "failed") (string=? phase "fatal")) "failed")
                  ((string=? phase "succeeded") "built")
                  (else phase))
            (match (json-number json "id")
              ((Some id) (show id))
              ((None) "")))))

;; ---- Runs ----

;; A run target's process as the service last reported it: the build it
;; runs, its process id once it has one, its phase, how it ended, if it
;; has, and what it has written.
(struct Attempt
  ((build I64)
   (pid (Option I64))
   (phase String)
   (code (Option I64))
   (signal String)
   (error String)
   (stdout String)
   (stderr String)))

;; A run target: the build requested of it, none when it is to stop; its
;; process; whether it is wanted running; and whether the project still
;; has it.
(struct Run
  ((target String)
   (desired (Option I64))
   (attempt (Option Attempt))
   (wanted Bool)
   (available Bool)))

;; The run targets, the one chosen, whether a command to it is in flight,
;; and what the last command did wrong.
(struct Runs
  ((runs (List Run))
   (selected String)
   (pending Bool)
   (problem String)))

(: run-of (-> Json Run))
(define (run-of json)
  (Run (json-text json "target")
       (match (json-member json "desired")
         ((Some (JsonObject members)) (json-number (JsonObject members) "build"))
         (_ (None)))
       (match (json-member json "attempt")
         ((Some (JsonObject members)) (Some (attempt-of (JsonObject members))))
         (_ (None)))
       (json-flag json "wanted")
       (json-flag json "available")))

(: attempt-of (-> Json Attempt))
(define (attempt-of json)
  (Attempt (match (json-number json "build")
             ((Some build) build)
             ((None) 0))
           (json-number json "pid")
           (json-text json "phase")
           (json-number json "code")
           (json-text json "signal")
           (json-text json "error")
           (json-text json "stdout")
           (json-text json "stderr")))

;; The runs the service reported, keeping the one chosen while it is
;; still there, else choosing the first available, else the first.
(: runs-received (-> Runs String Runs))
(define (runs-received runs data)
  (match (string->json data)
    ((Some (JsonArray items))
     (let ((list (map run-of items)))
       (Runs-selected-set (Runs-runs-set runs list) (chosen list (Runs-selected runs)))))
    (_ runs)))

(: chosen (-> (List Run) String String))
(define (chosen runs selected)
  (if (any? (lambda (run) (string=? (Run-target run) selected)) runs)
      selected
      (match (find Run-available runs)
        ((Some run) (Run-target run))
        ((None) (match runs
                  ((Cons run _) (Run-target run))
                  ((Nil) ""))))))

(: selected-run (-> Runs (Option Run)))
(define (selected-run runs)
  (find (lambda (run) (string=? (Run-target run) (Runs-selected runs))) (Runs-runs runs)))

;; What was asked of a run and what was seen of it.
(: run-description (-> (Option Run) String))
(define (run-description found)
  (match found
    ((Some run)
     (string-append (if (Run-available run) "" "Removed · ")
                    "Requested: "
                    (match (Run-desired run)
                      ((Some build) (string-append "build " (show build)))
                      ((None) "stop"))
                    " · Observed: "
                    (match (Run-attempt run)
                      ((Some attempt) (attempt-description attempt))
                      ((None) "no process"))))
    ((None) "No run targets")))

(: attempt-description (-> Attempt String))
(define (attempt-description attempt)
  (string-append (Attempt-phase attempt)
                 ", build "
                 (show (Attempt-build attempt))
                 (match (Attempt-pid attempt)
                   ((Some pid) (string-append ", PID " (show pid)))
                   ((None) ""))
                 (cond ((not (string=? (Attempt-signal attempt) ""))
                        (string-append " · " (Attempt-signal attempt)))
                       (else (match (Attempt-code attempt)
                               ((Some code) (string-append " · exit " (show code)))
                               ((None) ""))))
                 (if (string=? (Attempt-error attempt) "")
                     ""
                     (string-append " · " (Attempt-error attempt)))))

;; ---- The model ----

;; What a read remembers of when it was asked: its file and sequence, the
;; status then and the diagnostic at the file, with what reads had said
;; of its text; and what to do once it answers.
(struct Asked
  ((path String)
   (sequence I64)
   (generation I64)
   (diagnostic (Option I64))
   (observation Observation)
   (follow Follow)))

;; What opening a file asks once its read has answered: nothing, to focus
;; the pane that shows it, or also to put its caret at a diagnostic's
;; point, the one at `index` of status `generation`.
(enum Follow
  (Stay)
  (Focus ((pane I64)))
  (Reveal ((pane I64)
           (generation I64)
           (index I64))))

;; Where a drag began: the files' edge or a split's divider.
(enum Grip
  (FilesEdge)
  (Divider ((split I64))))

;; A drag under way: of the files' edge, within the page's width, or of a
;; split's divider, within the box of the panes' room.
(enum Drag
  (Resizing ((width F64)))
  (Dividing ((split I64)
             (box Measure))))

;; The editor: the project; the sequence of its latest listing; the open
;; buffers, in the order they were opened; the sequence of the latest read
;; of any; the panes, how they are laid out, the active one and the next
;; id for a pane or split; the folders shown closed; whether the files are
;; shown, and how wide; a drag; the compiler's status, its report as it
;; was sent, how many different reports have come, and their diagnostics;
;; the runs; and the event stream heard now, none while connecting.
(struct Ide
  ((project Project)
   (listing I64)
   (buffers (List Buffer))
   (reads I64)
   (panes (List Pane))
   (layout Layout)
   (active I64)
   (next I64)
   (closed (List String))
   (files-shown Bool)
   (files-width F64)
   (drag (Option Drag))
   (status Status)
   (report String)
   (generation I64)
   (diagnostics (List Diagnostic))
   (runs Runs)
   (events (Option Stream))))

(: initial Ide)
(define initial
  (Ide (Project "" "" (Nil))
       0
       (Nil)
       0
       (list (Pane 0 (None) 0.0))
       (Leaf 0)
       0
       1
       (Nil)
       #t
       220.0
       (None)
       (Status "Connecting…" "starting" "")
       ""
       0
       (Nil)
       (Runs (Nil) "" #f "")
       (None)))

(: buffer-at (-> Ide String (Option Buffer)))
(define (buffer-at model path)
  (find (lambda (buffer) (string=? (Buffer-path buffer) path)) (Ide-buffers model)))

;; The model with `buffer` in place of the one at its path, or added.
(: buffer-set (-> Ide Buffer Ide))
(define (buffer-set model buffer)
  (let ((path (Buffer-path buffer)))
    (Ide-buffers-set model
                     (match (buffer-at model path)
                       ((Some _)
                        (map (lambda (old) (if (string=? (Buffer-path old) path) buffer old))
                             (Ide-buffers model)))
                       ((None) (append (Ide-buffers model) (list buffer)))))))

;; The buffer at `path` closed, and the panes that showed it empty.
(: buffer-removed (-> Ide String Ide))
(define (buffer-removed model path)
  (Ide-panes-set (Ide-buffers-set model
                                  (filter
                                   (lambda (buffer) (not (string=? (Buffer-path buffer) path)))
                                   (Ide-buffers model)))
                 (map (lambda (pane)
                        (if (shows? pane path) (Pane-path-set pane (None)) pane))
                      (Ide-panes model))))

(: shows? (-> Pane String Bool))
(define (shows? pane path)
  (match (Pane-path pane)
    ((Some shown) (string=? shown path))
    ((None) #f)))

(: pane-of (-> Ide I64 Pane))
(define (pane-of model id)
  (match (find (lambda (pane) (= (Pane-id pane) id)) (Ide-panes model))
    ((Some pane) pane)
    ((None) (Pane id (None) 0.0))))

(: pane-set (-> Ide Pane Ide))
(define (pane-set model changed)
  (Ide-panes-set model
                 (map (lambda (pane) (if (= (Pane-id pane) (Pane-id changed)) changed pane))
                      (Ide-panes model))))

(: pane-buffer (-> Ide I64 (Option Buffer)))
(define (pane-buffer model id)
  (match (Pane-path (pane-of model id))
    ((Some path) (buffer-at model path))
    ((None) (None))))

(: active-buffer (-> Ide (Option Buffer)))
(define (active-buffer model)
  (pane-buffer model (Ide-active model)))

;; The active pane shows the file at `path`.
(: showing? (-> Ide I64 String Bool))
(define (showing? model pane path)
  (and (= pane (Ide-active model))
       (shows? (pane-of model pane) path)
       (match (buffer-at model path)
         ((Some _) #t)
         ((None) #f))))

;; The project file a diagnostic's point is in, when it names one of the
;; project's files. Generated scratch and library sources stay messages,
;; never mapped onto a project file.
(: source-path (-> Project (Option Point) (Option String)))
(define (source-path project source)
  (match source
    ((Some point)
     (let ((prefix (if (ends-with? (Project-directory project) "/")
                       (Project-directory project)
                       (string-append (Project-directory project) "/")))
           (file (Point-file point)))
       (if (starts-with? file prefix)
           (let ((path (substring file (string-length prefix) (string-length file))))
             (if (member? path (Project-files project)) (Some path) (None)))
           (None))))
    ((None) (None))))

;; The index of the first diagnostic at the file at `path`.
(: diagnostic-index (-> Ide String (Option I64)))
(define (diagnostic-index model path)
  (list-index (lambda (diagnostic)
                (match (source-path (Ide-project model) (Diagnostic-source diagnostic))
                  ((Some found) (string=? found path))
                  ((None) #f)))
              (Ide-diagnostics model)))

(: observation-at (-> Ide (Option I64) Observation))
(define (observation-at model index)
  (match index
    ((Some at) (Diagnostic-observation (list-ref (Ide-diagnostics model) at)))
    ((None) (Unobserved))))

(: observation-set (-> Ide I64 Observation Ide))
(define (observation-set model index observation)
  (Ide-diagnostics-set model
                       (map-indexed (lambda (at diagnostic)
                                      (if (= at index)
                                          (Diagnostic-observation-set diagnostic observation)
                                          diagnostic))
                                    (Ide-diagnostics model))))

;; The diagnostic whose point a pane showing the buffer marks: only while
;; the buffer is its disk contents, and only when the buffer's latest read
;; confirmed the revision the diagnostic was made from.
(: marked (-> Ide Buffer (Option Diagnostic)))
(define (marked model buffer)
  (match (Pair (Buffer-baseline buffer) (diagnostic-index model (Buffer-path buffer)))
    ((Pair (Some baseline) (Some index))
     (let ((diagnostic (list-ref (Ide-diagnostics model) index)))
       (match (Diagnostic-observation diagnostic)
         ((Observed revision sequence)
          (if (and (not (dirty? buffer))
                   (not (conflict? buffer))
                   (string=? revision (Snapshot-revision baseline))
                   (= sequence (Buffer-read buffer)))
              (Some diagnostic)
              (None)))
         (_ (None)))))
    (_ (None))))

(: failed-status (-> Ide String Status))
(define (failed-status model message)
  (Status message "failed" (Status-attempt (Ide-status model))))

;; ---- Messages ----

(enum Msg
  (Nothing)
  (Connect)
  (Connected ((stream Stream)))
  (Heard ((stream Stream)
          (event StreamEvent)))
  (Ended)
  (Listed ((sequence I64)
           (result (Result Project Failure))))
  (Open ((path String)))
  (Show ((generation I64)
         (index I64)))
  (Answered ((asked Asked)
             (result (Result Snapshot Failure))))
  (Typed ((pane I64)
          (text String)))
  (Pressed ((pane I64)
            (key String)
            (text String)
            (start I32)
            (end I32)))
  (Focused ((pane I64)))
  (Scrolled ((pane I64)
             (top F64)))
  (Save)
  (Saved ((path String)
          (result (Result Snapshot Failure))))
  (Format)
  (Formatted ((path String)
              (taken Bool)))
  (Reload)
  (Discard ((path String)))
  (Build)
  (Refused ((failure Failure)))
  (Divide ((pane I64)
           (direction String)))
  (Close ((pane I64)))
  (ToggleFiles)
  (ToggleFolder ((path String)))
  (Grab ((grip Grip)))
  (Grabbed ((drag Drag)))
  (Dragged ((x F64)
            (y F64)))
  (Dropped)
  (Shortcut ((key String)))
  (Choose ((target String)))
  (Control ((action String)))
  (Controlled ((action String)
               (target String)
               (result (Result Json Failure)))))

;; The next model and the commands an update starts.
(type Step
      (Pair Ide (List (Command Msg))))

(: stay (-> Ide Step))
(define (stay model)
  (Pair model (Nil)))

;; Two steps' commands, the first's model given to the second.
(: then (-> Step (-> Ide Step) Step))
(define (then step next)
  (match step
    ((Pair model commands)
     (match (next model)
       ((Pair after more) (Pair after (append commands more)))))))

(: update (-> Ide Msg Step))
(define (update model message)
  (match message
    ((Nothing) (stay model))
    ((Connect) (connecting model))
    ((Connected stream) (Pair (Ide-events-set model (Some stream)) (list (hear stream))))
    ((Heard stream event)
     (if (current-stream? model stream) (heard model stream event) (stay model)))
    ((Ended) (stay model))
    ((Listed sequence result) (listed model sequence result))
    ((Open path) (opening model path (Focus (Ide-active model))))
    ((Show generation index) (showing-diagnostic model generation index))
    ((Answered asked result) (answered model asked result))
    ((Typed pane text) (typed model pane text))
    ((Pressed pane key text start end) (pressed model pane key text start end))
    ((Focused pane) (stay (Ide-active-set model pane)))
    ((Scrolled pane top) (stay (pane-set model (Pane-scroll-set (pane-of model pane) top))))
    ((Save) (saving model))
    ((Saved path result) (saved model path result))
    ((Format) (formatting model))
    ((Formatted path taken) (formatted model path taken))
    ((Reload) (reloading model))
    ((Discard path) (discarded model path))
    ((Build) (Pair model (list (once building))))
    ((Refused failure)
     (stay (Ide-status-set model (failed-status model (Failure-message failure)))))
    ((Divide pane direction) (divided (Ide-active-set model pane) direction))
    ((Close pane) (closing (Ide-active-set model pane)))
    ((ToggleFiles) (stay (Ide-files-shown-set model (not (Ide-files-shown model)))))
    ((ToggleFolder path) (stay (Ide-closed-set model (toggled (Ide-closed model) path))))
    ((Grab grip) (Pair model (list (once (lambda () (grabbed grip))))))
    ((Grabbed drag) (stay (Ide-drag-set model (Some drag))))
    ((Dragged x y) (stay (dragged model x y)))
    ((Dropped) (stay (Ide-drag-set model (None))))
    ((Shortcut key) (update model (shortcut model key)))
    ((Choose target) (stay (Ide-runs-set model (Runs-selected-set (Ide-runs model) target))))
    ((Control action) (controlling model action))
    ((Controlled action target result) (controlled model action target result))))

;; ---- Events ----

;; The service's event stream: the compiler's status, the run targets'
;; processes, a sign that files changed, and each dropped connection.
(: event-kinds (List String))
(define event-kinds
  (list "status" "runs" "files" "error"))

;; Connecting closes the stream before, so none of its events, sent or
;; not, is heard again.
(: connecting (-> Ide Step))
(define (connecting model)
  (let ((old (Ide-events model)))
    (Pair (Ide-status-set (Ide-events-set model (None))
                          (Status "Connecting…" "starting" (Status-attempt (Ide-status model))))
          (list (once (lambda ()
                        (match old
                          ((Some stream) (stream-close stream))
                          ((None) (unit)))
                        (Connected (stream-open "/api/events" event-kinds))))))))

(: hear (-> Stream (Command Msg)))
(define (hear stream)
  (once (lambda ()
          (match (stream-next stream)
            ((Some event) (Heard stream event))
            ((None) (Ended))))))

(: current-stream? (-> Ide Stream Bool))
(define (current-stream? model stream)
  (match (Ide-events model)
    ((Some current) (= (Stream-id current) (Stream-id stream)))
    ((None) #f)))

;; The next event is heard after this one.
(: heard (-> Ide Stream StreamEvent Step))
(define (heard model stream event)
  (let ((kind (StreamEvent-kind event)) (data (StreamEvent-data event)))
    (then (Pair model (list (hear stream)))
          (lambda (model)
            (cond ((string=? kind "status") (received model data))
                  ((string=? kind "runs")
                   (stay (Ide-runs-set model (runs-received (Ide-runs model) data))))
                  ((string=? kind "files") (listing model))
                  (else (stay (Ide-status-set model
                                              (failed-status model
                                                             "Connection lost; reconnecting…")))))))))

;; A reconnection repeats the status the service holds; only a different
;; one replaces the diagnostics, and with them what reads said of their
;; text, as a save's invalidation. Every diagnostic's file is read again,
;; to tie it to the text it was made from.
(: received (-> Ide String Step))
(define (received model data)
  (match (string->json data)
    ((Some json)
     (let* ((fresh (not (string=? data (Ide-report model))))
            (model (if fresh
                       (Ide-diagnostics-set (Ide-generation-set (Ide-report-set model data)
                                                                (+ (Ide-generation model) 1))
                                            (map diagnostic-of (json-items json "diagnostics")))
                       model))
            (model (Ide-status-set model (compiler-status json))))
       (if (null? (Ide-diagnostics model)) (stay model) (reading-all model))))
    ((None) (stay model))))

;; ---- Files ----

;; Files changed: every open buffer is read again, and the project listed.
(: listing (-> Ide Step))
(define (listing model)
  (let ((sequence (+ (Ide-listing model) 1)))
    (then (reading-all (Ide-listing-set model sequence))
          (lambda (model)
            (Pair model
                  (list (once (lambda ()
                                (Listed sequence
                                        (project-reply (api "GET" "/api/project" (Nil) "")))))))))))

;; Only the latest listing counts. A project with files and no open
;; buffer opens its main.sld, or its first file.
(: listed (-> Ide I64 (Result Project Failure) Step))
(define (listed model sequence result)
  (if (= sequence (Ide-listing model))
      (match result
        ((Ok project)
         (let ((model (Ide-project-set model project)))
           (match (Project-files project)
             ((Cons first _)
              (if (null? (Ide-buffers model))
                  (opening model
                           (if (member? "main.sld" (Project-files project)) "main.sld" first)
                           (Focus (Ide-active model)))
                  (stay model)))
             ((Nil) (stay model)))))
        ((Err failure)
         (stay (Ide-status-set model (failed-status model (Failure-message failure))))))
      (stay model)))

;; Opening shows the file's buffer in the active pane at once, made empty
;; when it is new, and reads it when it has nothing from disk yet or a
;; diagnostic's point is to be found in it.
(: opening (-> Ide String Follow Step))
(define (opening model path follow)
  (let* ((model (match (buffer-at model path)
                  ((Some _) model)
                  ((None) (buffer-set model (new-buffer path)))))
         (model (pane-set model (Pane-path-set (pane-of model (Ide-active model)) (Some path)))))
    (match (buffer-at model path)
      ((Some buffer)
       (match follow
         ((Reveal _ _ _) (reading model path follow))
         (_ (if (loaded? buffer)
                (Pair model (followed model path follow))
                (reading model path follow)))))
      ((None) (stay model)))))

(: showing-diagnostic (-> Ide I64 I64 Step))
(define (showing-diagnostic model generation index)
  (if (= generation (Ide-generation model))
      (match (source-path (Ide-project model)
                          (Diagnostic-source (list-ref (Ide-diagnostics model) index)))
        ((Some path) (opening model path (Reveal (Ide-active model) generation index)))
        ((None) (stay model)))
      (stay model)))

;; What opening asked, once the file's read has answered, while the pane
;; that asked is active and still shows the file. A point is revealed only
;; when the diagnostic is still the one the pane marks.
(: followed (-> Ide String Follow (List (Command Msg))))
(define (followed model path follow)
  (match follow
    ((Stay) (Nil))
    ((Focus pane) (if (showing? model pane path) (list (focusing pane)) (Nil)))
    ((Reveal pane generation index)
     (if (showing? model pane path)
         (match (revealed model path generation index)
           ((Some point) (list (revealing pane (shown-text model path) point)))
           ((None) (list (focusing pane))))
         (Nil)))))

(: revealed (-> Ide String I64 I64 (Option Point)))
(define (revealed model path generation index)
  (match (buffer-at model path)
    ((Some buffer)
     (match (Pair (marked model buffer) (diagnostic-index model path))
       ((Pair (Some diagnostic) (Some at))
        (if (and (= generation (Ide-generation model)) (= at index))
            (Diagnostic-source diagnostic)
            (None)))
       (_ (None))))
    ((None) (None))))

(: shown-text (-> Ide String String))
(define (shown-text model path)
  (match (buffer-at model path)
    ((Some buffer) (display-text (Buffer-text buffer)))
    ((None) "")))

(: focusing (-> I64 (Command Msg)))
(define (focusing pane)
  (once (lambda ()
          (match (element-by-id (field-id pane))
            ((Some field) (focus-node field))
            ((None) (unit)))
          (Nothing))))

;; The caret at a diagnostic's point, its line scrolled a few lines below
;; the top.
(: revealing (-> I64 String Point (Command Msg)))
(define (revealing pane text point)
  (once (lambda ()
          (let ((offset (source-offset text point)))
            (match (element-by-id (field-id pane))
              ((Some field)
               (focus-node field)
               (select-range field (i64->i32 offset) (i64->i32 offset)))
              ((None) (unit)))
            (scrolled-to pane (* line-height (i64->f64 (max 0 (- (count-lines text 0 offset) 4)))))
            (Nothing)))))

(: scrolled-to (-> I64 F64 Unit ! dom))
(define (scrolled-to pane top)
  (match (element-by-id (scroller-id pane))
    ((Some scroller) (set-number-property scroller "scrollTop" top))
    ((None) (unit))))

;; ---- Reading ----

;; A read of the buffer at `path`, unless it is saving. Its sequence
;; withdraws what every earlier read said, the point it marked among it.
(: reading (-> Ide String Follow Step))
(define (reading model path follow)
  (match (buffer-at model path)
    ((Some buffer)
     (if (Buffer-saving buffer)
         (Pair model (followed model path follow))
         (let* ((sequence (+ (Ide-reads model) 1))
                (index (diagnostic-index model path))
                (asked (Asked path
                              sequence
                              (Ide-generation model)
                              index
                              (observation-at model index)
                              follow)))
           (Pair (buffer-set (Ide-reads-set model sequence) (Buffer-read-set buffer sequence))
                 (list (once (lambda ()
                               (Answered asked
                                         (file-reply (api "GET" (file-url path) (Nil) ""))))))))))
    ((None) (Pair model (followed model path follow)))))

(: reading-all (-> Ide Step))
(define (reading-all model)
  (fold-left (lambda (step path) (then step (lambda (model) (reading model path (Stay)))))
             (stay model)
             (map Buffer-path (Ide-buffers model))))

;; Only a buffer's latest read counts; what it asked is done either way.
(: answered (-> Ide Asked (Result Snapshot Failure) Step))
(define (answered model asked result)
  (let* ((path (Asked-path asked))
         (model (match (buffer-at model path)
                  ((Some buffer)
                   (if (= (Buffer-read buffer) (Asked-sequence asked))
                       (match result
                         ((Ok snapshot)
                          (snapshot-read (bound model asked snapshot) buffer snapshot))
                         ((Err failure) (read-failed model buffer failure)))
                       model))
                  ((None) model))))
    (Pair model (followed model path (Asked-follow asked)))))

;; The draft follows disk unless it has changes of its own.
(: snapshot-read (-> Ide Buffer Snapshot Ide))
(define (snapshot-read model buffer snapshot)
  (let* ((observed (Buffer-observed-set buffer (Some (Snapshot-revision snapshot))))
         (loaded (if (dirty? buffer)
                     observed
                     (Buffer-baseline-set (Buffer-text-set observed (Snapshot-text snapshot))
                                          (Some snapshot)))))
    (buffer-set model
                (Buffer-problem-set loaded
                                    (if (conflict? loaded)
                                        "Changed on disk. Your draft is kept; Reload discards it."
                                        "")))))

;; Only a read that finds the file gone removes a buffer, and then only
;; one without changes of its own; a draft is kept.
(: read-failed (-> Ide Buffer Failure Ide))
(define (read-failed model buffer failure)
  (if (= (Failure-status failure) 404)
      (let ((gone
             (Buffer-problem-set (Buffer-observed-set buffer (None)) (Failure-message failure))))
        (if (dirty? gone)
            (buffer-set model
                        (Buffer-problem-set gone
                                            "Deleted on disk. Your draft is kept; copy it before reloading."))
            (buffer-removed model (Buffer-path buffer))))
      (buffer-set model (Buffer-problem-set buffer (Failure-message failure)))))

;; A read ties the diagnostic at its file to the revision it found, when
;; that is the diagnostic that was there when it was asked, and reads had
;; then said nothing of its text or said that same revision.
(: bound (-> Ide Asked Snapshot Ide))
(define (bound model asked snapshot)
  (match (Pair (Asked-diagnostic asked) (diagnostic-index model (Asked-path asked)))
    ((Pair (Some index) (Some now))
     (if (and (= index now)
              (= (Asked-generation asked) (Ide-generation model))
              (match (Asked-observation asked)
                ((Unobserved) #t)
                ((Observed revision _) (string=? revision (Snapshot-revision snapshot)))
                ((Invalidated) #f)))
         (observation-set model
                          index
                          (Observed (Snapshot-revision snapshot) (Asked-sequence asked)))
         model))
    (_ model)))

;; ---- Typing ----

;; A draft typed back to its disk contents while disk has moved on reads
;; disk again.
(: typed (-> Ide I64 String Step))
(define (typed model pane text)
  (match (pane-buffer model pane)
    ((Some buffer)
     (if (loaded? buffer)
         (let ((edited (Buffer-text-set buffer text)))
           (if (and (not (dirty? edited)) (conflict? edited))
               (reading (buffer-set model edited) (Buffer-path edited) (Stay))
               (stay (buffer-set model edited))))
         (stay model)))
    ((None) (stay model))))

;; Tab and Enter in a Scheme source, made in the field by a command.
(: pressed (-> Ide I64 String String I32 I32 Step))
(define (pressed model pane key text start end)
  (let ((from (i32->i64 start)) (to (i32->i64 end)))
    (Pair model
          (list (changing pane
                          (if (string=? key "Tab")
                              (indent-change text from to)
                              (newline-change text from to)))))))

(: changing (-> I64 Change (Command Msg)))
(define (changing pane change)
  (once (lambda ()
          (match (element-by-id (field-id pane))
            ((Some field) (apply-change field change) (Nothing))
            ((None) (Nothing))))))

;; The keys Tab and Enter, which a Scheme source's field hears.
(: editing-chords (List Chord))
(define editing-chords
  (list (Chord "Tab" 0) (Chord "Tab" shift-key) (Chord "Enter" 0)))

;; ---- Saving ----

;; One save at a time per buffer. Its answer changes the baseline, never
;; newer typing, and a read begun before it no longer counts. A save
;; withdraws the diagnostic at its file for good: the failure was not made
;; from the text it writes.
(: saving (-> Ide Step))
(define (saving model)
  (match (active-buffer model)
    ((Some buffer)
     (match (Buffer-baseline buffer)
       ((Some baseline)
        (if (Buffer-saving buffer)
            (stay model)
            (let* ((sequence (+ (Ide-reads model) 1))
                   (model (match (diagnostic-index model (Buffer-path buffer))
                            ((Some index) (observation-set model index (Invalidated)))
                            ((None) model)))
                   (pane (pane-of model (Ide-active model))))
              (Pair (buffer-set (Ide-reads-set model sequence)
                                (Buffer-failure-set
                                 (Buffer-read-set (Buffer-saving-set buffer #t) sequence)
                                 ""))
                    (list (once (lambda () (saved-text pane buffer baseline))))))))
       ((None) (stay model))))
    ((None) (stay model))))

;; A source is formatted first, in the pane's field; formatting that fails
;; does not keep an incomplete draft from being saved.
(: saved-text (-> Pane Buffer Snapshot Msg ! dom fetch tasks))
(define (saved-text pane buffer baseline)
  (let* ((path (Buffer-path buffer))
         (text
          (if (source-file? path) (formatted-in pane (Buffer-text buffer)) (Buffer-text buffer))))
    (Saved path
           (file-reply (api "PUT"
                            (file-url path)
                            (list (Header "Content-Type" "text/plain; charset=utf-8")
                                  (Header "If-Match"
                                          (string-append "\"" (Snapshot-revision baseline) "\"")))
                            text)))))

;; The text formatted in the pane's field as typing would, which the
;; field's input brings to the buffer too; or the text as it was, when the
;; field did not take it.
(: formatted-in (-> Pane String String ! dom))
(define (formatted-in pane text)
  (let* ((shown (display-text text)) (formatted (format-source shown format-width)))
    (if (or (string=? shown formatted) (not (reformatted pane shown formatted)))
        text
        formatted)))

;; The change keeps the caret's line, and the field its scroll.
(: reformatted (-> Pane String String Bool ! dom))
(define (reformatted pane shown formatted)
  (match (element-by-id (field-id (Pane-id pane)))
    ((Some field)
     (let ((taken (apply-change field
                                (format-change shown
                                               formatted
                                               (i32->i64 (Pair-first (selection-range field)))))))
       (scrolled-to (Pane-id pane) (Pane-scroll pane))
       taken))
    ((None) #f)))

;; A save that wrote has its text as the new baseline. The file is read
;; again even after a failure, as the write may have reached disk.
(: saved (-> Ide String (Result Snapshot Failure) Step))
(define (saved model path result)
  (match (buffer-at model path)
    ((Some buffer)
     (reading (buffer-set model
                          (Buffer-saving-set
                           (match result
                             ((Ok snapshot)
                              (Buffer-observed-set (Buffer-baseline-set buffer (Some snapshot))
                                                   (Some (Snapshot-revision snapshot))))
                             ((Err failure)
                              (Buffer-failure-set buffer
                                                  (if (= (Failure-status failure) 409)
                                                      "Changed on disk; save rejected. Your draft is kept."
                                                      (Failure-message failure)))))
                           #f))
              path
              (Stay)))
    ((None) (stay model))))

(: formatting (-> Ide Step))
(define (formatting model)
  (match (active-buffer model)
    ((Some buffer)
     (if (and (loaded? buffer) (source-file? (Buffer-path buffer)))
         (let ((pane (pane-of model (Ide-active model))) (path (Buffer-path buffer)))
           (Pair (buffer-set model (Buffer-failure-set buffer ""))
                 (list (once (lambda ()
                               (let* ((shown (display-text (Buffer-text buffer)))
                                      (formatted (format-source shown format-width)))
                                 (Formatted path
                                            (or (string=? shown formatted)
                                                (reformatted pane shown formatted)))))))))
         (stay model)))
    ((None) (stay model))))

(: formatted (-> Ide String Bool Step))
(define (formatted model path taken)
  (stay (match (buffer-at model path)
          ((Some buffer)
           (if taken
               model
               (buffer-set model
                           (Buffer-failure-set buffer "The page refused the formatted text."))))
          ((None) model))))

;; Reload discards a draft, once the person agrees, then reads disk. The
;; discard is at once: a read that answers later loads disk, while typing
;; after it is a new draft that survives that read.
(: reloading (-> Ide Step))
(define (reloading model)
  (match (active-buffer model)
    ((Some buffer)
     (cond ((Buffer-saving buffer) (stay model))
           ((dirty? buffer)
            (Pair model
                  (list (once (lambda ()
                                (if (confirm
                                     "Discard this file’s unsaved changes and reload from disk?")
                                    (Discard (Buffer-path buffer))
                                    (Nothing)))))))
           (else (discarded model (Buffer-path buffer)))))
    ((None) (stay model))))

(: discarded (-> Ide String Step))
(define (discarded model path)
  (match (buffer-at model path)
    ((Some buffer)
     (reading (buffer-set model
                          (Buffer-failure-set (match (Buffer-baseline buffer)
                                                ((Some baseline)
                                                 (Buffer-text-set buffer (Snapshot-text baseline)))
                                                ((None) buffer))
                                              ""))
              path
              (Stay)))
    ((None) (stay model))))

(: building (-> Msg ! fetch tasks))
(define (building)
  (match (api "POST" "/api/build" (Nil) "")
    ((Ok _) (Nothing))
    ((Err failure) (Refused failure))))

;; ---- Arranging ----

;; The active pane splits in two, the new one second, showing the same
;; file, and active.
(: divided (-> Ide String Step))
(define (divided model direction)
  (let* ((active (Ide-active model))
         (pane (Ide-next model))
         (split (Split (+ pane 1) direction 0.5 (Leaf active) (Leaf pane)))
         (model (Ide-panes-set model
                               (append (Ide-panes model)
                                       (list (Pane pane (Pane-path (pane-of model active)) 0.0)))))
         (model (Ide-layout-set model (leaf-replaced (Ide-layout model) active split))))
    (Pair (Ide-next-set (Ide-active-set model pane) (+ pane 2)) (list (focusing pane)))))

;; The active pane closes, its sibling taking its split's place; the last
;; pane stays.
(: closing (-> Ide Step))
(define (closing model)
  (let ((active (Ide-active model)))
    (match (sibling (Ide-layout model) active)
      ((Some beside)
       (let* ((next (first-leaf beside))
              (model (Ide-layout-set model (without-leaf (Ide-layout model) active)))
              (model (Ide-panes-set model
                                    (filter (lambda (pane) (not (= (Pane-id pane) active)))
                                            (Ide-panes model)))))
         (Pair (Ide-active-set model next) (list (focusing next)))))
      ((None) (stay model)))))

(: toggled (-> (List String) String (List String)))
(define (toggled closed path)
  (if (member? path closed)
      (filter (lambda (other) (not (string=? other path))) closed)
      (Cons path closed)))

;; A drag measures what it divides as it begins.
(: grabbed (-> Grip Msg ! dom))
(define (grabbed grip)
  (match grip
    ((FilesEdge) (Grabbed (Resizing (Measure-width (measured "workbench")))))
    ((Divider split) (Grabbed (Dividing split (measured "panes"))))))

(: measured (-> String Measure ! dom))
(define (measured id)
  (match (element-by-id id)
    ((Some node) (measure node))
    ((None) (Measure 0.0 0.0 0.0 0.0 0.0 0.0 0.0))))

;; The files keep between 120 pixels and seven tenths of the page; a
;; divider follows the pointer across its split.
(: dragged (-> Ide F64 F64 Ide))
(define (dragged model x y)
  (match (Ide-drag model)
    ((Some (Resizing width)) (Ide-files-width-set model (max 120.0 (min (* width 0.7) x))))
    ((Some (Dividing split box))
     (match (division-of (Ide-layout model) split)
       ((Some division)
        (Ide-layout-set model (ratio-set (Ide-layout model) split (pointed division box x y))))
       ((None) model)))
    ((None) model)))

;; Where the pointer lies across the split, in the room's box on the page.
(: pointed (-> Division Measure F64 F64 F64))
(define (pointed division box x y)
  (let ((area (Division-area division)))
    (if (string=? (Division-direction division) "column")
        (/ (- y (+ (Measure-top box) (* (Area-top area) (Measure-height box))))
           (* (Area-height area) (Measure-height box)))
        (/ (- x (+ (Measure-left box) (* (Area-left area) (Measure-width box))))
           (* (Area-width area) (Measure-width box))))))

;; The page's shortcuts, keys held with Control or Command.
(: shortcut (-> Ide String Msg))
(define (shortcut model key)
  (cond ((string=? key "s") (Save))
        ((string=? key "F") (Format))
        ((string=? key "b") (ToggleFiles))
        ((string=? key "\\") (Divide (Ide-active model) "row"))
        ((string=? key "|") (Divide (Ide-active model) "column"))
        (else (Nothing))))

(: shortcut-chords (List Chord))
(define shortcut-chords
  (concatenate (map (lambda (held)
                      (list (Chord "s" held)
                            (Chord "F" (+ held shift-key))
                            (Chord "b" held)
                            (Chord "\\" held)
                            (Chord "|" (+ held shift-key))))
                    (list control-key meta-key))))

;; ---- Controlling runs ----

;; One command to the runs at a time. Its reply only acknowledges it: the
;; event stream reports what the process does. A reply lost after the
;; command reached the service leaves its outcome unknown.
(: controlling (-> Ide String Step))
(define (controlling model action)
  (let ((runs (Ide-runs model)))
    (if (Runs-pending runs)
        (stay model)
        (let ((target (Runs-selected runs)))
          (Pair (Ide-runs-set model (Runs-problem-set (Runs-pending-set runs #t) ""))
                (list (once (lambda ()
                              (Controlled action
                                          target
                                          (api "POST"
                                               (string-append "/api/run/"
                                                              action
                                                              "?target="
                                                              (url-component target))
                                               (Nil)
                                               ""))))))))))

(: controlled (-> Ide String String (Result Json Failure) Step))
(define (controlled model action target result)
  (let ((runs (Runs-pending-set (Ide-runs model) #f)))
    (stay (Ide-runs-set model
                        (match result
                          ((Ok _) runs)
                          ((Err failure)
                           (Runs-problem-set runs
                                             (string-append action
                                                            " "
                                                            target
                                                            ": "
                                                            (if
                                                             (and (>= (Failure-status failure) 400)
                                                                  (< (Failure-status failure) 500))
                                                             (Failure-message failure)
                                                             "Outcome unknown; the command may have taken effect. Check process status before trying again.")))))))))

;; ---- Drawing ----

;; Lines are 20 pixels high, as ide.css's `--code` sets them.
(: line-height F64)
(define line-height 20.0)

;; The highlight layer draws from ten lines above the scroll 160 lines,
;; more than a pane shows, in runs of one class each. The highlighter reads
;; them from the start of their top-level form, as Emacs resynchronizes.
(: highlight-view (-> String F64 Bool (Html Msg)))
(define (highlight-view text scroll scheme)
  (let* ((first (max 0 (- (f64->i64 (floor (/ scroll line-height))) 10)))
         (start (line-offset text (+ first 1)))
         (end (line-offset text (+ first 161))))
    (Element "pre"
             (list (Attr "class" "highlight")
                   (Attr "style" (string-append "top: " (show (* first 20)) "px")))
             (if scheme
                 (highlight-runs text start end)
                 (list (Text (substring text start end)))))))

(: highlight-runs (-> String I64 I64 (List (Html Msg))))
(define (highlight-runs text start end)
  (let ((base (top-level-start text start)))
    (map run-view
         (reverse (fold-left (lambda (runs token)
                               (let ((from (max start (+ base (Token-start token))))
                                     (to (min end (+ base (Token-end token)))))
                                 (if (< from to)
                                     (joined runs (token-class token) (substring text from to))
                                     runs)))
                             (Nil)
                             (highlight-tokens (substring text base end)))))))

;; A class of the highlight's styles in ide.css, as the book's are named;
;; whitespace and plain names are plain text.
(: token-class (-> Token String))
(define (token-class token)
  (match (Token-class token)
    ((Blank) "")
    ((Identifier) "")
    (class (string-append "tok-" (class-name class)))))

;; The runs, newest first, with a piece of `class` added.
(: joined (-> (List (Pair String String)) String String (List (Pair String String))))
(define (joined runs class piece)
  (match runs
    ((Cons (Pair last text) rest)
     (if (string=? last class)
         (Cons (Pair class (string-append text piece)) rest)
         (Cons (Pair class piece) runs)))
    ((Nil) (list (Pair class piece)))))

(: run-view (-> (Pair String String) (Html Msg)))
(define (run-view run)
  (match run
    ((Pair "" text) (Text text))
    ((Pair class text) (Element "span" (list (Attr "class" class)) (list (Text text))))))

;; Compiler columns count scalars, as offsets do. A point marks one scalar,
;; or a space at a line's end, never a range guessed from the source or
;; the message.
(: source-offset (-> String Point I64))
(define (source-offset text point)
  (let loop ((offset (line-offset text (Point-line point))) (column 1))
    (if (and (< column (Point-column point))
             (< offset (string-length text))
             (not (char=? (string-ref text offset) #\newline)))
        (loop (+ offset 1) (+ column 1))
        offset)))

(: marks-view (-> String (Option Diagnostic) (Html Msg)))
(define (marks-view text found)
  (Element "pre"
           (list (Attr "class" "marks"))
           (match found
             ((Some diagnostic)
              (match (Diagnostic-source diagnostic)
                ((Some point)
                 (let ((offset (source-offset text point)))
                   (list (Text (substring text 0 offset))
                         (Element "span"
                                  (list (Attr "class" "squiggle")
                                        (Attr "title" (Diagnostic-message diagnostic)))
                                  (list (Text (if (and (< offset (string-length text))
                                                       (not (char=? (string-ref text offset)
                                                                    #\newline)))
                                                  (substring text offset (+ offset 1))
                                                  " ")))))))
                ((None) (Nil))))
             ((None) (Nil)))))

;; ---- The view ----

;; A button the toolbar or a pane holds, which never takes the focus from
;; the field.
(: tool (-> String String String String Bool Msg (Html Msg)))
(define (tool id class title label disabled message)
  (Element "button"
           (list (Attr "id" id)
                 (Attr "class" class)
                 (Attr "title" title)
                 (FlagProperty "disabled" disabled)
                 (On "mousedown" (Nil) (Always) (lambda (event) (Nothing)))
                 (On "click" (Nil) (Allow) (lambda (event) message)))
           (list (Text label))))

(: view (-> Ide (Html Msg)))
(define (view model)
  (Element "div"
           (list (Attr "id" "workbench") (Attr "class" "ide"))
           (append (list (toolbar-view model)
                         (layout-view model)
                         (diagnostics-view model)
                         (runs-view (Ide-runs model)))
                   (drag-view model))))

(: toolbar-view (-> Ide (Html Msg)))
(define (toolbar-view model)
  (let* ((buffer (active-buffer model))
         (loaded (match buffer
                   ((Some found) (loaded? found))
                   ((None) #f)))
         (busy (match buffer
                 ((Some found) (Buffer-saving found))
                 ((None) #t)))
         (source (match buffer
                   ((Some found) (source-file? (Buffer-path found)))
                   ((None) #f)))
         (status (Ide-status model)))
    (Element "header"
             (list (Attr "class" "toolbar"))
             (list (Element "button"
                            (list (Attr "id" "toggle-files")
                                  (Attr "class" "tool")
                                  (Attr "title" "Files (Ctrl+B)")
                                  (Attr "aria-pressed" (if (Ide-files-shown model) "true" "false"))
                                  (On "mousedown" (Nil) (Always) (lambda (event) (Nothing)))
                                  (On "click" (Nil) (Allow) (lambda (event) (ToggleFiles))))
                            (list (Text "☰")))
                   (Element "span"
                            (list (Attr "id" "project") (Attr "class" "project"))
                            (list (Text (Project-name (Ide-project model)))))
                   (tool "save" "tool" "Save (Ctrl+S)" "Save" (or (not loaded) busy) (Save))
                   (tool "reload"
                         "tool"
                         "Reload the selected file from disk"
                         "Reload"
                         busy
                         (Reload))
                   (tool "build" "tool" "Build the files saved on disk" "Build" #f (Build))
                   ;; The status is the span's whole text, set as a property, so
                   ;; it is right again however the page's text was changed.
                   (Element "span"
                            (list (Attr "id" "status")
                                  (Attr "class" "status")
                                  (Attr "role" "status")
                                  (Attr "title" (Status-text status))
                                  (Attr "data-state" (Status-state status))
                                  (Attr "data-attempt" (Status-attempt status))
                                  (StringProperty "textContent" (Status-text status)))
                            (Nil))
                   (tool "format"
                         "tool"
                         "Format (Ctrl+Shift+F)"
                         "Format"
                         (not (and loaded source))
                         (Format))
                   (tool "split-right"
                         "tool"
                         "Split right (Ctrl+\\)"
                         "⇥"
                         #f
                         (Divide (Ide-active model) "row"))
                   (tool "split-down"
                         "tool"
                         "Split down (Ctrl+Shift+\\)"
                         "⤓"
                         #f
                         (Divide (Ide-active model) "column"))))))

(: layout-view (-> Ide (Html Msg)))
(define (layout-view model)
  (Element "main"
           (list
            (Attr "class" (if (Ide-files-shown model) "project-layout" "project-layout no-files"))
            (Attr "style"
                  (string-append "--files-width: "
                                 (show (f64->i64 (round (Ide-files-width model))))
                                 "px")))
           (list (files-view model)
                 (Element "div"
                          (list (Attr "id" "files-resizer")
                                (Attr "class" "resizer")
                                (On "pointerdown"
                                    (Nil)
                                    (Always)
                                    (lambda (event) (Grab (FilesEdge)))))
                          (Nil))
                 (Element "section"
                          (list (Attr "id" "panes")
                                (Attr "class" "panes")
                                (Attr "aria-label" "Editors"))
                          (panes-view model)))))

;; ---- Files ----

;; The project's files as a tree: folders first, then files, each by name.
(enum Tree
  (File ((name String)
         (path String)))
  (Folder ((name String)
           (entries (List Tree)))))

(: path-parts (-> String (List String)))
(define (path-parts path)
  (let loop ((end (string-length path)) (index (- (string-length path) 1)) (parts (Nil)))
    (cond ((< index 0) (Cons (substring path 0 end) parts))
          ((char=? (string-ref path index) #\/)
           (loop index (- index 1) (Cons (substring path (+ index 1) end) parts)))
          (else (loop end (- index 1) parts)))))

;; Each file is the parts of its path left to place, and its path.
(: file-tree (-> (List (Pair (List String) String)) (List Tree)))
(define (file-tree files)
  (let* ((nested (filter (lambda (file) (> (length (Pair-first file)) 1)) files))
         (names (sorted-strings
                 (delete-duplicates string=? (map (lambda (file) (car-part file)) nested)))))
    (append (map (lambda (name)
                   (Folder name
                           (file-tree (map (lambda (file)
                                             (Pair (list-tail (Pair-first file) 1)
                                                   (Pair-second file)))
                                           (filter (lambda (file) (string=? (car-part file) name))
                                                   nested)))))
                 names)
            (map (lambda (file) (File (car-part file) (Pair-second file)))
                 (sorted-by (lambda (a b) (string<? (car-part a) (car-part b)))
                            (filter (lambda (file) (= (length (Pair-first file)) 1)) files))))))

(: car-part (-> (Pair (List String) String) String))
(define (car-part file)
  (match (Pair-first file)
    ((Cons part _) part)
    ((Nil) "")))

(: sorted-strings (-> (List String) (List String)))
(define (sorted-strings strings)
  (sorted-by string<? strings))

;; An insertion sort, for the few entries of a folder.
(: sorted-by (All (T) (requires (Copy T)) (-> (-> T T Bool) (List T) (List T))))
(define (sorted-by less items)
  (fold-left (lambda (sorted item) (inserted less item sorted)) (Nil) items))

(: inserted (All (T) (requires (Copy T)) (-> (-> T T Bool) T (List T) (List T))))
(define (inserted less item sorted)
  (match sorted
    ((Cons first rest)
     (if (less item first) (Cons item sorted) (Cons first (inserted less item rest))))
    ((Nil) (list item))))

(: files-view (-> Ide (Html Msg)))
(define (files-view model)
  (let* ((project (Ide-project model))
         (unlisted (filter (lambda (path) (not (member? path (Project-files project))))
                           (map Buffer-path (Ide-buffers model)))))
    (Element "nav"
             (list (Attr "id" "files") (Attr "class" "dock files") (Attr "aria-label" "Files"))
             (append (list (Element "h2"
                                    (Nil)
                                    (list (Text (if (string=? (Project-name project) "")
                                                    "Project"
                                                    (Project-name project)))))
                           (tree-view model
                                      (file-tree (map (lambda (path) (Pair (path-parts path) path))
                                                      (Project-files project)))
                                      ""))
                     (if (null? unlisted)
                         (Nil)
                         (Cons (Element "h2" (Nil) (list (Text "Open files")))
                               (map (lambda (path) (file-button model path path)) unlisted)))))))

(: tree-view (-> Ide (List Tree) String (Html Msg)))
(define (tree-view model entries prefix)
  (Element "ul"
           (Nil)
           (map (lambda (entry)
                  (match entry
                    ((File name path)
                     (Element "li" (list (Keyed path)) (list (file-button model name path))))
                    ((Folder name inside)
                     (let ((path (string-append prefix name "/")))
                       (Element "li"
                                (list (Keyed path))
                                (list (folder-view model name inside path)))))))
                entries)))

;; A folder opens and closes as the model says, not by itself.
(: folder-view (-> Ide String (List Tree) String (Html Msg)))
(define (folder-view model name entries path)
  (Element "details"
           (list (FlagProperty "open" (not (member? path (Ide-closed model)))))
           (list (Element "summary"
                          (list (On "click" (Nil) (Always) (lambda (event) (ToggleFolder path))))
                          (list (Text name)))
                 (tree-view model entries path))))

(: file-button (-> Ide String String (Html Msg)))
(define (file-button model name path)
  (let ((buffer (buffer-at model path))
        (active (shows? (pane-of model (Ide-active model)) path)))
    (Element "button"
             (list (Attr "class"
                         (string-append "file"
                                        (if active " active" "")
                                        (match buffer
                                          ((Some found)
                                           (string-append (if (dirty? found) " dirty" "")
                                                          (if (conflict? found) " conflict" "")))
                                          ((None) ""))))
                   (Attr "data-path" path)
                   (Attr "title"
                         (match buffer
                           ((Some found)
                            (cond
                             ((not (string=? (Buffer-failure found) "")) (Buffer-failure found))
                             ((not (string=? (Buffer-problem found) "")) (Buffer-problem found))
                             (else path)))
                           ((None) path)))
                   (On "click" (Nil) (Allow) (lambda (event) (Open path))))
             (list (Text name)))))

;; ---- Panes' view ----

;; The panes are the room's children, each placed in its part of it, and
;; the dividers lie over their edges. A split adds a pane and moves the
;; others, so each keeps its field, with its caret and undo history.
(: panes-view (-> Ide (List (Html Msg))))
(define (panes-view model)
  (let ((areas (pane-areas (Ide-layout model) whole)))
    (append (map (lambda (pane)
                   (pane-view model
                              (Pane-id pane)
                              (match (assoc-ref areas (Pane-id pane))
                                ((Some area) area)
                                ((None) whole))))
                 (Ide-panes model))
            (map divider-view (divisions (Ide-layout model) whole)))))

(: percent (-> F64 String))
(define (percent fraction)
  (string-append (f64->string (* fraction 100.0)) "%"))

(: placed (-> Area String))
(define (placed area)
  (string-append "left: "
                 (percent (Area-left area))
                 "; top: "
                 (percent (Area-top area))
                 "; width: "
                 (percent (Area-width area))
                 "; height: "
                 (percent (Area-height area))))

;; A divider lies along the edge the split's ratio puts between its halves,
;; as long as the edge; ide.css gives it its thickness.
(: divider-view (-> Division (Html Msg)))
(define (divider-view division)
  (let* ((direction (Division-direction division))
         (edge (Pair-second (halves (Division-area division) direction (Division-ratio division))))
         (corner (string-append "left: "
                                (percent (Area-left edge))
                                "; top: "
                                (percent (Area-top edge)))))
    (Element "div"
             (list (Keyed (string-append "divider-" (show (Division-split division))))
                   (Attr "class" (string-append "divider " direction))
                   (Attr "style"
                         (if (string=? direction "column")
                             (string-append corner "; width: " (percent (Area-width edge)))
                             (string-append corner "; height: " (percent (Area-height edge)))))
                   (On "pointerdown"
                       (Nil)
                       (Always)
                       (lambda (event) (Grab (Divider (Division-split division))))))
             (Nil))))

(: pane-view (-> Ide I64 Area (Html Msg)))
(define (pane-view model id area)
  (let* ((pane (pane-of model id)) (buffer (pane-buffer model id)))
    (Element "div"
             (list (Keyed (string-append "pane-" (show id)))
                   (Attr "class" (if (= id (Ide-active model)) "pane active" "pane"))
                   (Attr "style" (placed area)))
             (list (Element "div"
                            (list (Attr "class" "pane-header"))
                            (list (Element "span"
                                           (list (Attr "class" "pane-title"))
                                           (list (Text (pane-title buffer))))
                                  (tool "" "pane-button" "Split right" "⇥" #f (Divide id "row"))
                                  (tool "" "pane-button" "Split down" "⤓" #f (Divide id "column"))
                                  (tool "" "pane-button" "Close pane" "×" #f (Close id))))
                   (editor-view model pane buffer)
                   (problem-view buffer)))))

(: pane-title (-> (Option Buffer) String))
(define (pane-title buffer)
  (match buffer
    ((Some found) (string-append (Buffer-path found) (if (dirty? found) " ●" "")))
    ((None) "Choose a file")))

(: problem-view (-> (Option Buffer) (Html Msg)))
(define (problem-view buffer)
  (let ((problem (match buffer
                   ((Some found)
                    (cond ((not (string=? (Buffer-failure found) "")) (Buffer-failure found))
                          ((not (string=? (Buffer-problem found) "")) (Buffer-problem found))
                          ((not (loaded? found)) "Loading…")
                          (else "")))
                   ((None) ""))))
    (Element "div"
             (list (Attr "class" "pane-problem") (FlagProperty "hidden" (string=? problem "")))
             (list (Text problem)))))

;; One scroller holds the gutter, the highlight and marks, and the field,
;; which is as big as its text, so they scroll together.
(: editor-view (-> Ide Pane (Option Buffer) (Html Msg)))
(define (editor-view model pane buffer)
  (let* ((id (Pane-id pane))
         (text (match buffer
                 ((Some found) (display-text (Buffer-text found)))
                 ((None) "")))
         (scheme (match buffer
                   ((Some found) (source-file? (Buffer-path found)))
                   ((None) #f)))
         (lines (match buffer
                  ((Some _) (+ (count-lines text 0 (string-length text)) 1))
                  ((None) 0))))
    (Element "div"
             (list (Attr "id" (scroller-id id))
                   (Attr "class" "editor")
                   (On "scroll"
                       (list (Scroll))
                       (Allow)
                       (lambda (event) (Scrolled id (Event-scroll-top event)))))
             (list (Element "div"
                            (list (Attr "class" "gutter"))
                            (list (Element "pre"
                                           (list (Attr "class" "numbers"))
                                           (list (Text (string-join
                                                        (map (lambda (line) (show (+ line 1)))
                                                             (iota lines))
                                                        newline-text))))))
                   (Element "div"
                            (list (Attr "class" "code"))
                            (list (highlight-view text (Pane-scroll pane) scheme)
                                  (marks-view text
                                              (match buffer
                                                ((Some found) (marked model found))
                                                ((None) (None))))
                                  (field-view id buffer text scheme lines)))))))

(: field-view (-> I64 (Option Buffer) String Bool I64 (Html Msg)))
(define (field-view id buffer text scheme lines)
  (Element "textarea"
           (append (list (Attr "id" (field-id id))
                         (Attr "spellcheck" "false")
                         (Attr "wrap" "off")
                         (Attr "autocapitalize" "off")
                         (Attr "rows" (show (max lines 1)))
                         (Attr "cols" (show (+ (longest-line text) 2)))
                         (FlagProperty "disabled"
                                       (match buffer
                                         ((Some found) (not (loaded? found)))
                                         ((None) #t)))
                         (StringProperty "value" text)
                         (On "input"
                             (list (Value))
                             (Allow)
                             (lambda (event) (Typed id (Event-value event))))
                         (On "focus" (Nil) (Allow) (lambda (event) (Focused id))))
                   (if scheme
                       (list (On "keydown"
                                 (list (Key) (Value) (Selection))
                                 (Chords editing-chords)
                                 (lambda (event)
                                   (Pressed id
                                            (Event-key event)
                                            (Event-value event)
                                            (Event-selection-start event)
                                            (Event-selection-end event)))))
                       (Nil)))
           (Nil)))

;; ---- Diagnostics and runs' views ----

(: diagnostics-view (-> Ide (Html Msg)))
(define (diagnostics-view model)
  (Element "div"
           (list (Attr "id" "diagnostics")
                 (Attr "class" "diagnostics")
                 (Attr "role" "status")
                 (FlagProperty "hidden" (null? (Ide-diagnostics model))))
           (map-indexed (lambda (index diagnostic) (diagnostic-view model index diagnostic))
                        (Ide-diagnostics model))))

;; A diagnostic in a project file is a button that shows its point.
(: diagnostic-view (-> Ide I64 Diagnostic (Html Msg)))
(define (diagnostic-view model index diagnostic)
  (let* ((source (Diagnostic-source diagnostic))
         (path (source-path (Ide-project model) source))
         (text (string-append (Diagnostic-severity diagnostic)
                              ": "
                              (match source
                                ((Some point)
                                 (string-append (match path
                                                  ((Some found) found)
                                                  ((None) (Point-file point)))
                                                ":"
                                                (show (Point-line point))
                                                ":"
                                                (show (Point-column point))
                                                ": "))
                                ((None) ""))
                              (Diagnostic-message diagnostic))))
    (match path
      ((Some _)
       (Element "button"
                (list (On "click"
                          (Nil)
                          (Allow)
                          (lambda (event) (Show (Ide-generation model) index))))
                (list (Text text))))
      ((None) (Element "div" (Nil) (list (Text text)))))))

(: runs-view (-> Runs (Html Msg)))
(define (runs-view runs)
  (let* ((run (selected-run runs))
         (pending (Runs-pending runs))
         (available (match run
                      ((Some found) (Run-available found))
                      ((None) #f)))
         (wanted (match run
                   ((Some found) (Run-wanted found))
                   ((None) #f)))
         (attempt (match run
                    ((Some found) (Run-attempt found))
                    ((None) (None))))
         (problem (Runs-problem runs)))
    (Element "section"
             (list (Attr "id" "runs")
                   (Attr "class" "runs")
                   (Attr "aria-label" "Applications")
                   (FlagProperty "hidden"
                                 (and (null? (Runs-runs runs))
                                      (not pending)
                                      (string=? problem ""))))
             (list (Element "div"
                            (list (Attr "class" "run-toolbar"))
                            (list (Element "label"
                                           (list (Attr "for" "run-target"))
                                           (list (Text "Application")))
                                  (Element "select"
                                           (list (Attr "id" "run-target")
                                                 (On "change"
                                                     (list (Value))
                                                     (Allow)
                                                     (lambda (event) (Choose (Event-value event)))))
                                           (map (lambda (found)
                                                  (option-view found (Runs-selected runs)))
                                                (Runs-runs runs)))
                                  (run-button "run-start"
                                              "Start"
                                              (or pending (not available) wanted)
                                              "start")
                                  (run-button "run-stop"
                                              "Stop"
                                              (or pending
                                                  (match run
                                                    ((Some _) #f)
                                                    ((None) #t)))
                                              "stop")
                                  (run-button "run-restart"
                                              "Restart"
                                              (or pending (not available))
                                              "restart")
                                  (Element "span"
                                           (list (Attr "id" "run-status") (Attr "role" "status"))
                                           (list (Text (run-description run))))))
                   (Element "p"
                            (list (Attr "id" "run-problem")
                                  (Attr "role" "alert")
                                  (FlagProperty "hidden" (string=? problem "")))
                            (list (Text problem)))
                   (Element "div"
                            (list (Attr "class" "run-output"))
                            (list (output-view "Standard output"
                                               "stdout"
                                               "run-stdout"
                                               (match attempt
                                                 ((Some found) (Attempt-stdout found))
                                                 ((None) "")))
                                  (output-view "Standard error"
                                               "stderr"
                                               "run-stderr"
                                               (match attempt
                                                 ((Some found) (Attempt-stderr found))
                                                 ((None) "")))))))))

(: option-view (-> Run String (Html Msg)))
(define (option-view run selected)
  (Element "option"
           (list (Keyed (Run-target run))
                 (Attr "value" (Run-target run))
                 (FlagProperty "selected" (string=? (Run-target run) selected)))
           (list (Text (string-append (Run-target run) (if (Run-available run) "" " (removed)"))))))

(: run-button (-> String String Bool String (Html Msg)))
(define (run-button id label disabled action)
  (Element "button"
           (list (Attr "id" id)
                 (Attr "class" "tool")
                 (FlagProperty "disabled" disabled)
                 (On "click" (Nil) (Allow) (lambda (event) (Control action))))
           (list (Text label))))

;; Output is text, never markup.
(: output-view (-> String String String String (Html Msg)))
(define (output-view label heading id text)
  (Element "section"
           (list (Attr "aria-label" label))
           (list (Element "h2" (Nil) (list (Text heading)))
                 (Element "pre" (list (Attr "id" id) (Attr "tabindex" "0")) (list (Text text))))))

;; While a drag is under way the page is covered, so the pointer's moves
;; reach the drag wherever they go.
(: drag-view (-> Ide (List (Html Msg))))
(define (drag-view model)
  (match (Ide-drag model)
    ((Some drag)
     (list (Element "div"
                    (list (Attr "class"
                                (match drag
                                  ((Dividing split _)
                                   (match (division-of (Ide-layout model) split)
                                     ((Some division)
                                      (string-append "drag-overlay " (Division-direction division)))
                                     ((None) "drag-overlay row")))
                                  ((Resizing _) "drag-overlay row")))
                          (On "pointermove"
                              (list (Pointer))
                              (Allow)
                              (lambda (event) (Dragged (Event-x event) (Event-y event))))
                          (On "pointerup" (Nil) (Allow) (lambda (event) (Dropped))))
                    (Nil))))
    ((None) (Nil))))

;; ---- The window ----

;; The shortcuts, going back online, which connects again, and, while a
;; draft has changes of its own, leaving the page, which asks first.
(: window (-> Ide (List (Attribute Msg))))
(define (window model)
  (append (list (On "keydown"
                    (list (Key))
                    (Chords shortcut-chords)
                    (lambda (event) (Shortcut (Event-key event))))
                (On "online" (Nil) (Allow) (lambda (event) (Connect))))
          (if (any? dirty? (Ide-buffers model))
              (list (On "beforeunload" (Nil) (Always) (lambda (event) (Nothing))))
              (Nil))))

;; ---- The interface ----

;; The editor keeps nothing across loads: drafts live in the page only, and
;; leaving with one asks first. Its save is empty.
(: kept (-> Ide Unit))
(define (kept model)
  (unit))

(: restored (-> Unit Ide))
(define (restored save)
  initial)

(define-ui Ide
  Msg
  (init: (lambda (seed) initial))
  (update: update)
  (view: view)
  (window: window)
  (start: (list (Connect)))
  (save: kept)
  (restore: restored))
