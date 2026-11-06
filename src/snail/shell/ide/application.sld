;; The browser IDE as a host-independent application. Its immutable model,
;; update and view run over the shared DOM and fetch effects, so a page and
;; Scheme tests exercise the same application loop. host/ide/ide.sld binds
;; the application to the page; feature libraries own their own services.
(define-library (snail shell ide application)
  (export Ide Msg initial update view window kept restored Connect Boot
          DispatchCommand InvokeCommand Typed Open Answered Saved Heard PaletteEvent
          Buffer
          Snapshot buffer-at dirty? conflict?)
  (import
   (snail core base)
   (only (snail shell text) string-upcase string-downcase)
   (only (snail shell task) tasks)
   (snail shell dom)
   (snail shell fetch)
   (snail shell json)
   (snail shell json read)
   (snail shell project client)
   (snail shell project protocol)
   (snail shell format)
   (snail shell highlight)
   (snail shell ui)
   (snail shell wire)
   (prefix (rename (snail shell ide palette) (open open-component) (view view-component)) palette-)
   (prefix (snail shell ide search) search-)
   (only (snail shell text search) Occurrence)
   (prefix (snail shell ui commands) command-)
   (prefix (snail shell ui shortcuts) shortcut-))
  (begin
    (type (Command M) (FnOnce M ! tasks dom fetch))

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
      (let ((taken (or (and (= (::start change) (::end change))
                            (string=? (::text change) ""))
                       (insert-text field
                                    (i64->i32 (::start change))
                                    (i64->i32 (::end change))
                                    (::text change)))))
        (when taken
          (select-range field
                        (i64->i32 (::selection-start change))
                        (i64->i32 (::selection-end change))))
        taken))

    ;; Tab reindents the caret's line, or every line the selection touches but
    ;; a last one it only reaches the start of. As in Emacs, a caret in the
    ;; indentation moves to the line's first character, and a caret in the
    ;; text stays with it; a selection then selects the lines.
    (: indent-change (-> String I64 I64 Change))
    (define (indent-change text from selected-to)
      (let* ((to
              (if (and (> selected-to from) (char=? (string-ref text (- selected-to 1)) #\newline))
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
        (indentation (lines-between (indent-lines (substring placed base end) line line) line line)
                     0)))

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
             (moved
              (min (+ (+ at (indentation formatted at)) (max 0 past)) (line-end formatted at))))
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
      (match (::baseline buffer)
        ((Some baseline) (not (string=? (::text buffer) (::text baseline))))
        ((None) #f)))

    ;; Disk has moved on from the contents the draft was made from.
    (: conflict? (-> Buffer Bool))
    (define (conflict? buffer)
      (match (Pair (::baseline buffer) (::observed buffer))
        ((Pair (Some baseline) (Some revision))
         (not (string=? revision (::revision baseline))))
        ((Pair (Some _) (None)) #t)
        (_ #f)))

    (: loaded? (-> Buffer Bool))
    (define (loaded? buffer)
      (match (::baseline buffer)
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
       (scroll F64))
      (deriving Serialize Deserialize))

    ;; How the panes share the room: one pane, or two nodes side by side
    ;; (`row`) or one above the other (`column`), the first taking `ratio` of
    ;; the room. A split has an id of its own, for dragging its divider.
    (enum Layout
      (Leaf ((pane I64)))
      (Split ((id I64)
              (direction String)
              (ratio F64)
              (first Layout)
              (second Layout)))
      (deriving Serialize Deserialize))

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
          (let ((first (* (::height area) ratio)))
            (Pair (Area-height-set area first)
                  (Area (::left area)
                        (+ (::top area) first)
                        (::width area)
                        (- (::height area) first))))
          (let ((first (* (::width area) ratio)))
            (Pair (Area-width-set area first)
                  (Area (+ (::left area) first)
                        (::top area)
                        (- (::width area) first)
                        (::height area))))))

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
      (find (lambda (division) (= (::split division) split)) (divisions layout whole)))

    ;; The layout with split `split` dividing at `ratio`, kept to a tenth of
    ;; the room either side.
    (: ratio-set (-> Layout I64 F64 Layout))
    (define (ratio-set layout split ratio)
      (match layout
        ((Leaf _) layout)
        ((Split id direction old first second)
         (if (= id split)
             (Split id direction (max 0.1 (min 0.9 ratio)) first second)
             (Split id
                    direction
                    old
                    (ratio-set first split ratio)
                    (ratio-set second split ratio))))))

    (: field-id (-> I64 String))
    (define (field-id pane)
      (string-append "text-" (show pane)))

    (: scroller-id (-> I64 String))
    (define (scroller-id pane)
      (string-append "editor-" (show pane)))

    ;; ---- Builds ----

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

    (: diagnostic-of (-> Report Diagnostic))
    (define (diagnostic-of report)
      (Diagnostic (::severity report)
                  (::message report)
                  (::source report)
                  (Unobserved)))

    ;; The compiler's status as the status bar shows it: its words, its state for
    ;; styling (`starting`, `building`, `built` or `failed`), and the attempt
    ;; it reports.
    (struct Status
      ((text String)
       (state String)
       (attempt String)))

    (: compiler-status (-> Build Status))
    (define (compiler-status build)
      (let ((phase (::phase build)))
        (Status (cond ((string=? phase "starting") "Starting the compiler…")
                      ((string=? phase "building") "Building…")
                      ((string=? phase "succeeded") "Built")
                      ((string=? phase "failed") "Build failed")
                      ((string=? phase "fatal") "Compiler stopped")
                      (else phase))
                (cond ((or (string=? phase "failed") (string=? phase "fatal")) "failed")
                      ((string=? phase "succeeded") "built")
                      (else phase))
                (show (::id build)))))

    ;; ---- Runs ----

    ;; The run targets, the one chosen, whether a command to it is in flight,
    ;; and what the last command did wrong.
    (struct Runs
      ((runs (List Run))
       (selected String)
       (pending Bool)
       (problem String)))

    ;; Keep the selected run while it remains in the complete server snapshot.
    (: runs-received (-> Runs (List Run) Runs))
    (define (runs-received runs list)
      (Runs-selected-set (Runs-runs-set runs list) (chosen list (::selected runs))))

    (: chosen (-> (List Run) String String))
    (define (chosen runs selected)
      (if (any? (lambda (run) (string=? (::target run) selected)) runs)
          selected
          (match (find ::available runs)
            ((Some run) (::target run))
            ((None) (match runs
                      ((Cons run _) (::target run))
                      ((Nil) ""))))))

    (: selected-run (-> Runs (Option Run)))
    (define (selected-run runs)
      (find (lambda (run) (string=? (::target run) (::selected runs))) (::runs runs)))

    ;; What was asked of a run and what was seen of it.
    (: run-description (-> (Option Run) String))
    (define (run-description found)
      (match found
        ((Some run)
         (string-append (if (::available run) "" "Removed · ")
                        "Requested: "
                        (match (::desired run)
                          ((Some build) (string-append "build " (show build)))
                          ((None) "stop"))
                        " · Observed: "
                        (match (::attempt run)
                          ((Some attempt) (attempt-description attempt))
                          ((None) "no process"))))
        ((None) "No run targets")))

    (: attempt-description (-> Attempt String))
    (define (attempt-description attempt)
      (string-append (::phase attempt)
                     ", build "
                     (show (::build attempt))
                     (match (::pid attempt)
                       ((Some pid) (string-append ", PID " (show pid)))
                       ((None) ""))
                     (cond ((not (string=? (::signal attempt) ""))
                            (string-append " · " (::signal attempt)))
                           (else (match (::code attempt)
                                   ((Some code) (string-append " · exit " (show code)))
                                   ((None) ""))))
                     (if (string=? (::error attempt) "")
                         ""
                         (string-append " · " (::error attempt)))))

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
       (navigation I64)
       (follow Follow)))

    ;; What opening a file asks once its read has answered: nothing, to focus
    ;; the pane that shows it, or also to put its caret at a diagnostic's
    ;; point, the one at `index` of status `generation`.
    (enum Follow
      (Stay)
      (Focus ((pane I64)))
      (Reveal ((pane I64)
               (generation I64)
               (index I64)))
      (SearchPoint ((pane I64)
                    (hit Hit))))

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
    ;; id for a pane or split; the folders explicitly expanded; whether the files are
    ;; shown, and how wide; a drag; the compiler's status, the last server
    ;; snapshot, how many different build reports have come, and their diagnostics;
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
       (expanded (List String))
       (files-shown Bool)
       (files-width F64)
       (drag (Option Drag))
       (palette palette-State)
       (auto-open Bool)
       (status Status)
       (server (Option ServerState))
       (generation I64)
       (diagnostics (List Diagnostic))
       (runs Runs)
       (events (Option Stream))
       (editor String)
       (refreshing Bool)))

    (: initial Ide)
    (define initial
      (Ide (Project "" "" (Nil) (Nil))
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
           palette-initial
           #t
           (Status "Connecting…" "starting" "")
           (None)
           0
           (Nil)
           (Runs (Nil) "" #f "")
           (None)
           ""
           #f))

    (: buffer-at (-> Ide String (Option Buffer)))
    (define (buffer-at model path)
      (find (lambda (buffer) (string=? (::path buffer) path)) (::buffers model)))

    ;; The model with `buffer` in place of the one at its path, or added.
    (: buffer-set (-> Ide Buffer Ide))
    (define (buffer-set model buffer)
      (let ((path (::path buffer)))
        (Ide-buffers-set model
                         (match (buffer-at model path)
                           ((Some _)
                            (map (lambda (old) (if (string=? (::path old) path) buffer old))
                                 (::buffers model)))
                           ((None) (append (::buffers model) (list buffer)))))))

    ;; The buffer at `path` closed, and the panes that showed it empty.
    (: buffer-removed (-> Ide String Ide))
    (define (buffer-removed model path)
      (Ide-panes-set (Ide-buffers-set model
                                      (filter
                                       (lambda (buffer) (not (string=? (::path buffer) path)))
                                       (::buffers model)))
                     (map (lambda (pane)
                            (if (shows? pane path) (Pane-path-set pane (None)) pane))
                          (::panes model))))

    (: shows? (-> Pane String Bool))
    (define (shows? pane path)
      (match (::path pane)
        ((Some shown) (string=? shown path))
        ((None) #f)))

    (: pane-of (-> Ide I64 Pane))
    (define (pane-of model id)
      (match (find (lambda (pane) (= (::id pane) id)) (::panes model))
        ((Some pane) pane)
        ((None) (Pane id (None) 0.0))))

    (: pane-set (-> Ide Pane Ide))
    (define (pane-set model changed)
      (Ide-panes-set model
                     (map (lambda (pane) (if (= (::id pane) (::id changed)) changed pane))
                          (::panes model))))

    (: pane-buffer (-> Ide I64 (Option Buffer)))
    (define (pane-buffer model id)
      (match (::path (pane-of model id))
        ((Some path) (buffer-at model path))
        ((None) (None))))

    (: active-buffer (-> Ide (Option Buffer)))
    (define (active-buffer model)
      (pane-buffer model (::active model)))

    ;; The active pane shows the file at `path`.
    (: showing? (-> Ide I64 String Bool))
    (define (showing? model pane path)
      (and (= pane (::active model))
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
         (let ((prefix (if (ends-with? (::directory project) "/")
                           (::directory project)
                           (string-append (::directory project) "/")))
               (file (::file point)))
           (if (starts-with? file prefix)
               (let ((path (substring file (string-length prefix) (string-length file))))
                 (if (member? path (::files project)) (Some path) (None)))
               (None))))
        ((None) (None))))

    ;; The index of the first diagnostic at the file at `path`.
    (: diagnostic-index (-> Ide String (Option I64)))
    (define (diagnostic-index model path)
      (list-index (lambda (diagnostic)
                    (match (source-path (::project model) (::source diagnostic))
                      ((Some found) (string=? found path))
                      ((None) #f)))
                  (::diagnostics model)))

    (: observation-at (-> Ide (Option I64) Observation))
    (define (observation-at model index)
      (match index
        ((Some at) (::observation (list-ref (::diagnostics model) at)))
        ((None) (Unobserved))))

    (: observation-set (-> Ide I64 Observation Ide))
    (define (observation-set model index observation)
      (Ide-diagnostics-set model
                           (map-indexed (lambda (at diagnostic)
                                          (if (= at index)
                                              (Diagnostic-observation-set diagnostic observation)
                                              diagnostic))
                                        (::diagnostics model))))

    ;; The diagnostic whose point a pane showing the buffer marks: only while
    ;; the buffer is its disk contents, and only when the buffer's latest read
    ;; confirmed the revision the diagnostic was made from.
    (: marked (-> Ide Buffer (Option Diagnostic)))
    (define (marked model buffer)
      (match (Pair (::baseline buffer) (diagnostic-index model (::path buffer)))
        ((Pair (Some baseline) (Some index))
         (let ((diagnostic (list-ref (::diagnostics model) index)))
           (match (::observation diagnostic)
             ((Observed revision sequence)
              (if (and (not (dirty? buffer))
                       (not (conflict? buffer))
                       (string=? revision (::revision baseline))
                       (= sequence (::read buffer)))
                  (Some diagnostic)
                  (None)))
             (_ (None)))))
        (_ (None))))

    (: failed-status (-> Ide String Status))
    (define (failed-status model message)
      (Status message "failed" (::attempt (::status model))))

    ;; ---- Messages ----

    (enum Msg
      (Boot)
      (Booted ((generation String)))
      (RefreshFailed)
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
      (Saved ((path String)
              (result (Result Snapshot Failure))))
      (Formatted ((path String)
                  (taken Bool)))
      (Discard ((path String)))
      (Refused ((failure Failure)))
      (Close ((pane I64)))
      (CloseReady ((pane I64)
                   (path String)
                   (text String)))
      (InstallFinished ((result InstallResult)))
      (FullscreenFinished ((accepted Bool)))
      (DispatchCommand ((name String)))
      (InvokeCommand ((name String)))
      (PaletteEvent ((message palette-Message)))
      (ToggleFolder ((path String)))
      (Grab ((grip Grip)))
      (Grabbed ((drag Drag)))
      (Dragged ((x F64)
                (y F64)))
      (Dropped)
      (Shortcut ((key String)
                 (modifiers I32)))
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
      (then (update-message model message) reconcile-palette))

    (: update-message (-> Ide Msg Step))
    (define (update-message model message)
      (match message
        ((Boot)
         (Pair model
               (list
                (once (lambda () (Booted (string-property (document-root) "snailGeneration")))))))
        ((Booted generation)
         (refresh-if-needed (if (string=? (::editor model) "")
                                (Ide-editor-set model generation) model)))
        ((RefreshFailed) (stay (Ide-refreshing-set model #f)))
        ((Nothing) (stay model))
        ((Connect) (connecting model))
        ((Connected stream) (Pair (Ide-events-set model (Some stream)) (list (hear stream))))
        ((Heard stream event)
         (if (current-stream? model stream) (heard model stream event) (stay model)))
        ((Ended) (stay model))
        ((Listed sequence result) (listed model sequence result))
        ((Open path) (opening (search-invalidated model) path (Focus (::active model))))
        ((Show generation index) (showing-diagnostic (search-invalidated model) generation index))
        ((Answered asked result) (answered model asked result))
        ((Typed pane text) (typed model pane text))
        ((Pressed pane key text start end) (pressed model pane key text start end))
        ((Focused pane)
         (stay
          (Ide-active-set (if (= pane (::active model)) model (search-invalidated model)) pane)))
        ((Scrolled pane top) (stay (pane-set model (Pane-scroll-set (pane-of model pane) top))))
        ((Saved path result) (saved model path result))
        ((Formatted path taken) (formatted model path taken))
        ((Discard path) (discarded model path))
        ((Refused failure)
         (stay (Ide-status-set model (failed-status model (::message failure)))))
        ((Close pane) (invoked (Ide-active-set model pane) closing))
        ((CloseReady pane path text) (close-ready model pane path text))
        ((InstallFinished result) (installation-finished model result))
        ((FullscreenFinished accepted)
         (if accepted (stay model)
             (notice model
                     "Fullscreen needs an explicit click or is unavailable in this browser.")))
        ((DispatchCommand name) (Pair model (list (once (lambda () (InvokeCommand name))))))
        ((InvokeCommand name) (run-command model name))
        ((PaletteEvent message) (palette-message model message))
        ((ToggleFolder path) (stay (Ide-expanded-set model (toggled (::expanded model) path))))
        ((Grab grip) (Pair model (list (once (lambda () (grabbed grip))))))
        ((Grabbed drag) (stay (Ide-drag-set model (Some drag))))
        ((Dragged x y) (stay (dragged model x y)))
        ((Dropped) (stay (Ide-drag-set model (None))))
        ((Shortcut key modifiers) (shortcut model key modifiers))
        ((Choose target) (stay (Ide-runs-set model (Runs-selected-set (::runs model) target))))
        ((Control action) (controlling model action))
        ((Controlled action target result) (controlled model action target result))))

    ;; ---- Events ----

    ;; The service's event stream: the compiler's status, the run targets'
    ;; processes, a sign that files changed, and each dropped connection.
    (: event-kinds (List String))
    (define event-kinds
      (list event-kind "open" "error"))

    ;; Connecting closes the stream before, so none of its events, sent or
    ;; not, is heard again.
    (: connecting (-> Ide Step))
    (define (connecting model)
      (let ((old (::events model)))
        (Pair (Ide-status-set (Ide-events-set model (None))
                              (Status "Connecting…" "starting" (::attempt (::status model))))
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
      (match (::events model)
        ((Some current) (= (::id current) (::id stream)))
        ((None) #f)))

    ;; Every connection, including EventSource reconnections, refreshes reads
    ;; and listings. Their new intent numbers reject delayed old replies.
    ;; The next event is heard after this one. Bad messages leave the last
    ;; complete snapshot intact and make the protocol failure visible.
    (: heard (-> Ide Stream StreamEvent Step))
    (define (heard model stream event)
      (then (Pair model (list (hear stream)))
            (lambda (model)
              (cond ((string=? (::kind event) "open") (reconnected model))
                    ((string=? (::kind event) event-kind)
                     (match (read-event (::data event))
                       ((Some state) (then (received model state) refresh-if-needed))
                       ((None)
                        (stay
                         (Ide-status-set model (failed-status model "Invalid server snapshot"))))))
                    (else
                     (stay (Ide-status-set model
                                           (failed-status model
                                                          "Connection lost; reconnecting…"))))))))

    (: reconnected (-> Ide Step))
    (define (reconnected model)
      (then (listing model) (lambda (model) (palette-message model (palette-Reconnected)))))

    ;; The stream is ordered and reconnection starts with a complete snapshot.
    ;; Only a new build report resets diagnostic evidence; process output and
    ;; repeated snapshots cannot revive a diagnostic invalidated by a save.
    (: received (-> Ide ServerState Step))
    (define (received model state)
      (let* ((old (::server model))
             (new-server (match old
                           ((Some previous) (not (string=? (::instance previous)
                                                           (::instance state))))
                           ((None) #t)))
             (files (or new-server (match old
                                     ((Some previous) (not (= (::files previous)
                                                              (::files state))))
                                     ((None) #t))))
             (fresh (or new-server (match old
                                     ((Some previous)
                                      (not (string=?
                                            (json->string
                                             (build->json (::build previous)))
                                            (json->string
                                             (build->json (::build state))))))
                                     ((None) #t))))
             (model (received-build model (::build state) fresh))
             (model (Ide-server-set (Ide-runs-set model (runs-received (::runs model)
                                                                       (::runs state)))
                                    (Some state))))
        (cond (files (listing model))
              ((and fresh (not (null? (::diagnostics model)))) (reading-all model))
              (else (stay model)))))

    (: received-build (-> Ide Build Bool Ide))
    (define (received-build model build fresh)
      (Ide-status-set
       (if fresh
           (Ide-diagnostics-set (Ide-generation-set model (+ (::generation model) 1))
                                (map diagnostic-of (::diagnostics build)))
           model)
       (compiler-status build)))

    ;; A successful server generation is the only reason to auto-refresh.
    ;; Record the attempted generation so a storage refusal does not retry on
    ;; every process-output event. The explicit command can retry at any time.
    (: refresh-if-needed (-> Ide Step))
    (define (refresh-if-needed model)
      (match (::server model)
        ((Some state)
         (cond ((not (string=? (::editor-problem state) ""))
                (stay (Ide-status-set model
                                      (failed-status model (string-append "IDE update failed: "
                                                                          (::editor-problem
                                                                           state))))))
               ((and (not (string=? (::editor model) "")) (not (::refreshing model))
                     (not (string=? (::editor model) (::editor state))))
                (refreshing (Ide-editor-set model (::editor state))))
               (else (stay model))))
        ((None) (stay model))))

    (: refreshing (-> Ide Step))
    (define (refreshing model)
      (Pair (Ide-refreshing-set model #t)
            (list (once (lambda () (refresh-page) (Nothing))))))

    ;; ---- Files ----

    ;; Files changed: every open buffer is read again, and the project listed.
    (: listing (-> Ide Step))
    (define (listing model)
      (let ((sequence (+ (::listing model) 1)))
        (then (reading-all (Ide-listing-set model sequence))
              (lambda (model)
                (Pair model
                      (list (once (lambda ()
                                    (Listed sequence
                                            (project-reply
                                             (api "GET" "/api/project" (Nil) "")))))))))))

    ;; Only the latest listing counts. The first nonempty project listing
    ;; opens main.sld or its first file; explicit closes never reopen a file.
    (: listed (-> Ide I64 (Result Project Failure) Step))
    (define (listed model sequence result)
      (if (= sequence (::listing model))
          (match result
            ((Ok project)
             (let ((model (Ide-project-set model project)))
               (match (::files project)
                 ((Cons first _)
                  (if (::auto-open model)
                      (opening model
                               (if (member? "main.sld" (::files project)) "main.sld" first)
                               (Focus (::active model)))
                      (stay model)))
                 ((Nil) (stay model)))))
            ((Err failure)
             (stay (Ide-status-set model (failed-status model (::message failure))))))
          (stay model)))

    ;; Opening shows the file's buffer in the active pane at once, made empty
    ;; when it is new, and reads it when it has nothing from disk yet or a
    ;; diagnostic's point is to be found in it.
    (: opening (-> Ide String Follow Step))
    (define (opening model path follow)
      (let* ((model (Ide-auto-open-set model #f))
             (model (match (buffer-at model path)
                      ((Some _) model)
                      ((None) (buffer-set model (new-buffer path)))))
             (model
              (pane-set model (Pane-path-set (pane-of model (::active model)) (Some path)))))
        (match (buffer-at model path)
          ((Some buffer)
           (match follow
             ((Reveal _ _ _) (reading model path follow))
             ((SearchPoint _ _) (reading model path follow))
             (_ (if (loaded? buffer)
                    (Pair model (followed model path follow
                                          (::generation (::palette model)) (None)))
                    (reading model path follow)))))
          ((None) (stay model)))))

    (: showing-diagnostic (-> Ide I64 I64 Step))
    (define (showing-diagnostic model generation index)
      (if (= generation (::generation model))
          (match (source-path (::project model)
                              (::source (list-ref (::diagnostics model) index)))
            ((Some path) (opening model path (Reveal (::active model) generation index)))
            ((None) (stay model)))
          (stay model)))

    ;; What opening asked, once the file's read has answered, while the pane
    ;; that asked is active and still shows the file. A point is revealed only
    ;; when the diagnostic is still the one the pane marks.
    (: followed (-> Ide String Follow I64 (Option Snapshot) (List (Command Msg))))
    (define (followed model path follow navigation confirmed)
      (if (or (palette-visible? (::palette model))
              (not (= navigation (::generation (::palette model))))) (Nil)
              (match follow
                ((Stay) (Nil))
                ((SearchPoint pane hit) (search-followed model pane hit confirmed))
                ((Focus pane) (if (showing? model pane path) (list (focusing model pane)) (Nil)))
                ((Reveal pane generation index)
                 (if (showing? model pane path)
                     (match confirmed
                       ((Some _)
                        (match (revealed model path generation index)
                          ((Some point)
                           (list (revealing model pane path (shown-text model path) point)))
                          ((None) (list (focusing model pane)))))
                       ((None) (list (focusing model pane))))
                     (Nil))))))

    (: revealed (-> Ide String I64 I64 (Option Point)))
    (define (revealed model path generation index)
      (match (buffer-at model path)
        ((Some buffer)
         (match (Pair (marked model buffer) (diagnostic-index model path))
           ((Pair (Some diagnostic) (Some at))
            (if (and (= generation (::generation model)) (= at index))
                (::source diagnostic)
                (None)))
           (_ (None))))
        ((None) (None))))

    (: shown-text (-> Ide String String))
    (define (shown-text model path)
      (match (buffer-at model path)
        ((Some buffer) (display-text (::text buffer)))
        ((None) "")))

    (: focusing (-> Ide I64 (Command Msg)))
    (define (focusing model pane)
      (let ((navigation (::generation (::palette model)))
            (id (match (pane-buffer model pane)
                  ((Some buffer) (if (loaded? buffer) (field-id pane) "commands"))
                  ((None) "commands"))))
        (once (lambda ()
                (when (navigation-current? navigation)
                  (match (element-by-id id)
                    ((Some node) (focus-node node))
                    ((None) (unit))))
                (Nothing)))))

    ;; The caret at a diagnostic's point, its line scrolled a few lines below
    ;; the top.
    (: revealing (-> Ide I64 String String Point (Command Msg)))
    (define (revealing model pane path text point)
      (let ((navigation (::generation (::palette model))))
        (once (lambda ()
                (match (element-by-id (field-id pane))
                  ((Some field)
                   (when (and (navigation-current? navigation) (current-field? field path text))
                     (let ((offset (source-offset text point)))
                       (focus-node field)
                       (select-range field (i64->i32 offset) (i64->i32 offset))
                       (scrolled-to pane
                                    (* line-height
                                       (i64->f64 (max 0 (- (count-lines text 0 offset) 4))))))))
                  ((None) (unit)))
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
         (if (::saving buffer)
             (Pair model (followed model path follow
                                   (::generation (::palette model)) (None)))
             (let* ((sequence (+ (::reads model) 1))
                    (index (diagnostic-index model path))
                    (asked (Asked path
                                  sequence
                                  (::generation model)
                                  index
                                  (observation-at model index)
                                  (::generation (::palette model))
                                  follow)))
               (Pair (buffer-set (Ide-reads-set model sequence) (Buffer-read-set buffer sequence))
                     (list (once (lambda ()
                                   (Answered asked
                                             (file-reply
                                              (api "GET" (file-url path) (Nil) ""))))))))))
        ((None) (Pair model (followed model path follow
                                      (::generation (::palette model)) (None))))))

    (: reading-all (-> Ide Step))
    (define (reading-all model)
      (fold-left (lambda (step path) (then step (lambda (model) (reading model path (Stay)))))
                 (stay model)
                 (map ::path (::buffers model))))

    ;; Only the latest successful read confirms coordinates. An obsolete reply
    ;; must not revive a search hit merely because the cached baseline matches.
    (: answered (-> Ide Asked (Result Snapshot Failure) Step))
    (define (answered model asked result)
      (let* ((path (::path asked))
             (confirmed (read-confirmation model asked result))
             (next (match (buffer-at model path)
                     ((Some buffer)
                      (if (= (::read buffer) (::sequence asked))
                          (match result
                            ((Ok snapshot)
                             (snapshot-read (bound model asked snapshot) buffer snapshot))
                            ((Err failure) (read-failed model buffer failure))) model))
                     ((None) model))))
        (Pair next (followed next path (::follow asked) (::navigation asked) confirmed))))

    (: read-confirmation (-> Ide Asked (Result Snapshot Failure) (Option Snapshot)))
    (define (read-confirmation model asked result)
      (match (Pair (buffer-at model (::path asked)) result)
        ((Pair (Some buffer) (Ok snapshot))
         (if (= (::read buffer) (::sequence asked)) (Some snapshot) (None)))
        (_ (None))))

    ;; The draft follows disk unless it has changes of its own.
    (: snapshot-read (-> Ide Buffer Snapshot Ide))
    (define (snapshot-read model buffer snapshot)
      (let* ((observed (Buffer-observed-set buffer (Some (::revision snapshot))))
             (loaded (if (dirty? buffer)
                         observed
                         (Buffer-baseline-set (Buffer-text-set observed (::text snapshot))
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
      (if (= (::status failure) 404)
          (let ((gone
                 (Buffer-problem-set (Buffer-observed-set buffer (None))
                                     (::message failure))))
            (if (dirty? gone)
                (buffer-set model
                            (Buffer-problem-set gone
                                                "Deleted on disk. Your draft is kept; copy it before reloading."))
                (buffer-removed model (::path buffer))))
          (buffer-set model (Buffer-problem-set buffer (::message failure)))))

    ;; A read ties the diagnostic at its file to the revision it found, when
    ;; that is the diagnostic that was there when it was asked, and reads had
    ;; then said nothing of its text or said that same revision.
    (: bound (-> Ide Asked Snapshot Ide))
    (define (bound model asked snapshot)
      (match (Pair (::diagnostic asked) (diagnostic-index model (::path asked)))
        ((Pair (Some index) (Some now))
         (if (and (= index now)
                  (= (::generation asked) (::generation model))
                  (match (::observation asked)
                    ((Unobserved) #t)
                    ((Observed revision _) (string=? revision (::revision snapshot)))
                    ((Invalidated) #f)))
             (observation-set model
                              index
                              (Observed (::revision snapshot) (::sequence asked)))
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
                   (reading (buffer-set model edited) (::path edited) (Stay))
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
         (match (::baseline buffer)
           ((Some baseline)
            (if (::saving buffer)
                (stay model)
                (let* ((sequence (+ (::reads model) 1))
                       (model (match (diagnostic-index model (::path buffer))
                                ((Some index) (observation-set model index (Invalidated)))
                                ((None) model)))
                       (pane (pane-of model (::active model))))
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
      (let* ((path (::path buffer))
             (text
              (if (source-file? path)
                  (formatted-in pane (::path buffer) (::text buffer))
                  (::text buffer))))
        (Saved path
               (file-reply (api "PUT"
                                (file-url path)
                                (list (Header "Content-Type" "text/plain; charset=utf-8")
                                      (Header "If-Match"
                                              (string-append "\""
                                                             (::revision baseline)
                                                             "\"")))
                                text)))))

    ;; The text formatted in the pane's field as typing would, which the
    ;; field's input brings to the buffer too; or the text as it was, when the
    ;; field did not take it.
    (: formatted-in (-> Pane String String String ! dom))
    (define (formatted-in pane path text)
      (let* ((shown (display-text text)) (formatted (format-source shown format-width)))
        (if (or (string=? shown formatted) (not (reformatted pane path shown formatted)))
            text
            formatted)))

    ;; The change keeps the caret's line, and the field its scroll.
    (: reformatted (-> Pane String String String Bool ! dom))
    (define (reformatted pane path shown formatted)
      (match (element-by-id (field-id (::id pane)))
        ((Some field)
         (if (current-field? field path shown)
             (let ((taken (apply-change field
                                        (format-change shown formatted
                                                       (i32->i64
                                                        (::first (selection-range field)))))))
               (scrolled-to (::id pane) (::scroll pane))
               taken)
             #f))
        ((None) #f)))

    (: current-field? (-> Node String String Bool ! dom))
    (define (current-field? field path text)
      (and (string=? (string-property field "snailPath") path)
           (string=? (string-property field "value") text)))

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
                                                       (Some (::revision snapshot))))
                                 ((Err failure)
                                  (Buffer-failure-set buffer
                                                      (if (= (::status failure) 409)
                                                          "Changed on disk; save rejected. Your draft is kept."
                                                          (::message failure)))))
                               #f))
                  path
                  (Stay)))
        ((None) (stay model))))

    (: formatting (-> Ide Step))
    (define (formatting model)
      (match (active-buffer model)
        ((Some buffer)
         (if (and (loaded? buffer) (source-file? (::path buffer)))
             (let ((pane (pane-of model (::active model))) (path (::path buffer)))
               (Pair (buffer-set model (Buffer-failure-set buffer ""))
                     (list (once (lambda ()
                                   (let* ((shown (display-text (::text buffer)))
                                          (formatted (format-source shown format-width)))
                                     (Formatted path
                                                (or (string=? shown formatted)
                                                    (reformatted pane path shown formatted)))))))))
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
         (cond ((::saving buffer) (stay model))
               ((dirty? buffer)
                (Pair model
                      (list (once (lambda ()
                                    (if (confirm
                                         "Discard this file’s unsaved changes and reload from disk?")
                                        (Discard (::path buffer))
                                        (Nothing)))))))
               (else (discarded model (::path buffer)))))
        ((None) (stay model))))

    (: discarded (-> Ide String Step))
    (define (discarded model path)
      (match (buffer-at model path)
        ((Some buffer)
         (reading (buffer-set model
                              (Buffer-failure-set (match (::baseline buffer)
                                                    ((Some baseline)
                                                     (Buffer-text-set buffer
                                                                      (::text baseline)))
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
      (let* ((active (::active model))
             (pane (::next model))
             (split (Split (+ pane 1) direction 0.5 (Leaf active) (Leaf pane)))
             (model (Ide-panes-set model
                                   (append (::panes model)
                                           (list
                                            (Pane pane (::path (pane-of model active)) 0.0)))))
             (model (Ide-layout-set model (leaf-replaced (::layout model) active split))))
        (Pair (Ide-next-set (Ide-active-set model pane) (+ pane 2)) (list (focusing model pane)))))

    ;; Closing the last view of a draft asks before discarding it. A reply
    ;; names the exact draft it was for; it cannot discard subsequent typing.
    (: closing (-> Ide Step))
    (define (closing model)
      (match (active-buffer model)
        ((None) (close-pane model))
        ((Some buffer)
         (let ((path (::path buffer)) (pane (::active model)))
           (cond ((::saving buffer) (stay model))
                 ((other-view? model pane path)
                  (close-pane model))
                 ((dirty? buffer)
                  (Pair model (list (once (lambda ()
                                            (if (confirm
                                                 (string-append "Discard unsaved changes to "
                                                                path
                                                                "?"))
                                                (CloseReady pane path (::text buffer))
                                                (Nothing)))))))
                 (else (close-pane (buffer-removed model path))))))))

    (: close-ready (-> Ide I64 String String Step))
    (define (close-ready model pane path text)
      (match (buffer-at model path)
        ((Some buffer)
         (if (and (showing? model pane path) (not (::saving buffer))
                  (string=? text (::text buffer)))
             (close-pane (if (other-view? model pane path) model (buffer-removed model path)))
             (stay model)))
        ((None) (stay model))))

    (: other-view? (-> Ide I64 String Bool))
    (define (other-view? model pane path)
      (any? (lambda (other) (and (not (= pane (::id other))) (shows? other path)))
            (::panes model)))

    ;; The active pane's sibling takes its place. The last pane stays empty.
    (: close-pane (-> Ide Step))
    (define (close-pane model)
      (let ((active (::active model)))
        (match (sibling (::layout model) active)
          ((Some beside)
           (let* ((next (first-leaf beside))
                  (model (Ide-layout-set model (without-leaf (::layout model) active)))
                  (model (Ide-panes-set model
                                        (filter (lambda (pane) (not (= (::id pane) active)))
                                                (::panes model)))))
             (Pair (Ide-active-set model next) (list (focusing model next)))))
          ((None)
           (let ((empty (pane-set model (Pane-path-set (pane-of model active) (None)))))
             (Pair empty (list (focusing empty active))))))))

    (: toggled (-> (List String) String (List String)))
    (define (toggled paths path)
      (if (member? path paths)
          (filter (lambda (other) (not (string=? other path))) paths)
          (Cons path paths)))

    ;; A drag measures what it divides as it begins.
    (: grabbed (-> Grip Msg ! dom))
    (define (grabbed grip)
      (match grip
        ((FilesEdge) (Grabbed (Resizing (::width (measured "workbench")))))
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
      (match (::drag model)
        ((Some (Resizing width)) (Ide-files-width-set model (max 120.0 (min (* width 0.7) x))))
        ((Some (Dividing split box))
         (match (division-of (::layout model) split)
           ((Some division)
            (Ide-layout-set model (ratio-set (::layout model) split (pointed division box x y))))
           ((None) model)))
        ((None) model)))

    ;; Where the pointer lies across the split, in the room's box on the page.
    (: pointed (-> Division Measure F64 F64 F64))
    (define (pointed division box x y)
      (let ((area (::area division)))
        (if (string=? (::direction division) "column")
            (/ (- y (+ (::top box) (* (::top area) (::height box))))
               (* (::height area) (::height box)))
            (/ (- x (+ (::left box) (* (::left area) (::width box))))
               (* (::width area) (::width box))))))

    ;; ---- Commands ----

    ;; Commands have names and functions; keyboard policy maps chords to names.
    ;; Every entry point schedules invocation through the application loop.
    ;; macOS can report lowercase letters with Command+Shift. Bind both cases
    ;; with the same modifiers, so the browser and the dispatcher agree.
    (: primary-chords (-> String I32 (List Chord)))
    (define (primary-chords key extra)
      (concatenate
       (map (lambda (spelling)
              (map (lambda (held) (Chord spelling (+ held extra))) (list control-key meta-key)))
            (delete-duplicates string=? (list (string-upcase key) (string-downcase key))))))

    (: commands (command-Registry (-> Ide Step)))
    (define commands
      (match (command-register
              (list->vector (list (command-Command "command-palette"
                                                   (lambda (model)
                                                     (palette-open model (palette-Commands))))
                                  (command-Command "go-to-file"
                                                   (lambda (model)
                                                     (palette-open model (palette-Files))))
                                  (command-Command "search-project"
                                                   (lambda (model)
                                                     (palette-open model (palette-Searching
                                                                          (palette-Search
                                                                           (search-SavedProject)
                                                                           (palette-Debouncing))))))
                                  (command-Command "search-buffer" search-buffer)
                                  (command-Command "new-file"
                                                   (lambda (model)
                                                     (palette-open model
                                                                   (palette-Creating
                                                                    (palette-Creation #f #f "")))))
                                  (command-Command "new-directory"
                                                   (lambda (model)
                                                     (palette-open model
                                                                   (palette-Creating
                                                                    (palette-Creation #t #f "")))))
                                  (command-Command "install-app" installing)
                                  (command-Command "toggle-fullscreen" (lambda (model)
                                                                         (Pair model
                                                                               (list
                                                                                (once (lambda ()
                                                                                        (FullscreenFinished
                                                                                         (set-fullscreen
                                                                                          (not
                                                                                           (fullscreen?))))))))))
                                  (command-Command "save-buffer" saving)
                                  (command-Command "format-buffer" formatting)
                                  (command-Command "refresh-ide" refreshing)
                                  (command-Command "reload-buffer" reloading)
                                  (command-Command "build-project"
                                                   (lambda (model)
                                                     (Pair model (list (once building)))))
                                  (command-Command "toggle-files" (lambda (model)
                                                                    (stay
                                                                     (Ide-files-shown-set model
                                                                                          (not
                                                                                           (::files-shown
                                                                                            model))))))
                                  (command-Command "split-right"
                                                   (lambda (model) (divided model "row")))
                                  (command-Command "split-down"
                                                   (lambda (model) (divided model "column")))
                                  (command-Command "close-editor" closing))))
        ((Ok registry) registry)
        ((Err message) (panic message))))

    (: bound-chords (-> String (List Chord) (List shortcut-Binding)))
    (define (bound-chords name chords)
      (map (lambda (chord) (shortcut-Binding chord name)) chords))

    (: shortcuts shortcut-Shortcuts)
    (define shortcuts
      (match (shortcut-register
              (vector-map ::name (::commands commands))
              (list->vector (concatenate (list (bound-chords "command-palette"
                                                             (Cons (Chord "F1" 0)
                                                                   (primary-chords "P" shift-key)))
                                               (bound-chords "go-to-file" (primary-chords "p" 0))
                                               (bound-chords "search-project"
                                                             (primary-chords "F" shift-key))
                                               (bound-chords "search-buffer" (primary-chords "f" 0))
                                               (bound-chords "new-file" (Nil))
                                               (bound-chords "new-directory" (Nil))
                                               (bound-chords "install-app" (Nil))
                                               (bound-chords "toggle-fullscreen" (Nil))
                                               (bound-chords "save-buffer" (primary-chords "s" 0))
                                               (bound-chords "format-buffer"
                                                             (list
                                                              (Chord "F" (+ alt-key shift-key))))
                                               (bound-chords "refresh-ide" (Nil))
                                               (bound-chords "reload-buffer" (Nil))
                                               (bound-chords "build-project" (Nil))
                                               (bound-chords "toggle-files" (primary-chords "b" 0))
                                               (bound-chords "split-right" (primary-chords "\\" 0))
                                               (bound-chords "split-down"
                                                             (primary-chords "|" shift-key))
                                               (bound-chords "close-editor"
                                                             (Cons (Chord "w" alt-key)
                                                                   (primary-chords "w" 0)))))))
        ((Ok shortcuts) shortcuts)
        ((Err message) (panic message))))

    (: run-command (-> Ide String Step))
    (define (run-command model name)
      (match (command-named commands name)
        ((Some run) (invoked model run))
        ((None) (stay model))))

    (: shortcut (-> Ide String I32 Step))
    (define (shortcut model key modifiers)
      (match (shortcut-matching shortcuts (Chord key modifiers))
        ((Some name) (update model (DispatchCommand name)))
        ((None) (stay model))))

    (: invoked (-> Ide (-> Ide Step) Step))
    (define (invoked model run)
      (then (run (search-invalidated model))
            (lambda (next)
              (if (palette-visible? (::palette next)) (stay next)
                  (Pair next (list (focusing next (::active next))))))))

    (: palette-open (-> Ide palette-Mode Step))
    (define (palette-open model mode)
      (palette-step model (palette-open-component (::palette model) mode)))

    (: navigation-current? (-> I64 Bool ! dom))
    (define (navigation-current? navigation)
      (match (element-by-id "workbench")
        ((Some node) (string=? (string-property node "snailNavigation") (show navigation)))
        ((None) #f)))

    (: file-choices (-> Ide (List String)))
    (define (file-choices model)
      (list-sort string<?
                 (fold-left (lambda (paths buffer)
                              (if (member? (::path buffer) paths)
                                  paths
                                  (Cons (::path buffer) paths)))
                            (::files (::project model)) (::buffers model))))

    ;; ---- Palette boundary ----

    (: current-draft (-> Ide (Option search-Draft)))
    (define (current-draft model)
      (match (active-buffer model)
        ((Some buffer)
         (if (loaded? buffer)
             (Some (search-Draft (::path buffer) (display-text (::text buffer))))
             (None)))
        ((None) (None))))

    (: palette-context (-> Ide palette-Context))
    (define (palette-context model)
      (palette-Context
       (map (lambda (name) (palette-Entry name (command-keys name)))
            (vector->list (vector-map ::name (::commands commands))))
       (file-choices model)))

    (: palette-message (-> Ide palette-Message Step))
    (define (palette-message model message)
      (palette-step model (palette-update (::palette model) (palette-context model) message)))

    (: reconcile-palette (-> Ide Step))
    (define (reconcile-palette model)
      (if (palette-visible? (::palette model))
          (palette-step model (palette-reconcile (::palette model) (current-draft model)))
          (stay model)))

    (: palette-commands (-> (List (FnOnce palette-Message ! tasks dom fetch))
                            (List (Command Msg))))
    (define (palette-commands commands)
      (match commands
        ((Nil) (Nil))
        ((Cons command rest)
         (Cons (once (lambda () (PaletteEvent (command)))) (palette-commands rest)))))

    (: palette-step (-> Ide palette-Step Step))
    (define (palette-step model step)
      (match step
        ((palette-Step state outcome commands)
         (then (Pair (Ide-palette-set model state) (palette-commands commands))
               (lambda (next)
                 (match outcome
                   ((Some chosen) (palette-chosen next chosen))
                   ((None) (stay next))))))))

    ;; Selection has already closed the palette and advanced its generation.
    ;; Do not cancel it again: the read below belongs to that new navigation.
    (: palette-chosen (-> Ide palette-Outcome Step))
    (define (palette-chosen model chosen)
      (match chosen
        ((palette-InvokeNamed name) (update-message model (DispatchCommand name)))
        ((palette-OpenPath path) (opening model path (Focus (::active model))))
        ((palette-OpenSavedHit hit)
         (opening model (::file (::point hit)) (SearchPoint (::active model) hit)))
        ((palette-SelectDraftHit draft hit) (draft-followed model draft hit))
        ((palette-CreatedPath path directory)
         (then (listing model)
               (lambda (next)
                 (if directory (Pair next (list (focusing next (::active next))))
                     (opening next path (Focus (::active next)))))))
        ((palette-Dismissed) (Pair model (list (focusing model (::active model)))))))

    (: search-buffer (-> Ide Step))
    (define (search-buffer model)
      (match (current-draft model)
        ((Some draft)
         (palette-open model (palette-Searching (palette-Search (search-CurrentDraft draft)
                                                                (palette-Debouncing)))))
        ((None) (notice model "Open a file to search its current text."))))

    (: search-invalidated (-> Ide Ide))
    (define (search-invalidated model)
      (Ide-palette-set model (palette-cancel (::palette model))))

    (: draft-followed (-> Ide search-Draft Occurrence Step))
    (define (draft-followed model draft hit)
      (match (current-draft model)
        ((Some current)
         (if (search-same-draft? current draft)
             (Pair model (list (revealing model (::active model) (::path draft)
                                          (::text draft)
                                          (Point (::path draft) (::line hit)
                                                 (::column hit)))))
             (stay model)))
        ((None) (stay model))))

    (: search-followed (-> Ide I64 Hit (Option Snapshot) (List (Command Msg))))
    (define (search-followed model pane hit confirmed)
      (match (Pair (pane-buffer model pane) confirmed)
        ((Pair (Some buffer) (Some snapshot))
         (if (and (showing? model pane (::file (::point hit)))
                  (string=? (::revision snapshot) (::revision hit))
                  (hit-current? hit buffer))
             (list (revealing model pane
                              (::path buffer)
                              (display-text (::text buffer))
                              (::point hit)))
             (list (focusing model pane))))
        (_ (if (showing? model pane (::file (::point hit)))
               (list (focusing model pane)) (Nil)))))

    (: hit-current? (-> Hit Buffer Bool))
    (define (hit-current? hit buffer)
      (and (not (dirty? buffer)) (not (::saving buffer)) (string=? (::problem buffer) "")
           (match (::baseline buffer)
             ((Some snapshot) (string=? (::revision hit) (::revision snapshot)))
             ((None) #f))))

    ;; ---- Window commands ----

    (: notice (-> Ide String Step))
    (define (notice model text)
      (stay (Ide-status-set model (Status text "notice" (::attempt (::status model))))))

    (: installing (-> Ide Step))
    (define (installing model)
      (Pair model (list (once (lambda () (InstallFinished (install-app)))))))

    (: installation-finished (-> Ide InstallResult Step))
    (define (installation-finished model result)
      (notice model
              (match result
                ((InstallAccepted)
                 "Installation accepted; your browser will finish installing the app.")
                ((InstallDismissed) "Installation dismissed.")
                ((InstallAlreadyInstalled) "This app is already installed.")
                ((GestureRequired)
                 "Open the palette and click install-app to confirm installation.")
                ((InstallFailed)
                 "The browser could not open its installation prompt. Try its Install App menu.")
                ((InstallNotAvailable)
                 "Use your browser’s Install App or Add to Dock menu if available."))))

    ;; ---- Controlling runs ----

    ;; One command to the runs at a time. Its reply only acknowledges it: the
    ;; event stream reports what the process does. A reply lost after the
    ;; command reached the service leaves its outcome unknown.
    (: controlling (-> Ide String Step))
    (define (controlling model action)
      (let ((runs (::runs model)))
        (if (::pending runs)
            (stay model)
            (let ((target (::selected runs)))
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
      (let ((runs (Runs-pending-set (::runs model) #f)))
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
                                                                 (and
                                                                  (>= (::status failure) 400)
                                                                  (< (::status failure) 500))
                                                                 (::message failure)
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
                                   (let ((from (max start (+ base (::start token))))
                                         (to (min end (+ base (::end token)))))
                                     (if (< from to)
                                         (joined runs (token-class token) (substring text from to))
                                         runs)))
                                 (Nil)
                                 (highlight-tokens (substring text base end)))))))

    ;; A class of the highlight's styles in ide.css, as the book's are named;
    ;; whitespace and plain names are plain text.
    (: token-class (-> Token String))
    (define (token-class token)
      (match (::class token)
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

    ;; Compiler columns count scalars, as offsets do. Navigation keeps this
    ;; exact point; only the mark's display extends it to a lexical range.
    (: source-offset (-> String Point I64))
    (define (source-offset text point)
      (let loop ((offset (line-offset text (::line point))) (column 1))
        (if (and (< column (::column point))
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
                  (match (::source diagnostic)
                    ((Some point)
                     (range-mark text
                                 (highlight-range text (source-offset text point))
                                 (::message diagnostic)))
                    ((None) (Nil))))
                 ((None) (Nil)))))

    ;; One inline span crosses both lines and the syntax layer's token runs.
    ;; Newline and EOF points retain a visible cell without changing the source.
    (: range-mark (-> String (Pair I64 I64) String (List (Html Msg))))
    (define (range-mark text range message)
      (let ((start (::first range)) (end (::second range)))
        (list (Text (substring text 0 start))
              (Element "span"
                       (list (Attr "class" "error-highlight") (Attr "title" message))
                       (list (Text (if (or (= start end) (char=? (string-ref text start) #\newline))
                                       " "
                                       (substring text start end))))))))

    ;; ---- The view ----

    ;; A compact button that leaves focus in the editor until its command runs.
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
               (list (Attr "id" "workbench") (Attr "class" "ide")
                     (StringProperty "snailNavigation"
                                     (show (::generation (::palette model)))))
               (append (list (layout-view model)
                             (diagnostics-view model)
                             (runs-view (::runs model))
                             (status-view model))
                       (append (drag-view model) (palette-view model)))))

    (: status-view (-> Ide (Html Msg)))
    (define (status-view model)
      (let ((status (::status model)))
        (Element "footer" (list (Attr "class" "statusbar"))
                 (list (tool "toggle-files"
                             "tool"
                             "Toggle files (Cmd/Ctrl+B)"
                             "☰"
                             #f
                             (DispatchCommand "toggle-files"))
                       (tool "commands"
                             "tool"
                             "Commands (Cmd/Ctrl+Shift+P or F1)"
                             ">_"
                             #f
                             (DispatchCommand "command-palette"))
                       (Element "span"
                                (list (Attr "id" "status") (Attr "class" "status")
                                      (Attr "role" "status") (Attr "title" (::text status))
                                      (Attr "data-state" (::state status))
                                      (Attr "data-attempt" (::attempt status))
                                      (StringProperty "textContent" (::text status)))
                                (Nil))))))

    (: palette-view (-> Ide (List (Html Msg))))
    (define (palette-view model)
      (if (palette-visible? (::palette model))
          (map (lambda (html) (map-html PaletteEvent html))
               (palette-view-component (::palette model) (palette-context model)))
          (Nil)))

    (: command-keys (-> String String))
    (define (command-keys name)
      (string-join
       (delete-duplicates
        string=?
        (map (lambda (binding) (chord-label (::chord binding)))
             (filter (lambda (binding) (string=? name (::name binding)))
                     (vector->list (::bindings shortcuts)))))
       " / "))

    (: chord-label (-> Chord String))
    (define (chord-label chord)
      (string-append (if (= 0 (i32-and (::modifiers chord) control-key)) "" "Ctrl+")
                     (if (= 0 (i32-and (::modifiers chord) meta-key)) "" "⌘+")
                     (if (= 0 (i32-and (::modifiers chord) alt-key)) "" "Alt+")
                     (if (= 0 (i32-and (::modifiers chord) shift-key)) "" "Shift+")
                     (string-upcase (::key chord))))

    (: layout-view (-> Ide (Html Msg)))
    (define (layout-view model)
      (Element "main"
               (list
                (Attr "class"
                      (if (::files-shown model) "project-layout" "project-layout no-files"))
                (Attr "style"
                      (string-append "--files-width: "
                                     (show (f64->i64 (round (::files-width model))))
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
    (: file-tree (-> (List (Pair (List String) String)) (List (List String)) (List Tree)))
    (define (file-tree files directories)
      (let* ((nested (filter (lambda (file) (> (length (::first file)) 1)) files))
             (directories (filter (lambda (parts) (not (null? parts))) directories))
             (names (list-sort string<?
                               (delete-duplicates string=?
                                                  (append (map car-part nested)
                                                          (map (lambda (parts) (list-ref parts 0))
                                                               directories))))))
        (append (map (lambda (name)
                       (Folder name
                               (file-tree
                                (map (lambda (file)
                                       (Pair (list-tail (::first file) 1) (::second file)))
                                     (filter (lambda (file) (string=? (car-part file) name))
                                             nested))
                                (map (lambda (parts) (list-tail parts 1))
                                     (filter (lambda (parts) (string=? (list-ref parts 0) name))
                                             directories)))))
                     names)
                (map (lambda (file) (File (car-part file) (::second file)))
                     (list-sort (lambda (a b) (string<? (car-part a) (car-part b)))
                                (filter (lambda (file) (= (length (::first file)) 1)) files))))))

    (: car-part (-> (Pair (List String) String) String))
    (define (car-part file)
      (match (::first file)
        ((Cons part _) part)
        ((Nil) "")))

    (: files-view (-> Ide (Html Msg)))
    (define (files-view model)
      (let* ((project (::project model))
             (unlisted (filter (lambda (path) (not (member? path (::files project))))
                               (map ::path (::buffers model)))))
        (Element "nav"
                 (list (Attr "id" "files") (Attr "class" "dock files") (Attr "aria-label" "Files"))
                 (append (list (Element "h2"
                                        (Nil)
                                        (list (Text (if (string=? (::name project) "")
                                                        "Project"
                                                        (::name project)))))
                               (tree-view model
                                          (file-tree
                                           (map (lambda (path) (Pair (path-parts path) path))
                                                (::files project))
                                           (map path-parts (::directories project)))
                                          ""))
                         (if (null? unlisted)
                             (Nil)
                             (Cons (Element "h2" (Nil) (list (Text "Open files")))
                                   (map (lambda (path) (file-button model path path))
                                        unlisted)))))))

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

    ;; Folders start closed; only an explicit toggle expands one.
    (: folder-view (-> Ide String (List Tree) String (Html Msg)))
    (define (folder-view model name entries path)
      (Element "details"
               (list (FlagProperty "open" (member? path (::expanded model))))
               (list (Element "summary"
                              (list
                               (On "click" (Nil) (Always) (lambda (event) (ToggleFolder path))))
                              (list (Text name)))
                     (tree-view model entries path))))

    (: file-button (-> Ide String String (Html Msg)))
    (define (file-button model name path)
      (let ((buffer (buffer-at model path))
            (active (shows? (pane-of model (::active model)) path)))
        (Element "button"
                 (list (Attr "class"
                             (string-append "file"
                                            (if active " active" "")
                                            (match buffer
                                              ((Some found)
                                               (string-append (if (dirty? found) " dirty" "")
                                                              (if (conflict? found)
                                                                  " conflict"
                                                                  "")))
                                              ((None) ""))))
                       (Attr "data-path" path)
                       (Attr "title"
                             (match buffer
                               ((Some found)
                                (cond
                                 ((not (string=? (::failure found) "")) (::failure found))
                                 ((not (string=? (::problem found) "")) (::problem found))
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
      (let ((areas (pane-areas (::layout model) whole)))
        (append (map (lambda (pane)
                       (pane-view model
                                  (::id pane)
                                  (match (assoc-ref areas (::id pane))
                                    ((Some area) area)
                                    ((None) whole))))
                     (::panes model))
                (map divider-view (divisions (::layout model) whole)))))

    (: percent (-> F64 String))
    (define (percent fraction)
      (string-append (f64->string (* fraction 100.0)) "%"))

    (: placed (-> Area String))
    (define (placed area)
      (string-append "left: "
                     (percent (::left area))
                     "; top: "
                     (percent (::top area))
                     "; width: "
                     (percent (::width area))
                     "; height: "
                     (percent (::height area))))

    ;; A divider lies along the edge the split's ratio puts between its halves,
    ;; as long as the edge; ide.css gives it its thickness.
    (: divider-view (-> Division (Html Msg)))
    (define (divider-view division)
      (let* ((direction (::direction division))
             (edge
              (::second (halves (::area division) direction (::ratio division))))
             (corner (string-append "left: "
                                    (percent (::left edge))
                                    "; top: "
                                    (percent (::top edge)))))
        (Element "div"
                 (list (Keyed (string-append "divider-" (show (::split division))))
                       (Attr "class" (string-append "divider " direction))
                       (Attr "style"
                             (if (string=? direction "column")
                                 (string-append corner "; width: " (percent (::width edge)))
                                 (string-append corner "; height: " (percent (::height edge)))))
                       (On "pointerdown"
                           (Nil)
                           (Always)
                           (lambda (event) (Grab (Divider (::split division))))))
                 (Nil))))

    (: pane-view (-> Ide I64 Area (Html Msg)))
    (define (pane-view model id area)
      (let* ((pane (pane-of model id)) (buffer (pane-buffer model id)))
        (Element "div"
                 (list (Keyed (string-append "pane-" (show id)))
                       (Attr "class" (if (= id (::active model)) "pane active" "pane"))
                       (Attr "style" (placed area)))
                 (list (Element "div"
                                (list (Attr "class" "pane-header"))
                                (list (Element "span"
                                               (list (Attr "class" "pane-title"))
                                               (list (Text (pane-title buffer))))
                                      (tool ""
                                            "pane-button"
                                            "Close editor (Cmd/Ctrl+W or Alt+W)"
                                            "×"
                                            #f
                                            (Close id))))
                       (editor-view model pane buffer)
                       (problem-view buffer)))))

    (: pane-title (-> (Option Buffer) String))
    (define (pane-title buffer)
      (match buffer
        ((Some found) (string-append (::path found) (if (dirty? found) " ●" "")))
        ((None) "Choose a file")))

    (: problem-view (-> (Option Buffer) (Html Msg)))
    (define (problem-view buffer)
      (let ((problem (match buffer
                       ((Some found)
                        (cond ((not (string=? (::failure found) "")) (::failure found))
                              ((not (string=? (::problem found) "")) (::problem found))
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
      (let* ((id (::id pane))
             (text (match buffer
                     ((Some found) (display-text (::text found)))
                     ((None) "")))
             (scheme (match buffer
                       ((Some found) (source-file? (::path found)))
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
                           (lambda (event) (Scrolled id (::scroll-top event)))))
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
                                (list (highlight-view text (::scroll pane) scheme)
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
                             (Attr "aria-busy" (match buffer
                                                 ((Some found)
                                                  (if (::saving found) "true" "false"))
                                                 ((None) "false")))
                             (FlagProperty "disabled"
                                           (match buffer
                                             ((Some found) (not (loaded? found)))
                                             ((None) #t)))
                             (StringProperty "value" text)
                             (StringProperty "snailPath"
                                             (match buffer
                                               ((Some found) (::path found))
                                               ((None) "")))
                             (On "input"
                                 (list (Value))
                                 (Allow)
                                 (lambda (event) (Typed id (::value event))))
                             (On "focus" (Nil) (Allow) (lambda (event) (Focused id))))
                       (if scheme
                           (list (On "keydown"
                                     (list (Key) (Value) (Selection))
                                     (Chords editing-chords)
                                     (lambda (event)
                                       (Pressed id
                                                (::key event)
                                                (::value event)
                                                (::selection-start event)
                                                (::selection-end event)))))
                           (Nil)))
               (Nil)))

    ;; ---- Diagnostics and runs' views ----

    (: diagnostics-view (-> Ide (Html Msg)))
    (define (diagnostics-view model)
      (Element "div"
               (list (Attr "id" "diagnostics")
                     (Attr "class" "diagnostics")
                     (Attr "role" "status")
                     (FlagProperty "hidden" (null? (::diagnostics model))))
               (map-indexed (lambda (index diagnostic) (diagnostic-view model index diagnostic))
                            (::diagnostics model))))

    ;; A diagnostic in a project file is a button that shows its point.
    (: diagnostic-view (-> Ide I64 Diagnostic (Html Msg)))
    (define (diagnostic-view model index diagnostic)
      (let* ((source (::source diagnostic))
             (path (source-path (::project model) source))
             (text (string-append (::severity diagnostic)
                                  ": "
                                  (match source
                                    ((Some point)
                                     (string-append (match path
                                                      ((Some found) found)
                                                      ((None) (::file point)))
                                                    ":"
                                                    (show (::line point))
                                                    ":"
                                                    (show (::column point))
                                                    ": "))
                                    ((None) ""))
                                  (::message diagnostic))))
        (match path
          ((Some _)
           (Element "button"
                    (list (On "click"
                              (Nil)
                              (Allow)
                              (lambda (event) (Show (::generation model) index))))
                    (list (Text text))))
          ((None) (Element "div" (Nil) (list (Text text)))))))

    (: runs-view (-> Runs (Html Msg)))
    (define (runs-view runs)
      (let* ((run (selected-run runs))
             (pending (::pending runs))
             (available (match run
                          ((Some found) (::available found))
                          ((None) #f)))
             (wanted (match run
                       ((Some found) (::wanted found))
                       ((None) #f)))
             (attempt (match run
                        ((Some found) (::attempt found))
                        ((None) (None))))
             (problem (::problem runs)))
        (Element "section"
                 (list (Attr "id" "runs")
                       (Attr "class" "runs")
                       (Attr "aria-label" "Applications")
                       (FlagProperty "hidden"
                                     (and (null? (::runs runs))
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
                                                         (lambda (event)
                                                           (Choose (::value event)))))
                                               (map (lambda (found)
                                                      (option-view found (::selected runs)))
                                                    (::runs runs)))
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
                                               (list (Attr "id" "run-status")
                                                     (Attr "role" "status"))
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
                                                     ((Some found) (::stdout found))
                                                     ((None) "")))
                                      (output-view "Standard error"
                                                   "stderr"
                                                   "run-stderr"
                                                   (match attempt
                                                     ((Some found) (::stderr found))
                                                     ((None) "")))))))))

    (: option-view (-> Run String (Html Msg)))
    (define (option-view run selected)
      (Element "option"
               (list (Keyed (::target run))
                     (Attr "value" (::target run))
                     (FlagProperty "selected" (string=? (::target run) selected)))
               (list
                (Text (string-append (::target run) (if (::available run) "" " (removed)"))))))

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
                     (Element "pre"
                              (list (Attr "id" id) (Attr "tabindex" "0"))
                              (list (Text text))))))

    ;; While a drag is under way the page is covered, so the pointer's moves
    ;; reach the drag wherever they go.
    (: drag-view (-> Ide (List (Html Msg))))
    (define (drag-view model)
      (match (::drag model)
        ((Some drag)
         (list (Element "div"
                        (list (Attr "class"
                                    (match drag
                                      ((Dividing split _)
                                       (match (division-of (::layout model) split)
                                         ((Some division)
                                          (string-append "drag-overlay "
                                                         (::direction division)))
                                         ((None) "drag-overlay row")))
                                      ((Resizing _) "drag-overlay row")))
                              (On "pointermove"
                                  (list (Pointer))
                                  (Allow)
                                  (lambda (event) (Dragged (::x event) (::y event))))
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
                        (Chords (shortcut-chords shortcuts))
                        (lambda (event) (Shortcut (::key event) (::modifiers event))))
                    (On "online" (Nil) (Allow) (lambda (event) (Connect)))
                    (On "snail-refresh-failed" (Nil) (Allow) (lambda (event) (RefreshFailed))))
              (if (any? dirty? (::buffers model))
                  (list (On "beforeunload" (Nil) (Always) (lambda (event) (Nothing))))
                  (Nil))))

    ;; ---- The interface ----

    ;; Only user-owned state crosses navigation. Reads, pending commands and
    ;; server observations are reacquired, never replayed. Keep each original
    ;; baseline so a changed disk file cannot silently become a draft's base.
    (struct Draft
      ((path String)
       (text String)
       (baseline String))
      (deriving Serialize Deserialize))

    (struct Recovery
      ((version I64)
       (drafts (List Draft))
       (panes (List Pane))
       (layout Layout)
       (active I64)
       (next I64)
       ;; Keep the old wire field so saved drafts remain readable. Folder
       ;; expansion starts fresh on each page load.
       (closed (List String))
       (files-shown Bool)
       (files-width F64))
      (deriving Serialize Deserialize))

    (: kept (-> Ide Recovery))
    (define (kept model)
      (Recovery 1 (map kept-buffer (::buffers model)) (::panes model) (::layout model)
                (::active model) (::next model) (Nil)
                (::files-shown model) (::files-width model)))

    (: kept-buffer (-> Buffer Draft))
    (define (kept-buffer buffer)
      (Draft (::path buffer) (::text buffer)
             (match (::baseline buffer)
               ((Some baseline) (json->string (file->json baseline)))
               ((None) ""))))

    (: restored (-> Recovery Ide))
    (define (restored save)
      (unless (= (::version save) 1)
        (panic "unsupported IDE recovery version; saved drafts are retained"))
      (let* ((model (Ide-buffers-set initial (map restored-buffer (::drafts save))))
             (model (Ide-auto-open-set model #f))
             (model (Ide-panes-set model (::panes save)))
             (model (Ide-layout-set model (::layout save)))
             (model (Ide-active-set model (::active save)))
             (model (Ide-next-set model (::next save)))
             (model (Ide-files-shown-set model (::files-shown save))))
        (Ide-files-width-set model (::files-width save))))

    (: restored-buffer (-> Draft Buffer))
    (define (restored-buffer draft)
      (let ((baseline (if (string=? (::baseline draft) "") (None)
                          (match (string->json (::baseline draft))
                            ((Some json)
                             (match (json->file json)
                               ((Some baseline) (Some baseline))
                               ((None)
                                (panic "invalid recovered baseline; saved drafts are retained"))))
                            ((None) (panic "invalid recovered file; saved drafts are retained"))))))
        (Buffer (::path draft) (::text draft) baseline
                (match baseline
                  ((Some snapshot) (Some (::revision snapshot)))
                  ((None) (None)))
                #f 0 "" "")))
    ))
