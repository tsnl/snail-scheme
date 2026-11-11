;; The browser IDE as a host-independent application. A linear session owns
;; command futures beside immutable display data. Update polls without
;; suspending; view borrows the session. Pages and Scheme tests exercise the
;; same loop over DOM and fetch effects; host/ide/ide.sld supplies the page.
(define-library (snail shell ide application)
  (export Ide Msg initial update view window kept restored Connect Boot
          DispatchCommand Typed Open PaletteEvent
          Session begin-session update-session session-view session-window session-snapshot
          Command CommandResult Step Recovery TabbedRecovery read-recovery
          Buffer
          Snapshot buffer-at dirty? conflict?)
  (import
   (snail core base)
   (only (snail shell text) string-upcase string-downcase)
   (only (snail shell task) tasks)
   (snail shell future)
   (prefix (snail shell async) async-)
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
    (struct Command
      ((work (dyn (FnOnce → CommandResult ! tasks dom fetch)))
       (interrupted (dyn (Fn Ide → Step)))))

    ;; ---- Text ----

    ;; Offsets count scalars, as the dom effect's do.

    (define newline-text (→ String) (make-string 1 #\newline))

    (define (starts-with? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (define (ends-with? (text String) (suffix String)) (→ Bool)
      (let ((length (string-length text)) (size (string-length suffix)))
        (and (>= length size) (string=? (substring text (- length size) length) suffix))))

    ;; The last newline at or before `index`, or -1.

    (define (newline-before (text String) (index I64)) (→ I64)
      (let loop ((at (min index (- (string-length text) 1))))
        (cond ((< at 0) -1)
              ((char=? (string-ref text at) #\newline) at)
              (else (loop (- at 1))))))

    ;; Where the line holding `index` starts.

    (define (line-start (text String) (index I64)) (→ I64)
      (+ (newline-before text (- index 1)) 1))

    ;; Where the line holding `index` ends: its newline, or the text's end.

    (define (line-end (text String) (index I64)) (→ I64)
      (let loop ((at (max index 0)))
        (cond ((>= at (string-length text)) (string-length text))
              ((char=? (string-ref text at) #\newline) at)
              (else (loop (+ at 1))))))

    ;; Where line `line`, counting from 1, starts, or the text's end.

    (define (line-offset (text String) (line I64)) (→ I64)
      (let loop ((offset 0) (number 1))
        (if (>= number line)
            offset
            (let ((end (line-end text offset)))
              (if (>= end (string-length text)) end (loop (+ end 1) (+ number 1)))))))

    ;; The newlines from `from` up to `to`.

    (define (count-lines (text String) (from I64) (to I64)) (→ I64)
      (let loop ((at from) (count 0))
        (cond ((>= at to) count)
              ((char=? (string-ref text at) #\newline) (loop (+ at 1) (+ count 1)))
              (else (loop (+ at 1) count)))))

    (define (blank? (char Char)) (→ Bool)
      (or (char=? char #\space) (char=? char #\tab)))

    ;; How many spaces and tabs run from `index`.

    (define (indentation (text String) (index I64)) (→ I64)
      (let loop ((at index))
        (if (and (< at (string-length text)) (blank? (string-ref text at)))
            (loop (+ at 1))
            (- at index))))

    (define (spaces (count I64)) (→ String)
      (make-string count #\space))

    ;; The lines of a text, without their newlines.

    (define (lines-of (text String)) (→ (List String))
      (let loop ((end (string-length text)) (index (- (string-length text) 1)) (lines (Nil)))
        (cond ((< index 0) (Cons (substring text 0 end) lines))
              ((char=? (string-ref text index) #\newline)
               (loop index (- index 1) (Cons (substring text (+ index 1) end) lines)))
              (else (loop end (- index 1) lines)))))

    ;; Lines `first` to `last` of a text, counting from 0, as one text.

    (define (lines-between (text String) (first I64) (last I64)) (→ String)
      (string-join (take (list-tail (lines-of text) first) (+ (- last first) 1)) newline-text))

    ;; The text a field shows, which keeps only newlines of a file's line
    ;; ends.

    (define (display-text (text String)) (→ String)
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

    (define (longest-line (text String)) (→ I64)
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

    (define (apply-change (field Node) (change Change)) (→ Bool) (! dom)
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

    (define (indent-change (text String) (from I64) (selected-to I64)) (→ Change)
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

    (define (reindented (text String) (from I64) (to I64) (start I64) (end I64)) (→ String)
      (if (and (= from to) (= (indentation text start) (- end start)))
          (spaces (line-indentation text start))
          (let* ((base (form-start text start))
                 (first (count-lines text base start))
                 (last (+ first (count-lines text start end))))
            (lines-between (indent-lines (substring text base end) first last) first last))))

    ;; The column the line at `start` would be indented to, found by putting
    ;; a placeholder on it, since a formatted blank line stays empty.

    (define (line-indentation (text String) (start I64)) (→ I64)
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

    (define (form-start (text String) (start I64)) (→ I64)
      (if (> start 0) (top-level-start text (line-start text (- start 1))) 0))

    ;; The start of the line at or above `start` that opens a list in its
    ;; first column, or of the text.

    (define (top-level-start (text String) (start I64)) (→ I64)
      (if (or (= start 0) (and (< start (string-length text)) (char=? (string-ref text start) #\()))
          start
          (top-level-start text (line-start text (- start 1)))))

    ;; Enter starts a new line indented for what follows the caret, and, as
    ;; Emacs's electric indentation does, drops the spaces it leaves at the
    ;; end of the line before.

    (define (newline-change (text String) (from I64) (to I64)) (→ Change)
      (let* ((start (trailing-start text from))
             (skip (indentation text to))
             (joined (string-append (substring text 0 start)
                                    newline-text
                                    (substring text (+ to skip) (string-length text))))
             (indent (line-indentation joined (+ start 1)))
             (caret (+ (+ start 1) indent)))
        (Change start (+ to skip) (string-append newline-text (spaces indent)) caret caret)))

    ;; Where the spaces and tabs just before `index` start.

    (define (trailing-start (text String) (index I64)) (→ I64)
      (if (and (> index 0) (blank? (string-ref text (- index 1))))
          (trailing-start text (- index 1))
          index))

    ;; Formatting replaces only what changed, and the caret keeps its line and
    ;; its place after the line's indentation.

    (define (format-change (text String) (formatted String) (caret I64)) (→ Change)
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

    (define (shared-prefix (a String) (b String)) (→ I64)
      (let loop ((at 0))
        (if (and (< at (string-length a))
                 (< at (string-length b))
                 (char=? (string-ref a at) (string-ref b at)))
            (loop (+ at 1))
            at)))

    (define (shared-suffix (a String) (b String) (prefix I64)) (→ I64)
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

    (define (new-buffer (path String)) (→ Buffer)
      (Buffer path "" (None) (None) #f 0 "" ""))

    ;; The draft has changes of its own.

    (define (dirty? (buffer Buffer)) (→ Bool)
      (match (::baseline buffer)
        ((Some baseline) (not (string=? (::text buffer) (::text baseline))))
        ((None) #f)))

    ;; Disk has moved on from the contents the draft was made from.

    (define (conflict? (buffer Buffer)) (→ Bool)
      (match (Pair (::baseline buffer) (::observed buffer))
        ((Pair (Some baseline) (Some revision))
         (not (string=? revision (::revision baseline))))
        ((Pair (Some _) (None)) #t)
        (_ #f)))

    (define (loaded? (buffer Buffer)) (→ Bool)
      (match (::baseline buffer)
        ((Some _) #t)
        ((None) #f)))

    ;; The compiler reads Scheme sources, which the editor indents, formats
    ;; and colors.

    (define (source-file? (path String)) (→ Bool)
      (any? (lambda (extension) (ends-with? path extension)) (list ".sld" ".scm" ".datum")))

    ;; ---- Panes ----

    ;; A pane owns an ordered set of tabs and one selected path, never text.
    ;; Every tab refers to the shared buffers. The selected path is in tabs,
    ;; or absent exactly when tabs is empty.
    (struct EditorPane
      ((id I64)
       (path (Option String))
       (scroll F64)
       (tabs (List String))))

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

    (define (leaf? (layout Layout) (pane I64)) (→ Bool)
      (match layout
        ((Leaf id) (= id pane))
        (_ #f)))

    ;; The layout with the leaf of `pane` replaced by `replacement`.

    (define (leaf-replaced (layout Layout) (pane I64) (replacement Layout)) (→ Layout)
      (match layout
        ((Leaf id) (if (= id pane) replacement layout))
        ((Split id direction ratio first second)
         (Split id
                direction
                ratio
                (leaf-replaced first pane replacement)
                (leaf-replaced second pane replacement)))))

    ;; The node beside the leaf of `pane` in its split, if it is in one.

    (define (sibling (layout Layout) (pane I64)) (→ (Option Layout))
      (match layout
        ((Leaf _) (None))
        ((Split _ _ _ first second)
         (cond ((leaf? first pane) (Some second))
               ((leaf? second pane) (Some first))
               (else (match (sibling first pane)
                       ((Some found) (Some found))
                       ((None) (sibling second pane))))))))

    ;; The layout without the leaf of `pane`, its sibling in its split's place.

    (define (without-leaf (layout Layout) (pane I64)) (→ Layout)
      (match layout
        ((Leaf _) layout)
        ((Split id direction ratio first second)
         (cond ((leaf? first pane) second)
               ((leaf? second pane) first)
               (else
                (Split id direction ratio (without-leaf first pane) (without-leaf second pane)))))))

    (define (first-leaf (layout Layout)) (→ I64)
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

    (define whole (→ Area)
      (Area 0.0 0.0 1.0 1.0))

    ;; The two parts of `area` a split in `direction` at `ratio` makes.

    (define (halves (area Area) (direction String) (ratio F64)) (→ (Pair Area Area))
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

    (define (pane-areas (layout Layout) (area Area)) (→ (List (Pair I64 Area)))
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

    (define (divisions (layout Layout) (area Area)) (→ (List Division))
      (match layout
        ((Leaf _) (Nil))
        ((Split id direction ratio first second)
         (match (halves area direction ratio)
           ((Pair one other)
            (Cons (Division id direction ratio area)
                  (append (divisions first one) (divisions second other))))))))

    (define (division-of (layout Layout) (split I64)) (→ (Option Division))
      (find (lambda (division) (= (::split division) split)) (divisions layout whole)))

    ;; The layout with split `split` dividing at `ratio`, kept to a tenth of
    ;; the room either side.

    (define (ratio-set (layout Layout) (split I64) (ratio F64)) (→ Layout)
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

    (define (field-id (pane I64)) (→ String)
      (string-append "text-" (show pane)))

    (define (scroller-id (pane I64)) (→ String)
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

    (define (diagnostic-of (report Report)) (→ Diagnostic)
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

    (define (compiler-status (build Build)) (→ Status)
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

    (define (runs-received (runs Runs) (list (List Run))) (→ Runs)
      (Runs-selected-set (Runs-runs-set runs list) (chosen list (::selected runs))))

    (define (chosen (runs (List Run)) (selected String)) (→ String)
      (if (any? (lambda (run) (string=? (::target run) selected)) runs)
          selected
          (match (find ::available runs)
            ((Some run) (::target run))
            ((None) (match runs
                      ((Cons run _) (::target run))
                      ((Nil) ""))))))

    (define (selected-run (runs Runs)) (→ (Option Run))
      (find (lambda (run) (string=? (::target run) (::selected runs))) (::runs runs)))

    ;; What was asked of a run and what was seen of it.

    (define (run-description (found (Option Run))) (→ String)
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

    (define (attempt-description (attempt Attempt)) (→ String)
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
       (panes (List EditorPane))
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

    (define initial (→ Ide)
      (Ide (Project "" "" (Nil) (Nil))
           0
           (Nil)
           0
           (list (EditorPane 0 (None) 0.0 (Nil)))
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

    (define (buffer-at (model Ide) (path String)) (→ (Option Buffer))
      (find (lambda (buffer) (string=? (::path buffer) path)) (::buffers model)))

    ;; The model with `buffer` in place of the one at its path, or added.

    (define (buffer-set (model Ide) (buffer Buffer)) (→ Ide)
      (let ((path (::path buffer)))
        (Ide-buffers-set model
                         (match (buffer-at model path)
                           ((Some _)
                            (map (lambda (old) (if (string=? (::path old) path) buffer old))
                                 (::buffers model)))
                           ((None) (append (::buffers model) (list buffer)))))))

    ;; Remove a buffer and every tab that refers to it, choosing adjacent tabs.

    (define (buffer-removed (model Ide) (path String)) (→ Ide)
      (Ide-panes-set (Ide-buffers-set model
                                      (filter
                                       (lambda (buffer) (not (string=? (::path buffer) path)))
                                       (::buffers model)))
                     (map (lambda (pane)
                            (pane-closed pane path))
                          (::panes model))))

    (define (shows? (pane EditorPane) (path String)) (→ Bool)
      (match (::path pane)
        ((Some shown) (string=? shown path))
        ((None) #f)))

    (define (pane-opening (pane EditorPane) (path String)) (→ EditorPane)
      (if (shows? pane path) pane
          (EditorPane (::id pane) (Some path) 0.0
                      (if (member? path (::tabs pane)) (::tabs pane)
                          (append (::tabs pane) (list path))))))

    (define (pane-closed (pane EditorPane) (path String)) (→ EditorPane)
      (let ((tabs (filter (lambda (other) (not (string=? other path))) (::tabs pane))))
        (if (shows? pane path)
            (EditorPane (::id pane)
                        (tab-after-closing (::tabs pane) path (None))
                        0.0
                        tabs)
            (EditorPane-tabs-set pane tabs))))

    (define (tab-after-closing (tabs (List String)) (path String) (previous (Option String)))
      (→ (Option String))
      (match tabs
        ((Nil) previous)
        ((Cons first rest)
         (if (string=? first path)
             (match rest ((Cons next _) (Some next)) ((Nil) previous))
             (tab-after-closing rest path (Some first))))))

    (define (pane-of (model Ide) (id I64)) (→ EditorPane)
      (match (find (lambda (pane) (= (::id pane) id)) (::panes model))
        ((Some pane) pane)
        ((None) (EditorPane id (None) 0.0 (Nil)))))

    (define (pane-set (model Ide) (changed EditorPane)) (→ Ide)
      (Ide-panes-set model
                     (map (lambda (pane) (if (= (::id pane) (::id changed)) changed pane))
                          (::panes model))))

    (define (pane-buffer (model Ide) (id I64)) (→ (Option Buffer))
      (match (::path (pane-of model id))
        ((Some path) (buffer-at model path))
        ((None) (None))))

    (define (active-buffer (model Ide)) (→ (Option Buffer))
      (pane-buffer model (::active model)))

    ;; The active pane shows the file at `path`.

    (define (showing? (model Ide) (pane I64) (path String)) (→ Bool)
      (and (= pane (::active model))
           (shows? (pane-of model pane) path)
           (match (buffer-at model path)
             ((Some _) #t)
             ((None) #f))))

    ;; The project file a diagnostic's point is in, when it names one of the
    ;; project's files. Generated scratch and library sources stay messages,
    ;; never mapped onto a project file.

    (define (source-path (project Project) (source (Option Point))) (→ (Option String))
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

    (define (diagnostic-index (model Ide) (path String)) (→ (Option I64))
      (list-index (lambda (diagnostic)
                    (match (source-path (::project model) (::source diagnostic))
                      ((Some found) (string=? found path))
                      ((None) #f)))
                  (::diagnostics model)))

    (define (observation-at (model Ide) (index (Option I64))) (→ Observation)
      (match index
        ((Some at) (::observation (list-ref (::diagnostics model) at)))
        ((None) (Unobserved))))

    (define (observation-set (model Ide) (index I64) (observation Observation)) (→ Ide)
      (Ide-diagnostics-set model
                           (map-indexed (lambda (at diagnostic)
                                          (if (= at index)
                                              (Diagnostic-observation-set diagnostic observation)
                                              diagnostic))
                                        (::diagnostics model))))

    ;; The diagnostic whose point a pane showing the buffer marks: only while
    ;; the buffer is its disk contents, and only when the buffer's latest read
    ;; confirmed the revision the diagnostic was made from.

    (define (marked (model Ide) (buffer Buffer)) (→ (Option Diagnostic))
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

    (define (failed-status (model Ide) (message String)) (→ Status)
      (Status message "failed" (::attempt (::status model))))

    ;; ---- Input and work ----

    ;; Only intentions and browser input enter the UI message enum. Results
    ;; travel in futures as one-shot pure transitions on the current data.
    (enum Msg
      (Boot)
      (RefreshFailed)
      (Nothing)
      (Connect)
      (Open ((path String)))
      (Show ((generation I64)
             (index I64)))
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
      (Close ((pane I64)))
      (SelectTab ((pane I64)
                  (path String)))
      (DispatchCommand ((name String)))
      (PaletteEvent ((message palette-Message)))
      (ToggleFolder ((path String)))
      (Grab ((grip Grip)))
      (Dragged ((x F64)
                (y F64)))
      (Dropped)
      (Shortcut ((key String)
                 (modifiers I32)))
      (Choose ((target String)))
      (Control ((action String))))

    (struct CommandResult
      ((accept (dyn (FnOnce → (dyn (Fn Ide → Step)))))))

    ;; A command owns its transition in a one-shot thunk and unwraps it
    ;; only at the point it is applied to the current editor state.

    (define (command-result (transition (dyn (Fn Ide → Step)))) (→ CommandResult)
      (CommandResult (once (lambda () transition))))

    (define (apply-result (result CommandResult) (ide Ide)) (→ Step)
      (match result
        ((CommandResult accept)
         (let ((transition (accept)))
           (transition ide)))))

    (type Step
          (Pair Ide (List Command)))

    ;; Pending work has exactly one owner. Display data stays immutable and
    ;; shareable; the session itself cannot be copied or checkpointed.
    (struct PendingCommand
      ((future (Future CommandResult))
       (interrupted (dyn (Fn Ide → Step)))))

    (struct Session
      ((ide Ide)
       (pending (List PendingCommand))))

    (define interrupted-request (→ Failure)
      (Failure 0 "Request interrupted; its server-side outcome may be unknown."))

    (define (begin-session (ide Ide)) (→ Session)
      (Session ide (Nil)))

    (define (session-view (session (Borrow Session))) (→ (Html Msg))
      (view (::ide session)))

    (define (session-window (session (Borrow Session))) (→ (List (Attribute Msg)))
      (window (::ide session)))

    (define (session-snapshot (session (Borrow Session))) (→ TabbedRecovery)
      (kept (::ide session)))

    ;; Input invalidates old intentions before any result is accepted. Only
    ;; futures present on entry are polled: work spawned by a result waits
    ;; until a later turn, even if it could complete immediately.

    (define (update-session (session Session) (message (Option Msg)))
      (→ Session)
      (! mut completion dom fetch)
      (match session
        ((Session ide pending)
         (match (match message ((Some message) (update ide message)) ((None) (stay ide)))
           ((Pair next commands) (collect-results next pending (dispatch-commands commands)))))))

    (define (dispatch-commands (commands (List Command)))
      (→ (List PendingCommand))
      (! mut completion dom fetch)
      (match commands
        ((Nil) (Nil))
        ((Cons (Command work interrupted) rest)
         (Cons (PendingCommand (async-dispatch work) interrupted) (dispatch-commands rest)))))

    (define (collect-results (ide Ide)
                             (pending (List PendingCommand))
                             (waiting (List PendingCommand)))
      (→ Session)
      (! mut completion dom fetch)
      (match pending
        ((Nil) (Session ide waiting))
        ((Cons (PendingCommand future interrupted) rest)
         (match (poll future)
           ((Pending future)
            (collect-results ide rest (append waiting (list (PendingCommand future interrupted)))))
           ((Ready (Completed result))
            (continue-results (apply-result result ide) rest waiting))
           ((Ready (Abandoned))
            (continue-results (interrupted ide) rest waiting))))))

    (define (continue-results (step Step)
                              (rest (List PendingCommand))
                              (waiting (List PendingCommand)))
      (→ Session)
      (! mut completion dom fetch)
      (match (then step reconcile-palette)
        ((Pair next commands)
         (collect-results next rest (append waiting (dispatch-commands commands))))))

    (define (stay (model Ide)) (→ Step)
      (Pair model (Nil)))

    (define (then (step Step) (next (dyn (Fn Ide → Step)))) (→ Step)
      (match step
        ((Pair model commands)
         (match (next model)
           ((Pair after more) (Pair after (append commands more)))))))

    (define (update (model Ide) (message Msg)) (→ Step)
      (then (update-message model message) reconcile-palette))

    (define (update-message (model Ide) (message Msg)) (→ Step)
      (match message
        ((Boot)
         (Pair model
               (list (Command (once (lambda ()
                                      (let ((generation
                                             (string-property (document-root) "snailGeneration")))
                                        (command-result
                                         (lambda (current) (booted current generation))))))
                              stay))))
        ((RefreshFailed) (stay (Ide-refreshing-set model #f)))
        ((Nothing) (stay model))
        ((Connect) (connecting model))
        ((Open path) (opening (search-invalidated model) path (Focus (::active model))))
        ((Show generation index) (showing-diagnostic (search-invalidated model) generation index))
        ((Typed pane text) (typed model pane text))
        ((Pressed pane key text start end) (pressed model pane key text start end))
        ((Focused pane)
         (stay
          (Ide-active-set (if (= pane (::active model)) model (search-invalidated model)) pane)))
        ((Scrolled pane top)
         (stay (pane-set model (EditorPane-scroll-set (pane-of model pane) top))))
        ((Close pane) (invoked (Ide-active-set model pane) closing))
        ((SelectTab pane path)
         (opening (search-invalidated (Ide-active-set model pane)) path (Focus pane)))
        ((DispatchCommand name)
         (Pair model
               (list (Command (once (lambda ()
                                      (command-result
                                       (lambda (current) (run-command current name)))))
                              stay))))
        ((PaletteEvent message) (palette-message model message))
        ((ToggleFolder path) (stay (Ide-expanded-set model (toggled (::expanded model) path))))
        ((Grab grip) (Pair model (list (Command (once (lambda () (grabbed grip))) stay))))
        ((Dragged x y) (stay (dragged model x y)))
        ((Dropped) (stay (Ide-drag-set model (None))))
        ((Shortcut key modifiers) (shortcut model key modifiers))
        ((Choose target) (stay (Ide-runs-set model (Runs-selected-set (::runs model) target))))
        ((Control action) (controlling model action))))

    (define (booted (model Ide) (generation String)) (→ Step)
      (refresh-if-needed (if (string=? (::editor model) "")
                             (Ide-editor-set model generation) model)))

    (define (connected (model Ide) (stream Stream)) (→ Step)
      (Pair (Ide-events-set model (Some stream)) (list (hear stream))))

    (define (stream-heard (model Ide) (stream Stream) (event StreamEvent)) (→ Step)
      (if (current-stream? model stream) (heard model stream event) (stay model)))

    (define (refused (model Ide) (failure Failure)) (→ Step)
      (stay (Ide-status-set model (failed-status model (::message failure)))))

    (define (fullscreen-finished (model Ide) (accepted Bool)) (→ Step)
      (if accepted (stay model)
          (notice model "Fullscreen needs an explicit click or is unavailable in this browser.")))

    (define (began-drag (model Ide) (drag Drag)) (→ Step)
      (stay (Ide-drag-set model (Some drag))))

    ;; ---- Events ----

    ;; The service's event stream: the compiler's status, the run targets'
    ;; processes, a sign that files changed, and each dropped connection.

    (define event-kinds (→ (List String))
      (list event-kind "open" "error"))

    ;; Connecting closes the stream before, so none of its events, sent or
    ;; not, is heard again.

    (define (connecting (model Ide)) (→ Step)
      (let ((old (::events model)))
        (Pair (Ide-status-set (Ide-events-set model (None))
                              (Status "Connecting…" "starting" (::attempt (::status model))))
              (list (Command (once (lambda ()
                                     (match old
                                       ((Some stream) (stream-close stream))
                                       ((None) (unit)))
                                     (let ((stream (stream-open "/api/events" event-kinds)))
                                       (command-result
                                        (lambda (current) (connected current stream))))))
                             stay)))))

    (define (hear (stream Stream)) (→ Command)
      (Command (once (lambda ()
                       (match (stream-next stream)
                         ((Some event)
                          (command-result (lambda (current) (stream-heard current stream event))))
                         ((None) (command-result stay))))) stay))

    (define (current-stream? (model Ide) (stream Stream)) (→ Bool)
      (match (::events model)
        ((Some current) (= (::id current) (::id stream)))
        ((None) #f)))

    ;; Every connection, including EventSource reconnections, refreshes reads
    ;; and listings. Their new intent numbers reject delayed old replies.
    ;; The next event is heard after this one. Bad messages leave the last
    ;; complete snapshot intact and make the protocol failure visible.

    (define (heard (model Ide) (stream Stream) (event StreamEvent)) (→ Step)
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

    (define (reconnected (model Ide)) (→ Step)
      (then (listing model) (lambda (model) (palette-message model (palette-Reconnected)))))

    ;; The stream is ordered and reconnection starts with a complete snapshot.
    ;; Only a new build report resets diagnostic evidence; process output and
    ;; repeated snapshots cannot revive a diagnostic invalidated by a save.

    (define (received (model Ide) (state ServerState)) (→ Step)
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

    (define (received-build (model Ide) (build Build) (fresh Bool)) (→ Ide)
      (Ide-status-set
       (if fresh
           (Ide-diagnostics-set (Ide-generation-set model (+ (::generation model) 1))
                                (map diagnostic-of (::diagnostics build)))
           model)
       (compiler-status build)))

    ;; A successful server generation is the only reason to auto-refresh.
    ;; Record the attempted generation so a storage refusal does not retry on
    ;; every process-output event. The explicit command can retry at any time.

    (define (refresh-if-needed (model Ide)) (→ Step)
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

    (define (refreshing (model Ide)) (→ Step)
      (Pair (Ide-refreshing-set model #t)
            (list (Command (once (lambda () (refresh-page) (command-result stay)))
                           (lambda (current) (stay (Ide-refreshing-set current #f)))))))

    ;; ---- Files ----

    ;; Files changed: every open buffer is read again, and the project listed.

    (define (listing (model Ide)) (→ Step)
      (let ((sequence (+ (::listing model) 1)))
        (then (reading-all (Ide-listing-set model sequence))
              (lambda (model)
                (Pair model
                      (list (Command (once (lambda ()
                                             (let ((reply (project-reply
                                                           (api "GET" "/api/project" (Nil) ""))))
                                               (command-result (lambda (current)
                                                                 (listed current
                                                                         sequence
                                                                         reply))))))
                                     (lambda (current)
                                       (listed current sequence (Err interrupted-request))))))))))

    ;; Only the latest listing counts. The first nonempty project listing
    ;; opens main.sld or its first file; explicit closes never reopen a file.

    (define (listed (model Ide) (sequence I64) (result (Result Project Failure))) (→ Step)
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

    (define (opening (model Ide) (path String) (follow Follow)) (→ Step)
      (let* ((model (Ide-auto-open-set model #f))
             (model (match (buffer-at model path)
                      ((Some _) model)
                      ((None) (buffer-set model (new-buffer path)))))
             (model
              (pane-set model (pane-opening (pane-of model (::active model)) path))))
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

    (define (showing-diagnostic (model Ide) (generation I64) (index I64)) (→ Step)
      (if (= generation (::generation model))
          (match (source-path (::project model)
                              (::source (list-ref (::diagnostics model) index)))
            ((Some path) (opening model path (Reveal (::active model) generation index)))
            ((None) (stay model)))
          (stay model)))

    ;; What opening asked, once the file's read has answered, while the pane
    ;; that asked is active and still shows the file. A point is revealed only
    ;; when the diagnostic is still the one the pane marks.

    (define (followed (model Ide)
                      (path String)
                      (follow Follow)
                      (navigation I64)
                      (confirmed (Option Snapshot)))
      (→ (List Command))
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

    (define (revealed (model Ide) (path String) (generation I64) (index I64)) (→ (Option Point))
      (match (buffer-at model path)
        ((Some buffer)
         (match (Pair (marked model buffer) (diagnostic-index model path))
           ((Pair (Some diagnostic) (Some at))
            (if (and (= generation (::generation model)) (= at index))
                (::source diagnostic)
                (None)))
           (_ (None))))
        ((None) (None))))

    (define (shown-text (model Ide) (path String)) (→ String)
      (match (buffer-at model path)
        ((Some buffer) (display-text (::text buffer)))
        ((None) "")))

    (define (focusing (model Ide) (pane I64)) (→ Command)
      (let ((navigation (::generation (::palette model)))
            (id (match (pane-buffer model pane)
                  ((Some buffer) (if (loaded? buffer) (field-id pane) "commands"))
                  ((None) "commands"))))
        (Command (once (lambda ()
                         (when (navigation-current? navigation)
                           (match (::path (pane-of model pane))
                             ((Some path) (reveal-tab pane path))
                             ((None) (unit)))
                           (match (element-by-id id)
                             ((Some node) (focus-node node))
                             ((None) (unit))))
                         (command-result stay))) stay)))

    (define (tab-id (pane I64) (path String)) (→ String)
      (string-append "tab-" (show pane) ":" path))

    (define (reveal-tab (pane I64) (path String)) (→ Unit) (! dom)
      (match (Pair (element-by-id (string-append "tabs-" (show pane)))
                   (element-by-id (tab-id pane path)))
        ((Pair (Some strip) (Some tab))
         (let* ((left (number-property tab "offsetLeft"))
                (right (+ left (number-property tab "offsetWidth")))
                (start (number-property strip "scrollLeft"))
                (width (number-property strip "clientWidth")))
           (set-number-property strip
                                "scrollLeft"
                                (max 0.0 (min left (max start (- right width)))))))
        (_ (unit))))

    ;; The caret at a diagnostic's point, its line scrolled a few lines below
    ;; the top.

    (define (revealing (model Ide) (pane I64) (path String) (text String) (point Point)) (→ Command)
      (let ((navigation (::generation (::palette model))))
        (Command (once (lambda ()
                         (match (element-by-id (field-id pane))
                           ((Some field)
                            (when (and (navigation-current? navigation)
                                       (current-field? field path text))
                              (let ((offset (source-offset text point)))
                                (reveal-tab pane path)
                                (focus-node field)
                                (select-range field (i64->i32 offset) (i64->i32 offset))
                                (scrolled-to pane
                                             (* line-height
                                                (i64->f64
                                                 (max 0 (- (count-lines text 0 offset) 4))))))))
                           ((None) (unit)))
                         (command-result stay))) stay)))

    (define (scrolled-to (pane I64) (top F64)) (→ Unit) (! dom)
      (match (element-by-id (scroller-id pane))
        ((Some scroller) (set-number-property scroller "scrollTop" top))
        ((None) (unit))))

    ;; ---- Reading ----

    ;; A read of the buffer at `path`, unless it is saving. Its sequence
    ;; withdraws what every earlier read said, the point it marked among it.

    (define (reading (model Ide) (path String) (follow Follow)) (→ Step)
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
                     (list (Command (once (lambda ()
                                            (let ((reply (file-reply
                                                          (api "GET" (file-url path) (Nil) ""))))
                                              (command-result (lambda (current)
                                                                (answered current
                                                                          asked
                                                                          reply))))))
                                    (lambda (current)
                                      (answered current asked (Err interrupted-request)))))))))
        ((None) (Pair model (followed model path follow
                                      (::generation (::palette model)) (None))))))

    (define (reading-all (model Ide)) (→ Step)
      (fold-left (lambda (step path) (then step (lambda (model) (reading model path (Stay)))))
                 (stay model)
                 (map ::path (::buffers model))))

    ;; Only the latest successful read confirms coordinates. An obsolete reply
    ;; must not revive a search hit merely because the cached baseline matches.

    (define (answered (model Ide) (asked Asked) (result (Result Snapshot Failure))) (→ Step)
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

    (define (read-confirmation (model Ide) (asked Asked) (result (Result Snapshot Failure)))
      (→ (Option Snapshot))
      (match (Pair (buffer-at model (::path asked)) result)
        ((Pair (Some buffer) (Ok snapshot))
         (if (= (::read buffer) (::sequence asked)) (Some snapshot) (None)))
        (_ (None))))

    ;; The draft follows disk unless it has changes of its own.

    (define (snapshot-read (model Ide) (buffer Buffer) (snapshot Snapshot)) (→ Ide)
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

    (define (read-failed (model Ide) (buffer Buffer) (failure Failure)) (→ Ide)
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

    (define (bound (model Ide) (asked Asked) (snapshot Snapshot)) (→ Ide)
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

    (define (typed (model Ide) (pane I64) (text String)) (→ Step)
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

    (define (pressed (model Ide) (pane I64) (key String) (text String) (start I32) (end I32))
      (→ Step)
      (let ((from (i32->i64 start)) (to (i32->i64 end)))
        (Pair model
              (list (changing pane
                              (if (string=? key "Tab")
                                  (indent-change text from to)
                                  (newline-change text from to)))))))

    (define (changing (pane I64) (change Change)) (→ Command)
      (Command (once (lambda ()
                       (match (element-by-id (field-id pane))
                         ((Some field) (apply-change field change) (command-result stay))
                         ((None) (command-result stay))))) stay))

    ;; The keys Tab and Enter, which a Scheme source's field hears.

    (define editing-chords (→ (List Chord))
      (list (Chord "Tab" 0) (Chord "Tab" shift-key) (Chord "Enter" 0)))

    ;; ---- Saving ----

    ;; One save at a time per buffer. Its answer changes the baseline, never
    ;; newer typing, and a read begun before it no longer counts. A save
    ;; withdraws the diagnostic at its file for good: the failure was not made
    ;; from the text it writes.

    (define (saving (model Ide)) (→ Step)
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
                        (list (Command (once (lambda () (saved-text pane buffer baseline)))
                                       (lambda (current)
                                         (saved current
                                                (::path buffer)
                                                (Err interrupted-request)))))))))
           ((None) (stay model))))
        ((None) (stay model))))

    ;; A source is formatted first, in the pane's field; formatting that fails
    ;; does not keep an incomplete draft from being saved.

    (define (saved-text (pane EditorPane) (buffer Buffer) (baseline Snapshot))
      (→ CommandResult)
      (! dom fetch tasks)
      (let* ((path (::path buffer))
             (text
              (if (source-file? path)
                  (formatted-in pane (::path buffer) (::text buffer))
                  (::text buffer))))
        (let ((reply (file-reply (api "PUT"
                                      (file-url path)
                                      (list (Header "Content-Type" "text/plain; charset=utf-8")
                                            (Header "If-Match"
                                                    (string-append "\""
                                                                   (::revision baseline)
                                                                   "\"")))
                                      text))))
          (command-result (lambda (current) (saved current path reply))))))

    ;; The text formatted in the pane's field as typing would, which the
    ;; field's input brings to the buffer too; or the text as it was, when the
    ;; field did not take it.

    (define (formatted-in (pane EditorPane) (path String) (text String)) (→ String) (! dom)
      (let* ((shown (display-text text)) (formatted (format-source shown format-width)))
        (if (or (string=? shown formatted) (not (reformatted pane path shown formatted)))
            text
            formatted)))

    ;; The change keeps the caret's line, and the field its scroll.

    (define (reformatted (pane EditorPane) (path String) (shown String) (formatted String))
      (→ Bool)
      (! dom)
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

    (define (current-field? (field Node) (path String) (text String)) (→ Bool) (! dom)
      (and (string=? (string-property field "snailPath") path)
           (string=? (string-property field "value") text)))

    ;; A save that wrote has its text as the new baseline. The file is read
    ;; again even after a failure, as the write may have reached disk.

    (define (saved (model Ide) (path String) (result (Result Snapshot Failure))) (→ Step)
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

    (define (formatting (model Ide)) (→ Step)
      (match (active-buffer model)
        ((Some buffer)
         (if (and (loaded? buffer) (source-file? (::path buffer)))
             (let ((pane (pane-of model (::active model))) (path (::path buffer)))
               (Pair (buffer-set model (Buffer-failure-set buffer ""))
                     (list (Command (once (lambda ()
                                            (let* ((shown (display-text (::text buffer)))
                                                   (formatted (format-source shown format-width)))
                                              (let ((taken (or (string=? shown formatted)
                                                               (reformatted pane
                                                                            path
                                                                            shown
                                                                            formatted))))
                                                (command-result (lambda (current)
                                                                  (format-finished current
                                                                                   path
                                                                                   taken)))))))
                                    stay))))
             (stay model)))
        ((None) (stay model))))

    (define (format-finished (model Ide) (path String) (taken Bool)) (→ Step)
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

    (define (reloading (model Ide)) (→ Step)
      (match (active-buffer model)
        ((Some buffer)
         (cond ((::saving buffer) (stay model))
               ((dirty? buffer)
                (Pair model
                      (list (Command (once (lambda ()
                                             (if (confirm
                                                  "Discard this file’s unsaved changes and reload from disk?")
                                                 (let ((path (::path buffer)))
                                                   (command-result
                                                    (lambda (current) (discarded current path))))
                                                 (command-result stay)))) stay))))
               (else (discarded model (::path buffer)))))
        ((None) (stay model))))

    (define (discarded (model Ide) (path String)) (→ Step)
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

    (define (building) (→ CommandResult) (! fetch tasks)
      (match (api "POST" "/api/build" (Nil) "")
        ((Ok _) (command-result stay))
        ((Err failure) (command-result (lambda (current) (refused current failure))))))

    ;; ---- Arranging ----

    ;; The active pane splits in two, the new one second, showing the same
    ;; file, and active.

    (define (divided (model Ide) (direction String)) (→ Step)
      (let* ((active (::active model))
             (pane (::next model))
             (split (Split (+ pane 1) direction 0.5 (Leaf active) (Leaf pane)))
             (model (Ide-panes-set model
                                   (append (::panes model)
                                           (list
                                            (pane-split (pane-of model active) pane)))))
             (model (Ide-layout-set model (leaf-replaced (::layout model) active split))))
        (Pair (Ide-next-set (Ide-active-set model pane) (+ pane 2)) (list (focusing model pane)))))

    (define (pane-split (pane EditorPane) (id I64)) (→ EditorPane)
      (EditorPane id (::path pane) 0.0
                  (match (::path pane) ((Some path) (list path)) ((None) (Nil)))))

    ;; Closing the last view of a draft asks before discarding it. A reply
    ;; names the exact draft it was for; it cannot discard subsequent typing.

    (define (closing (model Ide)) (→ Step)
      (match (active-buffer model)
        ((None) (close-pane model))
        ((Some buffer)
         (let ((path (::path buffer)) (pane (::active model)))
           (cond ((::saving buffer) (stay model))
                 ((other-view? model pane path)
                  (closed-tab model pane path))
                 ((dirty? buffer)
                  (Pair model (list (Command (once (lambda ()
                                                     (if (confirm
                                                          (string-append
                                                           "Discard unsaved changes to "
                                                           path
                                                           "?"))
                                                         (let ((text (::text buffer)))
                                                           (command-result (lambda (current)
                                                                             (close-ready current
                                                                                          pane
                                                                                          path
                                                                                          text))))
                                                         (command-result stay)))) stay))))
                 (else (closed-tab model pane path)))))))

    (define (close-ready (model Ide) (pane I64) (path String) (text String)) (→ Step)
      (match (buffer-at model path)
        ((Some buffer)
         (if (and (showing? model pane path) (not (::saving buffer))
                  (string=? text (::text buffer)))
             (closed-tab model pane path)
             (stay model)))
        ((None) (stay model))))

    (define (other-view? (model Ide) (pane I64) (path String)) (→ Bool)
      (any? (lambda (other) (and (not (= pane (::id other))) (member? path (::tabs other))))
            (::panes model)))

    (define (closed-tab (model Ide) (pane I64) (path String)) (→ Step)
      (let* ((next (pane-closed (pane-of model pane) path))
             (model (pane-set model next))
             (model (if (other-view? model pane path) model (buffer-removed model path))))
        (if (null? (::tabs next)) (close-pane model)
            (Pair model (list (focusing model pane))))))

    ;; The active pane's sibling takes its place. The last pane stays empty.

    (define (close-pane (model Ide)) (→ Step)
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
           (let ((empty (pane-set model (EditorPane-path-set (pane-of model active) (None)))))
             (Pair empty (list (focusing empty active))))))))

    (define (toggled (paths (List String)) (path String)) (→ (List String))
      (if (member? path paths)
          (filter (lambda (other) (not (string=? other path))) paths)
          (Cons path paths)))

    ;; A drag measures what it divides as it begins.

    (define (grabbed (grip Grip)) (→ CommandResult) (! dom)
      (match grip
        ((FilesEdge)
         (let ((drag (Resizing (::width (measured "workbench")))))
           (command-result (lambda (current) (began-drag current drag)))))
        ((Divider split)
         (let ((drag (Dividing split (measured "panes"))))
           (command-result (lambda (current) (began-drag current drag)))))))

    (define (measured (id String)) (→ Measure) (! dom)
      (match (element-by-id id)
        ((Some node) (measure node))
        ((None) (Measure 0.0 0.0 0.0 0.0 0.0 0.0 0.0))))

    ;; The files keep between 120 pixels and seven tenths of the page; a
    ;; divider follows the pointer across its split.

    (define (dragged (model Ide) (x F64) (y F64)) (→ Ide)
      (match (::drag model)
        ((Some (Resizing width)) (Ide-files-width-set model (max 120.0 (min (* width 0.7) x))))
        ((Some (Dividing split box))
         (match (division-of (::layout model) split)
           ((Some division)
            (Ide-layout-set model (ratio-set (::layout model) split (pointed division box x y))))
           ((None) model)))
        ((None) model)))

    ;; Where the pointer lies across the split, in the room's box on the page.

    (define (pointed (division Division) (box Measure) (x F64) (y F64)) (→ F64)
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

    (define (primary-chords (key String) (extra I32)) (→ (List Chord))
      (concatenate
       (map (lambda (spelling)
              (map (lambda (held) (Chord spelling (+ held extra))) (list control-key meta-key)))
            (delete-duplicates string=? (list (string-upcase key) (string-downcase key))))))

    (define commands (→ (command-Registry (dyn (Fn Ide → Step))))
      (match (command-register
              (ann (list->vector (list (command-Command "command-palette"
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
                                                                         (palette-Creation #f
                                                                                           #f
                                                                                           "")))))
                                       (command-Command "new-directory"
                                                        (lambda (model)
                                                          (palette-open model
                                                                        (palette-Creating
                                                                         (palette-Creation #t
                                                                                           #f
                                                                                           "")))))
                                       (command-Command "install-app" installing)
                                       (command-Command "toggle-fullscreen" toggling-fullscreen)
                                       (command-Command "save-buffer" saving)
                                       (command-Command "format-buffer" formatting)
                                       (command-Command "refresh-ide" refreshing)
                                       (command-Command "reload-buffer" reloading)
                                       (command-Command "build-project"
                                                        (lambda (model)
                                                          (Pair model
                                                                (list
                                                                 (Command (once building) stay)))))
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
                                       (command-Command "close-editor" closing)))
                   (Vector (command-Command (dyn (Fn Ide → Step))))))
        ((Ok registry) registry)
        ((Err message) (panic message))))

    (define (bound-chords (name String) (chords (List Chord))) (→ (List shortcut-Binding))
      (map (lambda (chord) (shortcut-Binding chord name)) chords))

    (define shortcuts (→ shortcut-Shortcuts)
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

    (define (run-command (model Ide) (name String)) (→ Step)
      (match (command-named commands name)
        ((Some run) (if (and (string=? name "search-buffer") (palette-finding? (::palette model)))
                        (run model) (invoked model run)))
        ((None) (stay model))))

    (define (shortcut (model Ide) (key String) (modifiers I32)) (→ Step)
      (if (and (palette-finding? (::palette model)) (string=? key "Escape") (= modifiers 0))
          (palette-message model (palette-Dismiss))
          (match (shortcut-matching shortcuts (Chord key modifiers))
            ((Some name) (update model (DispatchCommand name)))
            ((None) (stay model)))))

    (define (invoked (model Ide) (run (dyn (Fn Ide → Step)))) (→ Step)
      (then (run (search-invalidated model))
            (lambda (next)
              (if (palette-visible? (::palette next)) (stay next)
                  (Pair next (list (focusing next (::active next))))))))

    (define (palette-open (model Ide) (mode palette-Mode)) (→ Step)
      (palette-step model (palette-open-component (::palette model) mode)))

    (define (navigation-current? (navigation I64)) (→ Bool) (! dom)
      (match (element-by-id "workbench")
        ((Some node) (string=? (string-property node "snailNavigation") (show navigation)))
        ((None) #f)))

    (define (file-choices (model Ide)) (→ (List String))
      (list-sort string<?
                 (fold-left (lambda (paths buffer)
                              (if (member? (::path buffer) paths)
                                  paths
                                  (Cons (::path buffer) paths)))
                            (::files (::project model)) (::buffers model))))

    ;; ---- Palette boundary ----

    (define (current-draft (model Ide)) (→ (Option search-Draft))
      (match (active-buffer model)
        ((Some buffer)
         (if (loaded? buffer)
             (Some (search-Draft (::path buffer) (display-text (::text buffer))))
             (None)))
        ((None) (None))))

    (define (palette-context (model Ide)) (→ palette-Context)
      (palette-Context
       (map (lambda (name) (palette-Entry name (command-keys name)))
            (vector->list (vector-map ::name (::commands commands))))
       (file-choices model)))

    (define (palette-message (model Ide) (message palette-Message)) (→ Step)
      (palette-step model (palette-update (::palette model) (palette-context model) message)))

    (define (reconcile-palette (model Ide)) (→ Step)
      (if (palette-visible? (::palette model))
          (palette-step model (palette-reconcile (::palette model) (current-draft model)))
          (stay model)))

    (define (palette-commands (commands (List palette-Command))) (→ (List Command))
      (match commands
        ((Nil) (Nil))
        ((Cons (palette-Command work interrupted) rest)
         (Cons (Command
                (once (lambda ()
                        (let ((transition (work)))
                          (command-result
                           (lambda (model) (palette-step model (transition (::palette model))))))))
                (lambda (model) (palette-step model (interrupted (::palette model)))))
               (palette-commands rest)))))

    (define (palette-step (model Ide) (step palette-Step)) (→ Step)
      (match step
        ((palette-Step state outcome commands)
         (then (Pair (Ide-palette-set model state) (palette-commands commands))
               (lambda (next)
                 (match outcome
                   ((Some chosen) (palette-chosen next chosen))
                   ((None) (stay next))))))))

    ;; Selection has already closed the palette and advanced its generation.
    ;; Do not cancel it again: the read below belongs to that new navigation.

    (define (palette-chosen (model Ide) (chosen palette-Outcome)) (→ Step)
      (match chosen
        ((palette-InvokeNamed name) (update-message model (DispatchCommand name)))
        ((palette-OpenPath path) (opening model path (Focus (::active model))))
        ((palette-OpenSavedHit hit)
         (opening model (::file (::point hit)) (SearchPoint (::active model) hit)))
        ((palette-SelectDraftHit draft hit size) (draft-followed model draft hit size))
        ((palette-CreatedPath path directory)
         (then (listing model)
               (lambda (next)
                 (if directory (Pair next (list (focusing next (::active next))))
                     (opening next path (Focus (::active next)))))))
        ((palette-Dismissed) (Pair model (list (focusing model (::active model)))))))

    (define (search-buffer (model Ide)) (→ Step)
      (match (current-draft model)
        ((Some draft)
         (palette-open model (palette-Searching (palette-Search (search-CurrentDraft draft)
                                                                (palette-Debouncing)))))
        ((None) (notice model "Open a file to search its current text."))))

    (define (search-invalidated (model Ide)) (→ Ide)
      (Ide-palette-set model (palette-cancel (::palette model))))

    (define (draft-followed (model Ide) (draft search-Draft) (hit Occurrence) (size I64)) (→ Step)
      (match (current-draft model)
        ((Some current)
         (if (search-same-draft? current draft)
             (Pair model (list (finding model draft hit size)))
             (stay model)))
        ((None) (stay model))))

    ;; Keep focus where the user left it: selecting another match must not
    ;; take the find input away. The DOM boundary uses scalar offsets too.

    (define (finding (model Ide) (draft search-Draft) (hit Occurrence) (size I64)) (→ Command)
      (let ((pane (::active model)) (navigation (::generation (::palette model))))
        (Command (once (lambda ()
                         (match (element-by-id (field-id pane))
                           ((Some field)
                            (when (and (navigation-current? navigation)
                                       (current-field? field (::path draft) (::text draft)))
                              (let ((offset (source-offset (::text draft)
                                                           (Point (::path draft)
                                                                  (::line hit)
                                                                  (::column hit)))))
                                (select-range field (i64->i32 offset) (i64->i32 (+ offset size)))
                                (scrolled-to pane
                                             (* line-height
                                                (i64->f64 (max 0 (- (::line hit) 5))))))))
                           ((None) (unit)))
                         (command-result stay))) stay)))

    (define (search-followed (model Ide) (pane I64) (hit Hit) (confirmed (Option Snapshot)))
      (→ (List Command))
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

    (define (hit-current? (hit Hit) (buffer Buffer)) (→ Bool)
      (and (not (dirty? buffer)) (not (::saving buffer)) (string=? (::problem buffer) "")
           (match (::baseline buffer)
             ((Some snapshot) (string=? (::revision hit) (::revision snapshot)))
             ((None) #f))))

    ;; ---- Window commands ----

    (define (toggling-fullscreen (model Ide)) (→ Step)
      (Pair model (list (Command (once toggle-fullscreen) stay))))

    (define (toggle-fullscreen) (→ CommandResult) (! dom tasks)
      (let ((accepted (set-fullscreen (not (fullscreen?)))))
        (command-result (lambda (current) (fullscreen-finished current accepted)))))

    (define (notice (model Ide) (text String)) (→ Step)
      (stay (Ide-status-set model (Status text "notice" (::attempt (::status model))))))

    (define (installing (model Ide)) (→ Step)
      (Pair model
            (list (Command (once (lambda ()
                                   (let ((result (install-app)))
                                     (command-result (lambda (current)
                                                       (installation-finished current result))))))
                           stay))))

    (define (installation-finished (model Ide) (result InstallResult)) (→ Step)
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

    (define (controlling (model Ide) (action String)) (→ Step)
      (let ((runs (::runs model)))
        (if (::pending runs)
            (stay model)
            (let ((target (::selected runs)))
              (Pair (Ide-runs-set model (Runs-problem-set (Runs-pending-set runs #t) ""))
                    (list (Command (once (lambda ()
                                           (let ((reply (api "POST"
                                                             (string-append "/api/run/"
                                                                            action
                                                                            "?target="
                                                                            (url-component
                                                                             target))
                                                             (Nil)
                                                             "")))
                                             (command-result (lambda (current)
                                                               (controlled current
                                                                           action
                                                                           target
                                                                           reply))))))
                                   (lambda (current)
                                     (controlled current
                                                 action
                                                 target
                                                 (Err interrupted-request))))))))))

    (define (controlled (model Ide) (action String) (target String) (result (Result Json Failure)))
      (→ Step)
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

    (define line-height (→ F64) 20.0)

    ;; The highlight layer draws from ten lines above the scroll 160 lines,
    ;; more than a pane shows, in runs of one class each. The highlighter reads
    ;; them from the start of their top-level form, as Emacs resynchronizes.

    (define (highlight-view (text String) (scroll F64) (scheme Bool)) (→ (Html Msg))
      (let* ((first (max 0 (- (f64->i64 (floor (/ scroll line-height))) 10)))
             (start (line-offset text (+ first 1)))
             (end (line-offset text (+ first 161))))
        (Element "pre"
                 (list (Attr "class" "highlight")
                       (Attr "style" (string-append "top: " (show (* first 20)) "px")))
                 (if scheme
                     (highlight-runs text start end)
                     (list (Text (substring text start end)))))))

    (define (highlight-runs (text String) (start I64) (end I64)) (→ (List (Html Msg)))
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

    (define (token-class (token Token)) (→ String)
      (match (::class token)
        ((Blank) "")
        ((Identifier) "")
        (class (string-append "tok-" (class-name class)))))

    ;; The runs, newest first, with a piece of `class` added.

    (define (joined (runs (List (Pair String String))) (class String) (piece String))
      (→ (List (Pair String String)))
      (match runs
        ((Cons (Pair last text) rest)
         (if (string=? last class)
             (Cons (Pair class (string-append text piece)) rest)
             (Cons (Pair class piece) runs)))
        ((Nil) (list (Pair class piece)))))

    (define (run-view (run (Pair String String))) (→ (Html Msg))
      (match run
        ((Pair "" text) (Text text))
        ((Pair class text) (Element "span" (list (Attr "class" class)) (list (Text text))))))

    ;; Compiler columns count scalars, as offsets do. Navigation keeps this
    ;; exact point; only the mark's display extends it to a lexical range.

    (define (source-offset (text String) (point Point)) (→ I64)
      (let loop ((offset (line-offset text (::line point))) (column 1))
        (if (and (< column (::column point))
                 (< offset (string-length text))
                 (not (char=? (string-ref text offset) #\newline)))
            (loop (+ offset 1) (+ column 1))
            offset)))

    (define (marks-view (text String) (found (Option Diagnostic))) (→ (Html Msg))
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

    (define (range-mark (text String) (range (Pair I64 I64)) (message String)) (→ (List (Html Msg)))
      (let ((start (::first range)) (end (::second range)))
        (list (Text (substring text 0 start))
              (Element "span"
                       (list (Attr "class" "error-highlight") (Attr "title" message))
                       (list (Text (if (or (= start end) (char=? (string-ref text start) #\newline))
                                       " "
                                       (substring text start end))))))))

    ;; ---- The view ----

    ;; The textarea's native selection is hidden while find owns focus.
    ;; Draw the same range over the syntax layer without changing its text.

    (define (find-mark (model Ide) (pane I64) (text String)) (→ (Html Msg))
      (Element "pre" (list (Attr "class" "marks") (Attr "aria-hidden" "true"))
               (match (palette-current-match (::palette model))
                 ((Some (palette-SelectDraftHit draft hit size))
                  (if (and (= pane (::active model)) (string=? text (::text draft)))
                      (let ((start (source-offset text
                                                  (Point (::path draft)
                                                         (::line hit)
                                                         (::column hit)))))
                        (list (Text (substring text 0 start))
                              (Element "span" (list (Attr "class" "find-highlight"))
                                       (list (Text (substring text start (+ start size)))))))
                      (Nil)))
                 (_ (Nil)))))

    ;; A compact button that leaves focus in the editor until its command runs.

    (define (tool (id String)
                  (class String)
                  (title String)
                  (label String)
                  (disabled Bool)
                  (message Msg))
      (→ (Html Msg))
      (Element "button"
               (list (Attr "id" id)
                     (Attr "class" class)
                     (Attr "title" title)
                     (FlagProperty "disabled" disabled)
                     (On "mousedown" (Nil) (Always) (lambda (event) (Nothing)))
                     (On "click" (Nil) (Allow) (lambda (event) message)))
               (list (Text label))))

    (define (view (model Ide)) (→ (Html Msg))
      (Element "div"
               (list (Attr "id" "workbench") (Attr "class" "ide")
                     (StringProperty "snailNavigation"
                                     (show (::generation (::palette model)))))
               (append (list (layout-view model)
                             (diagnostics-view model)
                             (runs-view (::runs model))
                             (status-view model))
                       (append (drag-view model) (palette-view model)))))

    (define (status-view (model Ide)) (→ (Html Msg))
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

    (define (palette-view (model Ide)) (→ (List (Html Msg)))
      (if (and (palette-visible? (::palette model)) (not (palette-finding? (::palette model))))
          (map (lambda (html) (map-html PaletteEvent html))
               (palette-view-component (::palette model) (palette-context model)))
          (Nil)))

    (define (find-view (model Ide) (pane I64)) (→ (List (Html Msg)))
      (if (and (= pane (::active model)) (palette-finding? (::palette model)))
          (map (lambda (html) (map-html PaletteEvent html))
               (palette-find-view (::palette model) (palette-context model)))
          (Nil)))

    (define (command-keys (name String)) (→ String)
      (string-join
       (delete-duplicates
        string=?
        (map (lambda (binding) (chord-label (::chord binding)))
             (filter (lambda (binding) (string=? name (::name binding)))
                     (vector->list (::bindings shortcuts)))))
       " / "))

    (define (chord-label (chord Chord)) (→ String)
      (string-append (if (= 0 (i32-and (::modifiers chord) control-key)) "" "Ctrl+")
                     (if (= 0 (i32-and (::modifiers chord) meta-key)) "" "⌘+")
                     (if (= 0 (i32-and (::modifiers chord) alt-key)) "" "Alt+")
                     (if (= 0 (i32-and (::modifiers chord) shift-key)) "" "Shift+")
                     (string-upcase (::key chord))))

    (define (layout-view (model Ide)) (→ (Html Msg))
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

    (define (path-parts (path String)) (→ (List String))
      (let loop ((end (string-length path)) (index (- (string-length path) 1)) (parts (Nil)))
        (cond ((< index 0) (Cons (substring path 0 end) parts))
              ((char=? (string-ref path index) #\/)
               (loop index (- index 1) (Cons (substring path (+ index 1) end) parts)))
              (else (loop end (- index 1) parts)))))

    ;; Each file is the parts of its path left to place, and its path.

    (define (file-tree (files (List (Pair (List String) String)))
                       (directories (List (List String))))
      (→ (List Tree))
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

    (define (car-part (file (Pair (List String) String))) (→ String)
      (match (::first file)
        ((Cons part _) part)
        ((Nil) "")))

    (define (files-view (model Ide)) (→ (Html Msg))
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

    (define (tree-view (model Ide) (entries (List Tree)) (prefix String)) (→ (Html Msg))
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

    (define (folder-view (model Ide) (name String) (entries (List Tree)) (path String))
      (→ (Html Msg))
      (Element "details"
               (list (FlagProperty "open" (member? path (::expanded model))))
               (list (Element "summary"
                              (list
                               (On "click" (Nil) (Always) (lambda (event) (ToggleFolder path))))
                              (list (Text name)))
                     (tree-view model entries path))))

    (define (file-button (model Ide) (name String) (path String)) (→ (Html Msg))
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

    (define (panes-view (model Ide)) (→ (List (Html Msg)))
      (let ((areas (pane-areas (::layout model) whole)))
        (append (map (lambda (pane)
                       (pane-view model
                                  (::id pane)
                                  (match (assoc-ref areas (::id pane))
                                    ((Some area) area)
                                    ((None) whole))))
                     (::panes model))
                (map divider-view (divisions (::layout model) whole)))))

    (define (percent (fraction F64)) (→ String)
      (string-append (f64->string (* fraction 100.0)) "%"))

    (define (placed (area Area)) (→ String)
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

    (define (divider-view (division Division)) (→ (Html Msg))
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

    (define (pane-view (model Ide) (id I64) (area Area)) (→ (Html Msg))
      (let* ((pane (pane-of model id)) (buffer (pane-buffer model id)))
        (Element "div"
                 (list (Keyed (string-append "pane-" (show id)))
                       (Attr "class" (if (= id (::active model)) "pane active" "pane"))
                       (Attr "style" (placed area)))
                 (append (list (Element "div"
                                        (list (Attr "class" "pane-header"))
                                        (list (tabs-view model pane)
                                              (tool ""
                                                    "pane-button"
                                                    "Close editor (Cmd/Ctrl+W or Alt+W)"
                                                    "×"
                                                    #f
                                                    (Close id))))
                               (editor-view model pane buffer)
                               (problem-view buffer)) (find-view model id)))))

    (define (tabs-view (model Ide) (pane EditorPane)) (→ (Html Msg))
      (Element "div" (list (Attr "id" (string-append "tabs-" (show (::id pane))))
                           (Attr "class" "pane-tabs") (Attr "role" "tablist")
                           (Attr "aria-label" "Open files"))
               (if (null? (::tabs pane))
                   (list (Element "span"
                                  (list (Attr "class" "pane-title"))
                                  (list (Text "Choose a file"))))
                   (map (lambda (path) (tab-view model pane path)) (::tabs pane)))))

    (define (tab-view (model Ide) (pane EditorPane) (path String)) (→ (Html Msg))
      (let ((selected (shows? pane path)))
        (Element "button"
                 (list (Keyed path) (Attr "id" (tab-id (::id pane) path))
                       (Attr "role" "tab") (Attr "data-path" path)
                       (Attr "class" (if selected "pane-tab active" "pane-tab"))
                       (Attr "aria-selected" (if selected "true" "false"))
                       (Attr "aria-controls" (scroller-id (::id pane)))
                       (Attr "title" path)
                       (On "click" (Nil) (Allow) (lambda (event) (SelectTab (::id pane) path))))
                 (list (Element "span" (list (Attr "class" (if selected "pane-title" "tab-title")))
                                (list (Text (pane-title (buffer-at model path)))))))))

    (define (pane-title (buffer (Option Buffer))) (→ String)
      (match buffer
        ((Some found) (string-append (::path found) (if (dirty? found) " ●" "")))
        ((None) "Choose a file")))

    (define (problem-view (buffer (Option Buffer))) (→ (Html Msg))
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

    (define (editor-view (model Ide) (pane EditorPane) (buffer (Option Buffer))) (→ (Html Msg))
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
                       (NumberProperty "scrollTop" (::scroll pane))
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
                                      (find-mark model id text)
                                      (field-view id buffer text scheme lines)))))))

    (define (field-view (id I64) (buffer (Option Buffer)) (text String) (scheme Bool) (lines I64))
      (→ (Html Msg))
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

    (define (diagnostics-view (model Ide)) (→ (Html Msg))
      (Element "div"
               (list (Attr "id" "diagnostics")
                     (Attr "class" "diagnostics")
                     (Attr "role" "status")
                     (FlagProperty "hidden" (null? (::diagnostics model))))
               (map-indexed (lambda (index diagnostic) (diagnostic-view model index diagnostic))
                            (::diagnostics model))))

    ;; A diagnostic in a project file is a button that shows its point.

    (define (diagnostic-view (model Ide) (index I64) (diagnostic Diagnostic)) (→ (Html Msg))
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

    (define (runs-view (runs Runs)) (→ (Html Msg))
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

    (define (option-view (run Run) (selected String)) (→ (Html Msg))
      (Element "option"
               (list (Keyed (::target run))
                     (Attr "value" (::target run))
                     (FlagProperty "selected" (string=? (::target run) selected)))
               (list
                (Text (string-append (::target run) (if (::available run) "" " (removed)"))))))

    (define (run-button (id String) (label String) (disabled Bool) (action String)) (→ (Html Msg))
      (Element "button"
               (list (Attr "id" id)
                     (Attr "class" "tool")
                     (FlagProperty "disabled" disabled)
                     (On "click" (Nil) (Allow) (lambda (event) (Control action))))
               (list (Text label))))

    ;; Output is text, never markup.

    (define (output-view (label String) (heading String) (id String) (text String)) (→ (Html Msg))
      (Element "section"
               (list (Attr "aria-label" label))
               (list (Element "h2" (Nil) (list (Text heading)))
                     (Element "pre"
                              (list (Attr "id" id) (Attr "tabindex" "0"))
                              (list (Text text))))))

    ;; While a drag is under way the page is covered, so the pointer's moves
    ;; reach the drag wherever they go.

    (define (drag-view (model Ide)) (→ (List (Html Msg)))
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

    (define (window (model Ide)) (→ (List (Attribute Msg)))
      (append (list (On "keydown"
                        (list (Key))
                        (Chords (append (if (palette-finding? (::palette model))
                                            (list (Chord "Escape" 0))
                                            (Nil))
                                        (shortcut-chords shortcuts)))
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

    ;; Version-one wire records stay unchanged so upgrading cannot strand drafts.
    (struct Pane
      ((id I64)
       (path (Option String))
       (scroll F64))
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

    (struct SavedTabs
      ((pane I64)
       (paths (List String)))
      (deriving Serialize Deserialize))

    (struct TabbedRecovery
      ((previous Recovery)
       (tabs (List SavedTabs)))
      (deriving Serialize Deserialize))

    ;; Read the legacy tag through its encoder, without copying a schema hash.
    ;; Both shapes use the same draft payload; only tab membership is new.

    (define (read-recovery (bytes Bytes)) (→ TabbedRecovery)
      (if (case-id=? (recovery-tag bytes) (recovery-tag (serialize (::previous (kept initial)))))
          (TabbedRecovery (deserialize bytes) (Nil))
          (deserialize bytes)))

    (define (recovery-tag (bytes Bytes)) (→ I32)
      (unsafe-total (lambda () (decode-case-id (Decoder bytes (ref 0))))))

    (define (kept (model Ide)) (→ TabbedRecovery)
      (TabbedRecovery
       (Recovery 1 (map kept-buffer (::buffers model))
                 (map (lambda (pane) (Pane (::id pane) (::path pane) (::scroll pane)))
                      (::panes model))
                 (::layout model) (::active model) (::next model) (Nil)
                 (::files-shown model) (::files-width model))
       (map (lambda (pane) (SavedTabs (::id pane) (::tabs pane))) (::panes model))))

    (define (kept-buffer (buffer Buffer)) (→ Draft)
      (Draft (::path buffer) (::text buffer)
             (match (::baseline buffer)
               ((Some baseline) (json->string (file->json baseline)))
               ((None) ""))))

    (define (restored (saved TabbedRecovery)) (→ Ide)
      (let ((save (::previous saved)))
        (unless (= (::version save) 1)
          (panic "unsupported IDE recovery version; saved drafts are retained"))
        (let* ((model (Ide-buffers-set initial (map restored-buffer (::drafts save))))
               (model (Ide-auto-open-set model #f))
               (model (Ide-panes-set model
                                     (map (lambda (pane) (restored-pane pane (::tabs saved)))
                                          (::panes save))))
               (model (Ide-layout-set model (::layout save)))
               (model (Ide-active-set model (::active save)))
               (model (Ide-next-set model (::next save)))
               (model (Ide-files-shown-set model (::files-shown save))))
          (Ide-files-width-set model (::files-width save)))))

    (define (restored-pane (pane Pane) (groups (List SavedTabs))) (→ EditorPane)
      (let ((tabs (match (find (lambda (group) (= (::pane group) (::id pane))) groups)
                    ((Some group) (::paths group))
                    ((None) (match (::path pane) ((Some path) (list path)) ((None) (Nil)))))))
        (EditorPane (::id pane) (::path pane) (::scroll pane) tabs)))

    (define (restored-buffer (draft Draft)) (→ Buffer)
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
