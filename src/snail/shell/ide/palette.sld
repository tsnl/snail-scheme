;; One palette owns command/file selection, search and entry creation. Its
;; input and result transitions do not know the IDE model. Only completed choices
;; cross back to the application, which owns buffers, panes and navigation.
(define-library (snail shell ide palette)
  (export State initial visible? finding? cancel
          Context Entry Mode Commands Files Searching Creating Creation
          Search SearchPhase Debouncing Fetching Finished
          Message Idle Query KeyPressed Pick FindNext Dismiss Reconnected
          Command CommandResult
          Outcome InvokeNamed OpenPath OpenSavedHit SelectDraftHit CreatedPath Dismissed
          Step open update reconcile view find-view current-match)
  (import
   (snail core base)
   (only (snail shell text) string-downcase)
   (snail shell task)
   (snail shell dom)
   (snail shell fetch)
   (snail shell json)
   (snail shell project client)
   (snail shell project protocol)
   (only (snail shell text search) Occurrence)
   (prefix (snail shell ide search) search-)
   (snail shell ui))
  (begin

    ;; ---- State and boundary ----

    (record Entry
      ((name String)
       (keys String)))

    (record Context
      ((commands (List Entry))
       (paths (List String))))

    (enum SearchPhase
      (Debouncing)
      (Fetching)
      (Finished ((result (Result search-Results Failure)))))

    (record Search
      ((source search-Source)
       (phase SearchPhase)))

    (record Creation
      ((directory Bool)
       (pending Bool)
       (problem String)))

    (enum Mode
      (Commands)
      (Files)
      (Searching ((search Search)))
      (Creating ((creation Creation))))

    (record Panel
      ((mode Mode)
       (query String)
       (selected I64)))

    ;; A generation is the identity of a palette interaction, including the
    ;; navigation it requested. It survives closing. New queries, openings,
    ;; cancellations and selections revoke every older timer, reply and choice.
    ;; Buffer reads and saves have separate owners and sequence numbers.
    (record State
      ((generation I64)
       (panel (Option Panel))))

    (enum Outcome
      (InvokeNamed ((name String)))
      (OpenPath ((path String)))
      (OpenSavedHit ((hit Hit)))
      (SelectDraftHit ((draft search-Draft)
                       (hit Occurrence)
                       (length I64)))
      (CreatedPath ((path String)
                    (directory Bool)))
      (Dismissed))

    (enum Action
      (Choose ((outcome Outcome)))
      (Create))

    (enum Message
      (Idle)
      (Query ((text String)))
      (KeyPressed ((key String)
                   (modifiers I32)))
      (Pick ((generation I64)
             (action Action)))
      (FindNext ((backwards Bool)))
      (Dismiss)
      (Reconnected))

    (type CommandResult (Fn State → Step))
    (record Command
      ((work (FnOnce → CommandResult ! tasks dom fetch))
       (interrupted CommandResult)))

    (record Step
      ((state State)
       (outcome (Option Outcome))
       (commands (List Command))))

    (define (initial) (→ State) (new State (generation 0) (panel (None))))

    (define (visible? (state State)) (→ Bool)
      (match (● state panel) ((Some _) #t) ((None) #f)))

    (define (finding? (state State)) (→ Bool)
      (match (● state panel)
        ((Some panel) (find-mode? (● panel mode)))
        ((None) #f)))

    (define (find-mode? (mode Mode)) (→ Bool)
      (match mode ((Searching (Search (search-CurrentDraft _) _)) #t) (_ #f)))

    (define (cancel (state State)) (→ State)
      (new State (generation (+ 1 (● state generation))) (panel (None))))

    (define (stay (state State))
      (→ Step)
      (new Step (state state) (outcome (None)) (commands (Nil))))

    (define (selected (state State) (outcome Outcome)) (→ Step)
      (new Step (state (cancel state)) (outcome (Some outcome)) (commands (Nil))))

    (define (open (state State) (mode Mode)) (→ Step)
      (new Step (state (if (and (finding? state) (find-mode? mode)) state
                           (new State
                             (generation (+ 1 (● state generation)))
                             (panel (Some (new Panel (mode mode) (query "") (selected 0)))))))
           (outcome (None))
           (commands (list (new Command (work (once (lambda ()
                                                      (match (element-by-id "command-query")
                                                        ((Some field) (focus-node field))
                                                        ((None) (unit)))
                                                      stay))) (interrupted stay))))))

    ;; ---- Updates ----

    (define (update (state State) (context Context) (message Message)) (→ Step)
      (match message
        ((Idle) (stay state))
        ((Query text) (queried state text))
        ((KeyPressed key modifiers) (pressed state context key modifiers))
        ((FindNext backwards) (find-next state context backwards))
        ((Pick generation action)
         (if (and (= generation (● state generation)) (visible? state))
             (match action
               ((Choose outcome) (selected state outcome))
               ((Create) (creating state)))
             (stay state)))
        ((Dismiss) (selected state (Dismissed)))
        ((Reconnected)
         (match (● state panel)
           ((Some (Panel (Searching (Search (search-SavedProject) _)) query _))
            (queried state query))
           (_ (stay state))))))

    ;; A draft can change through a read, reload or format as well as typing.
    ;; Reconcile after every parent update, so results retain exact provenance.

    (define (reconcile (state State) (draft (Option search-Draft))) (→ Step)
      (match (● state panel)
        ((Some panel)
         (match (● panel mode)
           ((Searching (Search (search-CurrentDraft old) _))
            (match draft
              ((Some draft)
               (if (search-same-draft? old draft) (stay state)
                   (queried (State-panel-set state
                                             (Some (Panel-mode-set panel
                                                                   (Searching
                                                                    (new Search
                                                                      (source
                                                                       (search-CurrentDraft draft))
                                                                      (phase (Debouncing)))))))
                            (● panel query))))
              ((None) (selected state (Dismissed)))))
           (_ (stay state))))
        ((None) (stay state))))

    (define (queried (state State) (text String)) (→ Step)
      (match (● state panel)
        ((Some panel)
         (if (creation-pending? panel) (stay state)
             (let* ((generation (+ 1 (● state generation)))
                    (mode (reset-mode (● panel mode)))
                    (next (new State
                            (generation generation)
                            (panel (Some (new Panel
                                           (mode mode)
                                           (query text)
                                           (selected (if (finding? state) -1 0))))))))
               (new Step (state next) (outcome (None))
                    (commands (if (and (searching? mode) (not (string=? text "")))
                                  (list (new Command (work (once (lambda ()
                                                                   (sleep 120)
                                                                   (lambda (current)
                                                                     (search-due current
                                                                                 generation)))))
                                             (interrupted (lambda (current)
                                                            (search-interrupted current
                                                                                generation)))))
                                  (Nil)))))))
        ((None) (stay state))))

    (define (reset-mode (mode Mode)) (→ Mode)
      (match mode
        ((Searching search) (Searching (Search-phase-set search (Debouncing))))
        ((Creating (Creation directory _ _))
         (Creating (new Creation (directory directory) (pending #f) (problem ""))))
        (_ mode)))

    (define (searching? (mode Mode)) (→ Bool)
      (match mode ((Searching _) #t) (_ #f)))

    (define (creation-pending? (panel Panel)) (→ Bool)
      (match (● panel mode) ((Creating (Creation _ pending _)) pending) (_ #f)))

    (define (mode-set (state State) (mode Mode)) (→ State)
      (match (● state panel)
        ((Some panel) (State-panel-set state (Some (Panel-mode-set panel mode))))
        ((None) state)))

    (define (pressed (state State) (context Context) (key String) (modifiers I32)) (→ Step)
      (match (● state panel)
        ((None) (stay state))
        ((Some panel)
         (let* ((options (choices context panel)) (count (length options)))
           (cond ((string=? key "Escape") (selected state (Dismissed)))
                 ((and (finding? state) (or (string=? key "Enter")
                                            (string=? key "ArrowUp")
                                            (string=? key "ArrowDown")))
                  (find-next state context (or (string=? key "ArrowUp") (= modifiers (shift-key)))))
                 ((and (string=? key "Enter") (> count 0))
                  (update state context
                          (Pick (● state generation)
                                (● (list-ref options (min (● panel selected) (- count 1)))
                                   action))))
                 ((string=? key "Enter") (stay state))
                 (else
                  (let* ((back (or (string=? key "ArrowUp") (= modifiers (shift-key))))
                         (at (max 0 (min (- count 1) (+ (● panel selected) (if back -1 1))))))
                    (stay (State-panel-set state (Some (Panel-selected-set panel at)))))))))))

    ;; Local find keeps its input and results while navigation reveals a match.

    (define (find-next (state State) (context Context) (backwards Bool)) (→ Step)
      (match (● state panel)
        ((Some panel)
         (let* ((options (choices context panel)) (count (length options))
                (at (+ (● panel selected) (if backwards -1 1)))
                (at (cond ((< at 0) (- count 1)) ((>= at count) 0) (else at))))
           (if (or (not (finding? state)) (= count 0)) (stay state)
               (match (● (list-ref options at) action)
                 ((Choose outcome)
                  (new Step
                    (state (new State
                             (generation (+ 1 (● state generation)))
                             (panel (Some (Panel-selected-set panel at)))))
                    (outcome (Some outcome)) (commands (Nil))))
                 (_ (stay state))))))
        ((None) (stay state))))

    (define (current-match (state State)) (→ (Option Outcome))
      (match (● state panel)
        ((Some panel)
         (let ((options (choices (new Context (commands (Nil)) (paths (Nil))) panel))
               (at (● panel selected)))
           (if (and (finding? state) (>= at 0) (< at (length options)))
               (match (● (list-ref options at) action) ((Choose outcome) (Some outcome)) (_ (None)))
               (None))))
        ((None) (None))))

    ;; ---- Search and creation tasks ----

    (define (search-due (state State) (generation I64)) (→ Step)
      (match (● state panel)
        ((Some (Panel (Searching (Search source (Debouncing))) query _))
         (if (and (= generation (● state generation)) (not (string=? query "")))
             (new Step
               (state (mode-set state (Searching (new Search (source source) (phase (Fetching))))))
               (outcome (None))
               (commands (list (new Command (work (once (lambda ()
                                                          (let ((result (search-run source query)))
                                                            (lambda (current)
                                                              (searched current
                                                                        generation
                                                                        result))))))
                                    (interrupted
                                     (lambda (current) (search-interrupted current generation)))))))
             (stay state)))
        (_ (stay state))))

    (define (interrupted-request) (→ Failure)
      (new Failure
        (status 0)
        (message "Request interrupted; its server-side outcome may be unknown.")))

    (define (search-interrupted (state State) (generation I64)) (→ Step)
      (match (● state panel)
        ((Some (Panel (Searching (Search source _)) _ _))
         (if (= generation (● state generation))
             (stay
              (mode-set state
                        (Searching (new Search
                                     (source source)
                                     (phase (Finished (Err (interrupted-request))))))))
             (stay state)))
        (_ (stay state))))

    (define (searched (state State) (generation I64) (result (Result search-Results Failure)))
      (→ Step)
      (match (● state panel)
        ((Some (Panel (Searching (Search source (Fetching))) _ _))
         (if (= generation (● state generation))
             (stay
              (mode-set state (Searching (new Search (source source) (phase (Finished result))))))
             (stay state)))
        (_ (stay state))))

    (define (creating (state State)) (→ Step)
      (match (● state panel)
        ((Some (Panel (Creating (Creation directory #f _)) path _))
         (if (string=? path "") (stay state)
             (let ((generation (● state generation)))
               (new Step
                 (state (mode-set state
                                  (Creating
                                   (new Creation (directory directory) (pending #t) (problem "")))))
                 (outcome (None))
                 (commands (list (new Command (work (once (lambda ()
                                                            (let ((result (api "POST" (string-append
                                                                                       (if directory
                                                                                           "/api/directory?path="
                                                                                           "/api/file?path=")
                                                                                       (url-component
                                                                                        path))
                                                                               (Nil)
                                                                               "")))
                                                              (lambda (current)
                                                                (created current
                                                                         generation
                                                                         result))))))
                                      (interrupted (lambda (current)
                                                     (created current
                                                              generation
                                                              (Err (interrupted-request))))))))))))
        (_ (stay state))))

    ;; Closing does not undo a write. Its watcher event still updates the file
    ;; tree, but only the interaction that submitted it may navigate on success.

    (define (created (state State) (generation I64) (result (Result Json Failure))) (→ Step)
      (match (● state panel)
        ((Some (Panel (Creating (Creation directory #t _)) path _))
         (if (= generation (● state generation))
             (match result
               ((Ok _) (selected state (CreatedPath path directory)))
               ((Err failure)
                (stay (mode-set state
                                (Creating (new Creation
                                            (directory directory)
                                            (pending #f)
                                            (problem (● failure message))))))))
             (stay state)))
        (_ (stay state))))

    ;; ---- Choices ----

    (record Choice
      ((label String)
       (detail String)
       (action Action)))

    ;; Ordered characters are sufficient for paths and symbolic command names.

    (define (matches? (query String) (text String)) (→ Bool)
      (let loop ((wanted (string->list (string-downcase query)))
                 (text (string->list (string-downcase text))))
        (match wanted
          ((Nil) #t)
          ((Cons char rest)
           (if (char-whitespace? char) (loop rest text)
               (match text
                 ((Nil) #f)
                 ((Cons next more) (loop (if (char=? char next) rest wanted) more))))))))

    (define (choices (context Context) (panel Panel)) (→ (List Choice))
      (let ((query (● panel query)))
        (match (● panel mode)
          ((Commands)
           (map (lambda (entry) (new Choice (label (● entry name)) (detail (● entry keys))
                                     (action (Choose (InvokeNamed (● entry name))))))
                (filter (lambda (entry) (matches? query (● entry name)))
                        (● context commands))))
          ((Files)
           (map
            (lambda (path) (new Choice (label path) (detail "") (action (Choose (OpenPath path)))))
            (take (filter (lambda (path) (matches? query path)) (● context paths)) 200)))
          ((Creating (Creation directory pending _))
           (if (or pending (string=? query "")) (Nil)
               (list
                (new Choice
                  (label (string-append (if directory "Create directory: " "Create file: ") query))
                  (detail "Enter") (action (Create))))))
          ((Searching (Search _ (Finished (Ok results))))
           (search-choices results (string-length query)))
          ((Searching _) (Nil)))))

    (define (location (path String) (line I64) (column I64)) (→ String)
      (string-append path ":" (show line) ":" (show column)))

    (define (search-choices (results search-Results) (size I64)) (→ (List Choice))
      (match results
        ((search-SavedResults results)
         (map (lambda (hit)
                (let ((point (● hit point)))
                  (new Choice (label (location (● point file) (● point line) (● point column)))
                       (detail (● hit snippet)) (action (Choose (OpenSavedHit hit))))))
              (● results hits)))
        ((search-DraftResults draft hits _)
         (map (lambda (hit)
                (new Choice
                  (label (location (● draft path) (● hit line) (● hit column)))
                  (detail (● hit snippet)) (action (Choose (SelectDraftHit draft hit size)))))
              hits))))

    ;; ---- View ----

    (define (find-view (state State) (context Context)) (→ (List (Html Message)))
      (match (● state panel)
        ((Some panel)
         (let ((count (length (choices context panel))))
           (list (Element "section"
                          (list (Attr "id" "find-widget") (Attr "class" "find-widget")
                                (Attr "role" "search") (Attr "aria-label" "Find in current file")
                                (On "keydown" (list (Key)) (Chords (find-chords))
                                    (lambda (event)
                                      (KeyPressed (● event key) (● event modifiers)))))
                          (list (find-input panel)
                                (Element "span"
                                         (list (Attr "id" "find-count") (Attr "role" "status"))
                                         (list (Text (find-status panel count))))
                                (find-button "Previous match (Shift+Enter)"
                                             "↑"
                                             (= count 0)
                                             (FindNext #t))
                                (find-button "Next match (Enter)" "↓" (= count 0) (FindNext #f))
                                (find-button "Close find (Escape)" "×" #f (Dismiss)))))))
        ((None) (Nil))))

    (define (find-input (panel Panel)) (→ (Html Message))
      (Element "input"
               (list (Attr "id" "command-query") (Attr "placeholder" "Find")
                     (Attr "aria-label" "Find in current file")
                     (Attr "aria-describedby" "find-count")
                     (Attr "autocomplete" "off") (Attr "spellcheck" "false")
                     (StringProperty "value" (● panel query))
                     (On "input" (list (Value)) (Allow) (lambda (event) (Query (● event value)))))
               (Nil)))

    (define (find-button (title String) (label String) (disabled Bool) (message Message))
      (→ (Html Message))
      (Element "button"
               (list (Attr "title" title) (Attr "aria-label" title)
                     (FlagProperty "disabled" disabled)
                     (On "mousedown" (Nil) (Always) (lambda (event) (Idle)))
                     (On "click" (Nil) (Allow) (lambda (event) message)))
               (list (Text label))))

    (define (find-status (panel Panel) (count I64)) (→ String)
      (if (string=? (● panel query) "") ""
          (match (● panel mode)
            ((Searching (Search _ (Finished (Ok results))))
             (string-append (if (= count 0) "No matches"
                                (if (< (● panel selected) 0) (string-append (show count) " matches")
                                    (string-append (show (+ 1 (● panel selected)))
                                                   " of "
                                                   (show count))))
                            (search-summary results)))
            ((Searching (Search _ (Finished (Err failure)))) (● failure message))
            (_ "Searching…"))))

    (define (find-chords) (→ (List Chord))
      (list (new Chord (key "Enter") (modifiers 0))
            (new Chord (key "Enter") (modifiers (shift-key)))
            (new Chord (key "Escape") (modifiers 0))
            (new Chord (key "ArrowUp") (modifiers 0)) (new Chord (key "ArrowDown") (modifiers 0))))

    (define (view (state State) (context Context)) (→ (List (Html Message)))
      (match (● state panel)
        ((None) (Nil))
        ((Some panel)
         (let* ((choices (choices context panel))
                (selected (min (● panel selected) (- (length choices) 1))))
           (list (Element "div" (list (Attr "class" "palette-layer"))
                          (list (Element "button"
                                         (list (Attr "class" "palette-backdrop")
                                               (Attr "tabindex" "-1")
                                               (Attr "aria-label" "Close palette")
                                               (On "click"
                                                   (Nil)
                                                   (Allow)
                                                   (lambda (event) (Dismiss))))
                                         (Nil))
                                (Element "section"
                                         (list (Attr "class" "palette") (Attr "role" "dialog")
                                               (Attr "aria-modal" "true")
                                               (Attr "aria-label" (panel-title panel)))
                                         (list (panel-input panel selected)
                                               (panel-results panel
                                                              choices
                                                              selected
                                                              (● state generation))
                                               (Element "p" (list (Attr "id" "palette-help")
                                                                  (Attr "class" "palette-help"))
                                                        (list
                                                         (Text (panel-help panel)))))))))))))

    (define (panel-title (panel Panel)) (→ String)
      (match (● panel mode)
        ((Commands) "Run a command…")
        ((Files) "Go to file…")
        ((Searching (Search source _))
         (match source
           ((search-SavedProject) "Search saved text…")
           ((search-CurrentDraft _) "Search current file…")))
        ((Creating (Creation directory _ _))
         (if directory "New directory path…" "New file path…"))))

    (define (panel-input (panel Panel) (selected I64)) (→ (Html Message))
      (Element "input"
               (list (Attr "id" "command-query")
                     (Attr "placeholder" (panel-title panel))
                     (Attr "aria-label" (panel-title panel))
                     (Attr "role" "combobox") (Attr "aria-expanded" "true")
                     (Attr "aria-controls" "command-results") (Attr "aria-autocomplete" "list")
                     (Attr "aria-describedby" "palette-help")
                     (Attr "aria-activedescendant"
                           (if (< selected 0) "" (string-append "command-result-" (show selected))))
                     (Attr "autocomplete" "off") (Attr "spellcheck" "false")
                     (FlagProperty "readOnly" (creation-pending? panel))
                     (StringProperty "value" (● panel query))
                     (On "input" (list (Value)) (Allow)
                         (lambda (event) (Query (● event value))))
                     (On "keydown" (list (Key)) (Chords (panel-chords))
                         (lambda (event) (KeyPressed (● event key) (● event modifiers)))))
               (Nil)))

    (define (panel-results (panel Panel) (choices (List Choice)) (selected I64) (generation I64))
      (→ (Html Message))
      (Element "div"
               (list (Attr "id" "command-results") (Attr "role" "listbox")
                     (NumberProperty "scrollTop" (i64->f64 (max 0 (- (* selected 30) 180)))))
               (if (null? choices)
                   (list (Element "p" (list (Attr "class" "palette-empty") (Attr "role" "status"))
                                  (list (Text (panel-empty panel)))))
                   (map-indexed
                    (lambda (index choice)
                      (panel-option choice index (= index selected) generation))
                    choices))))

    (define (panel-empty (panel Panel)) (→ String)
      (match (● panel mode)
        ((Searching (Search _ phase))
         (if (string=? (● panel query) "") "Type text to search"
             (match phase
               ((Finished (Err failure)) (● failure message))
               ((Finished (Ok _)) "No matches")
               (_ "Searching…"))))
        ((Creating (Creation _ pending _))
         (if pending "Creating…" "Enter a path relative to the project"))
        (_ "No matches")))

    (define (panel-help (panel Panel)) (→ String)
      (match (● panel mode)
        ((Searching (Search source phase))
         (string-append
          (match source
            ((search-SavedProject) "Saved text · ignores case · drafts stay unchanged")
            ((search-CurrentDraft _) "Current draft · ignores case · includes unsaved text"))
          (match phase
            ((Finished (Ok results)) (search-summary results))
            (_ ""))))
        ((Creating (Creation _ _ problem))
         (if (string=? problem "")
             "Enter creates · Escape closes · Parent directory must exist" problem))
        ((Files) "↑ ↓ choose · Enter open · Escape close · Up to 200 paths; type to narrow")
        ((Commands) "↑ ↓ choose · Enter run · Escape close")))

    (define (panel-option (choice Choice) (index I64) (selected Bool) (generation I64))
      (→ (Html Message))
      (Element "button"
               (list (Attr "id" (string-append "command-result-" (show index)))
                     (Attr "class" (if selected "palette-option selected" "palette-option"))
                     (Attr "role" "option") (Attr "aria-selected" (if selected "true" "false"))
                     (Attr "tabindex" "-1")
                     (Attr "data-command"
                           (match (● choice action) ((Choose (InvokeNamed name)) name) (_ "")))
                     (On "mousedown" (Nil) (Always) (lambda (event) (Idle)))
                     (On "click"
                         (Nil)
                         (Allow)
                         (lambda (event) (Pick generation (● choice action)))))
               (list
                (Element "span"
                         (list (Attr "class" "choice-label"))
                         (list (Text (● choice label))))
                (Element "span"
                         (list (Attr "class" "command-keys"))
                         (list (Text (● choice detail)))))))

    (define (search-summary (results search-Results)) (→ String)
      (match results
        ((search-SavedResults results)
         (string-append (limit-notice (● results limited))
                        (if (> (● results skipped) 0)
                            (string-append " · "
                                           (show (● results skipped))
                                           " files skipped")
                            "")))
        ((search-DraftResults _ _ limited) (limit-notice limited))))

    (define (limit-notice (limited Bool)) (→ String)
      (if limited " · Results limited; narrow your query" ""))

    (define (panel-chords) (→ (List Chord))
      (Cons (new Chord (key "Tab") (modifiers (shift-key)))
            (map (lambda (key) (new Chord (key key) (modifiers 0)))
                 (list "ArrowUp" "ArrowDown" "Enter" "Escape" "Tab"))))
    ))
