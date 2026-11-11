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

    (struct Entry
      ((name String)
       (keys String)))

    (struct Context
      ((commands (List Entry))
       (paths (List String))))

    (enum SearchPhase
      (Debouncing)
      (Fetching)
      (Finished ((result (Result search-Results Failure)))))

    (struct Search
      ((source search-Source)
       (phase SearchPhase)))

    (struct Creation
      ((directory Bool)
       (pending Bool)
       (problem String)))

    (enum Mode
      (Commands)
      (Files)
      (Searching ((search Search)))
      (Creating ((creation Creation))))

    (struct Panel
      ((mode Mode)
       (query String)
       (selected I64)))

    ;; A generation is the identity of a palette interaction, including the
    ;; navigation it requested. It survives closing. New queries, openings,
    ;; cancellations and selections revoke every older timer, reply and choice.
    ;; Buffer reads and saves have separate owners and sequence numbers.
    (struct State
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

    (type CommandResult (dyn (Fn State → Step)))
    (struct Command
      ((work (dyn (FnOnce → CommandResult ! tasks dom fetch)))
       (interrupted CommandResult)))

    (struct Step
      ((state State)
       (outcome (Option Outcome))
       (commands (List Command))))

    (define initial (→ State) (State 0 (None)))

    (define (visible? (state State)) (→ Bool)
      (match (::panel state) ((Some _) #t) ((None) #f)))

    (define (finding? (state State)) (→ Bool)
      (match (::panel state)
        ((Some panel) (find-mode? (::mode panel)))
        ((None) #f)))

    (define (find-mode? (mode Mode)) (→ Bool)
      (match mode ((Searching (Search (search-CurrentDraft _) _)) #t) (_ #f)))

    (define (cancel (state State)) (→ State)
      (State (+ 1 (::generation state)) (None)))

    (define (stay (state State)) (→ Step) (Step state (None) (Nil)))

    (define (selected (state State) (outcome Outcome)) (→ Step)
      (Step (cancel state) (Some outcome) (Nil)))

    (define (open (state State) (mode Mode)) (→ Step)
      (Step (if (and (finding? state) (find-mode? mode)) state
                (State (+ 1 (::generation state)) (Some (Panel mode "" 0)))) (None)
                (list (Command (once (lambda ()
                                       (match (element-by-id "command-query")
                                         ((Some field) (focus-node field))
                                         ((None) (unit)))
                                       stay)) stay))))

    ;; ---- Updates ----

    (define (update (state State) (context Context) (message Message)) (→ Step)
      (match message
        ((Idle) (stay state))
        ((Query text) (queried state text))
        ((KeyPressed key modifiers) (pressed state context key modifiers))
        ((FindNext backwards) (find-next state context backwards))
        ((Pick generation action)
         (if (and (= generation (::generation state)) (visible? state))
             (match action
               ((Choose outcome) (selected state outcome))
               ((Create) (creating state)))
             (stay state)))
        ((Dismiss) (selected state (Dismissed)))
        ((Reconnected)
         (match (::panel state)
           ((Some (Panel (Searching (Search (search-SavedProject) _)) query _))
            (queried state query))
           (_ (stay state))))))

    ;; A draft can change through a read, reload or format as well as typing.
    ;; Reconcile after every parent update, so results retain exact provenance.

    (define (reconcile (state State) (draft (Option search-Draft))) (→ Step)
      (match (::panel state)
        ((Some panel)
         (match (::mode panel)
           ((Searching (Search (search-CurrentDraft old) _))
            (match draft
              ((Some draft)
               (if (search-same-draft? old draft) (stay state)
                   (queried (State-panel-set state
                                             (Some (Panel-mode-set panel
                                                                   (Searching
                                                                    (Search
                                                                     (search-CurrentDraft draft)
                                                                     (Debouncing))))))
                            (::query panel))))
              ((None) (selected state (Dismissed)))))
           (_ (stay state))))
        ((None) (stay state))))

    (define (queried (state State) (text String)) (→ Step)
      (match (::panel state)
        ((Some panel)
         (if (creation-pending? panel) (stay state)
             (let* ((generation (+ 1 (::generation state)))
                    (mode (reset-mode (::mode panel)))
                    (next (State generation (Some (Panel mode text (if (finding? state) -1 0))))))
               (Step next (None)
                     (if (and (searching? mode) (not (string=? text "")))
                         (list (Command (once (lambda ()
                                                (sleep 120)
                                                (lambda (current) (search-due current generation))))
                                        (lambda (current) (search-interrupted current generation))))
                         (Nil))))))
        ((None) (stay state))))

    (define (reset-mode (mode Mode)) (→ Mode)
      (match mode
        ((Searching search) (Searching (Search-phase-set search (Debouncing))))
        ((Creating (Creation directory _ _)) (Creating (Creation directory #f "")))
        (_ mode)))

    (define (searching? (mode Mode)) (→ Bool)
      (match mode ((Searching _) #t) (_ #f)))

    (define (creation-pending? (panel Panel)) (→ Bool)
      (match (::mode panel) ((Creating (Creation _ pending _)) pending) (_ #f)))

    (define (mode-set (state State) (mode Mode)) (→ State)
      (match (::panel state)
        ((Some panel) (State-panel-set state (Some (Panel-mode-set panel mode))))
        ((None) state)))

    (define (pressed (state State) (context Context) (key String) (modifiers I32)) (→ Step)
      (match (::panel state)
        ((None) (stay state))
        ((Some panel)
         (let* ((options (choices context panel)) (count (length options)))
           (cond ((string=? key "Escape") (selected state (Dismissed)))
                 ((and (finding? state) (or (string=? key "Enter")
                                            (string=? key "ArrowUp")
                                            (string=? key "ArrowDown")))
                  (find-next state context (or (string=? key "ArrowUp") (= modifiers shift-key))))
                 ((and (string=? key "Enter") (> count 0))
                  (update state context
                          (Pick (::generation state)
                                (::action
                                 (list-ref options (min (::selected panel) (- count 1)))))))
                 ((string=? key "Enter") (stay state))
                 (else
                  (let* ((back (or (string=? key "ArrowUp") (= modifiers shift-key)))
                         (at (max 0 (min (- count 1) (+ (::selected panel) (if back -1 1))))))
                    (stay (State-panel-set state (Some (Panel-selected-set panel at)))))))))))

    ;; Local find keeps its input and results while navigation reveals a match.

    (define (find-next (state State) (context Context) (backwards Bool)) (→ Step)
      (match (::panel state)
        ((Some panel)
         (let* ((options (choices context panel)) (count (length options))
                (at (+ (::selected panel) (if backwards -1 1)))
                (at (cond ((< at 0) (- count 1)) ((>= at count) 0) (else at))))
           (if (or (not (finding? state)) (= count 0)) (stay state)
               (match (::action (list-ref options at))
                 ((Choose outcome)
                  (Step (State (+ 1 (::generation state)) (Some (Panel-selected-set panel at)))
                        (Some outcome) (Nil)))
                 (_ (stay state))))))
        ((None) (stay state))))

    (define (current-match (state State)) (→ (Option Outcome))
      (match (::panel state)
        ((Some panel)
         (let ((options (choices (Context (Nil) (Nil)) panel)) (at (::selected panel)))
           (if (and (finding? state) (>= at 0) (< at (length options)))
               (match (::action (list-ref options at)) ((Choose outcome) (Some outcome)) (_ (None)))
               (None))))
        ((None) (None))))

    ;; ---- Search and creation tasks ----

    (define (search-due (state State) (generation I64)) (→ Step)
      (match (::panel state)
        ((Some (Panel (Searching (Search source (Debouncing))) query _))
         (if (and (= generation (::generation state)) (not (string=? query "")))
             (Step (mode-set state (Searching (Search source (Fetching)))) (None)
                   (list (Command (once (lambda ()
                                          (let ((result (search-run source query)))
                                            (lambda (current)
                                              (searched current generation result)))))
                                  (lambda (current) (search-interrupted current generation)))))
             (stay state)))
        (_ (stay state))))

    (define interrupted-request (→ Failure)
      (Failure 0 "Request interrupted; its server-side outcome may be unknown."))

    (define (search-interrupted (state State) (generation I64)) (→ Step)
      (match (::panel state)
        ((Some (Panel (Searching (Search source _)) _ _))
         (if (= generation (::generation state))
             (stay
              (mode-set state (Searching (Search source (Finished (Err interrupted-request))))))
             (stay state)))
        (_ (stay state))))

    (define (searched (state State) (generation I64) (result (Result search-Results Failure)))
      (→ Step)
      (match (::panel state)
        ((Some (Panel (Searching (Search source (Fetching))) _ _))
         (if (= generation (::generation state))
             (stay (mode-set state (Searching (Search source (Finished result)))))
             (stay state)))
        (_ (stay state))))

    (define (creating (state State)) (→ Step)
      (match (::panel state)
        ((Some (Panel (Creating (Creation directory #f _)) path _))
         (if (string=? path "") (stay state)
             (let ((generation (::generation state)))
               (Step (mode-set state (Creating (Creation directory #t ""))) (None)
                     (list (Command (once (lambda ()
                                            (let ((result (api "POST" (string-append
                                                                       (if directory
                                                                           "/api/directory?path="
                                                                           "/api/file?path=")
                                                                       (url-component path))
                                                               (Nil)
                                                               "")))
                                              (lambda (current)
                                                (created current generation result)))))
                                    (lambda (current)
                                      (created current generation (Err interrupted-request)))))))))
        (_ (stay state))))

    ;; Closing does not undo a write. Its watcher event still updates the file
    ;; tree, but only the interaction that submitted it may navigate on success.

    (define (created (state State) (generation I64) (result (Result Json Failure))) (→ Step)
      (match (::panel state)
        ((Some (Panel (Creating (Creation directory #t _)) path _))
         (if (= generation (::generation state))
             (match result
               ((Ok _) (selected state (CreatedPath path directory)))
               ((Err failure)
                (stay (mode-set state
                                (Creating (Creation directory #f (::message failure)))))))
             (stay state)))
        (_ (stay state))))

    ;; ---- Choices ----

    (struct Choice
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
      (let ((query (::query panel)))
        (match (::mode panel)
          ((Commands)
           (map (lambda (entry) (Choice (::name entry) (::keys entry)
                                        (Choose (InvokeNamed (::name entry)))))
                (filter (lambda (entry) (matches? query (::name entry)))
                        (::commands context))))
          ((Files)
           (map (lambda (path) (Choice path "" (Choose (OpenPath path))))
                (take (filter (lambda (path) (matches? query path)) (::paths context)) 200)))
          ((Creating (Creation directory pending _))
           (if (or pending (string=? query "")) (Nil)
               (list
                (Choice (string-append (if directory "Create directory: " "Create file: ") query)
                        "Enter" (Create)))))
          ((Searching (Search _ (Finished (Ok results))))
           (search-choices results (string-length query)))
          ((Searching _) (Nil)))))

    (define (location (path String) (line I64) (column I64)) (→ String)
      (string-append path ":" (show line) ":" (show column)))

    (define (search-choices (results search-Results) (size I64)) (→ (List Choice))
      (match results
        ((search-SavedResults results)
         (map (lambda (hit)
                (let ((point (::point hit)))
                  (Choice (location (::file point) (::line point) (::column point))
                          (::snippet hit) (Choose (OpenSavedHit hit)))))
              (::hits results)))
        ((search-DraftResults draft hits _)
         (map (lambda (hit)
                (Choice
                 (location (::path draft) (::line hit) (::column hit))
                 (::snippet hit) (Choose (SelectDraftHit draft hit size)))) hits))))

    ;; ---- View ----

    (define (find-view (state State) (context Context)) (→ (List (Html Message)))
      (match (::panel state)
        ((Some panel)
         (let ((count (length (choices context panel))))
           (list (Element "section"
                          (list (Attr "id" "find-widget") (Attr "class" "find-widget")
                                (Attr "role" "search") (Attr "aria-label" "Find in current file")
                                (On "keydown" (list (Key)) (Chords find-chords)
                                    (lambda (event)
                                      (KeyPressed (::key event) (::modifiers event)))))
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
                     (StringProperty "value" (::query panel))
                     (On "input" (list (Value)) (Allow) (lambda (event) (Query (::value event)))))
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
      (if (string=? (::query panel) "") ""
          (match (::mode panel)
            ((Searching (Search _ (Finished (Ok results))))
             (string-append (if (= count 0) "No matches"
                                (if (< (::selected panel) 0) (string-append (show count) " matches")
                                    (string-append (show (+ 1 (::selected panel)))
                                                   " of "
                                                   (show count))))
                            (search-summary results)))
            ((Searching (Search _ (Finished (Err failure)))) (::message failure))
            (_ "Searching…"))))

    (define find-chords (→ (List Chord))
      (list (Chord "Enter" 0) (Chord "Enter" shift-key) (Chord "Escape" 0)
            (Chord "ArrowUp" 0) (Chord "ArrowDown" 0)))

    (define (view (state State) (context Context)) (→ (List (Html Message)))
      (match (::panel state)
        ((None) (Nil))
        ((Some panel)
         (let* ((choices (choices context panel))
                (selected (min (::selected panel) (- (length choices) 1))))
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
                                                              (::generation state))
                                               (Element "p" (list (Attr "id" "palette-help")
                                                                  (Attr "class" "palette-help"))
                                                        (list
                                                         (Text (panel-help panel)))))))))))))

    (define (panel-title (panel Panel)) (→ String)
      (match (::mode panel)
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
                     (StringProperty "value" (::query panel))
                     (On "input" (list (Value)) (Allow)
                         (lambda (event) (Query (::value event))))
                     (On "keydown" (list (Key)) (Chords panel-chords)
                         (lambda (event) (KeyPressed (::key event) (::modifiers event)))))
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
      (match (::mode panel)
        ((Searching (Search _ phase))
         (if (string=? (::query panel) "") "Type text to search"
             (match phase
               ((Finished (Err failure)) (::message failure))
               ((Finished (Ok _)) "No matches")
               (_ "Searching…"))))
        ((Creating (Creation _ pending _))
         (if pending "Creating…" "Enter a path relative to the project"))
        (_ "No matches")))

    (define (panel-help (panel Panel)) (→ String)
      (match (::mode panel)
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
                           (match (::action choice) ((Choose (InvokeNamed name)) name) (_ "")))
                     (On "mousedown" (Nil) (Always) (lambda (event) (Idle)))
                     (On "click"
                         (Nil)
                         (Allow)
                         (lambda (event) (Pick generation (::action choice)))))
               (list
                (Element "span"
                         (list (Attr "class" "choice-label"))
                         (list (Text (::label choice))))
                (Element "span"
                         (list (Attr "class" "command-keys"))
                         (list (Text (::detail choice)))))))

    (define (search-summary (results search-Results)) (→ String)
      (match results
        ((search-SavedResults results)
         (string-append (limit-notice (::limited results))
                        (if (> (::skipped results) 0)
                            (string-append " · "
                                           (show (::skipped results))
                                           " files skipped")
                            "")))
        ((search-DraftResults _ _ limited) (limit-notice limited))))

    (define (limit-notice (limited Bool)) (→ String)
      (if limited " · Results limited; narrow your query" ""))

    (define panel-chords (→ (List Chord))
      (Cons (Chord "Tab" shift-key)
            (map (lambda (key) (Chord key 0)) (list "ArrowUp" "ArrowDown" "Enter" "Escape" "Tab"))))
    ))
