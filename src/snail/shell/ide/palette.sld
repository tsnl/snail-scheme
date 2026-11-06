;; One palette owns command/file selection, search and entry creation. Its
;; local messages and tasks do not know the IDE model. Only completed choices
;; cross back to the application, which owns buffers, panes and navigation.
(define-library (snail shell ide palette)
  (export State State-generation initial visible? cancel
          Context Entry Mode Commands Files Searching Creating Creation
          Search SearchPhase Debouncing Fetching Finished
          Message Idle Query KeyPressed Pick Due Found Created Dismiss Reconnected
          Outcome InvokeNamed OpenPath OpenSavedHit SelectDraftHit CreatedPath Dismissed
          Step open update reconcile view)
  (import
   (snail core base)
   (only (snail shell text) string-downcase)
   (snail shell task)
   (snail shell dom)
   (snail shell fetch)
   (snail shell json)
   (snail shell project client)
   (snail shell project protocol)
   (only (snail shell text search) Occurrence Occurrence-line Occurrence-column Occurrence-snippet)
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
                       (hit Occurrence)))
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
      (Due ((generation I64)))
      (Found ((generation I64)
              (result (Result search-Results Failure))))
      (Created ((generation I64)
                (result (Result Json Failure))))
      (Dismiss)
      (Reconnected))

    (type Command (FnOnce Message ! tasks dom fetch))

    (struct Step
      ((state State)
       (outcome (Option Outcome))
       (commands (List Command))))

    (: initial State)
    (define initial (State 0 (None)))

    (: visible? (-> State Bool))
    (define (visible? state)
      (match (State-panel state) ((Some _) #t) ((None) #f)))

    (: cancel (-> State State))
    (define (cancel state)
      (State (+ 1 (State-generation state)) (None)))

    (: stay (-> State Step))
    (define (stay state) (Step state (None) (Nil)))

    (: selected (-> State Outcome Step))
    (define (selected state outcome)
      (Step (cancel state) (Some outcome) (Nil)))

    (: open (-> State Mode Step))
    (define (open state mode)
      (Step (State (+ 1 (State-generation state)) (Some (Panel mode "" 0))) (None)
            (list (once (lambda ()
                          (match (element-by-id "command-query")
                            ((Some field) (focus-node field))
                            ((None) (unit)))
                          (Idle))))))

    ;; ---- Updates ----

    (: update (-> State Context Message Step))
    (define (update state context message)
      (match message
        ((Idle) (stay state))
        ((Query text) (queried state text))
        ((KeyPressed key modifiers) (pressed state context key modifiers))
        ((Pick generation action)
         (if (and (= generation (State-generation state)) (visible? state))
             (match action
               ((Choose outcome) (selected state outcome))
               ((Create) (creating state)))
             (stay state)))
        ((Due generation) (search-due state generation))
        ((Found generation result) (searched state generation result))
        ((Created generation result) (created state generation result))
        ((Dismiss) (selected state (Dismissed)))
        ((Reconnected)
         (match (State-panel state)
           ((Some (Panel (Searching (Search (search-SavedProject) _)) query _))
            (queried state query))
           (_ (stay state))))))

    ;; A draft can change through a read, reload or format as well as typing.
    ;; Reconcile after every parent update, so results retain exact provenance.
    (: reconcile (-> State (Option search-Draft) Step))
    (define (reconcile state draft)
      (match (State-panel state)
        ((Some panel)
         (match (Panel-mode panel)
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
                            (Panel-query panel))))
              ((None) (selected state (Dismissed)))))
           (_ (stay state))))
        ((None) (stay state))))

    (: queried (-> State String Step))
    (define (queried state text)
      (match (State-panel state)
        ((Some panel)
         (if (creation-pending? panel) (stay state)
             (let* ((generation (+ 1 (State-generation state)))
                    (mode (reset-mode (Panel-mode panel)))
                    (next (State generation (Some (Panel mode text 0)))))
               (Step next (None)
                     (if (and (searching? mode) (not (string=? text "")))
                         (list (once (lambda () (sleep 120) (Due generation)))) (Nil))))))
        ((None) (stay state))))

    (: reset-mode (-> Mode Mode))
    (define (reset-mode mode)
      (match mode
        ((Searching search) (Searching (Search-phase-set search (Debouncing))))
        ((Creating (Creation directory _ _)) (Creating (Creation directory #f "")))
        (_ mode)))

    (: searching? (-> Mode Bool))
    (define (searching? mode)
      (match mode ((Searching _) #t) (_ #f)))

    (: creation-pending? (-> Panel Bool))
    (define (creation-pending? panel)
      (match (Panel-mode panel) ((Creating (Creation _ pending _)) pending) (_ #f)))

    (: mode-set (-> State Mode State))
    (define (mode-set state mode)
      (match (State-panel state)
        ((Some panel) (State-panel-set state (Some (Panel-mode-set panel mode))))
        ((None) state)))

    (: pressed (-> State Context String I32 Step))
    (define (pressed state context key modifiers)
      (match (State-panel state)
        ((None) (stay state))
        ((Some panel)
         (let* ((options (choices context panel)) (count (length options)))
           (cond ((string=? key "Escape") (selected state (Dismissed)))
                 ((and (string=? key "Enter") (> count 0))
                  (update state context
                          (Pick (State-generation state)
                                (Choice-action
                                 (list-ref options (min (Panel-selected panel) (- count 1)))))))
                 ((string=? key "Enter") (stay state))
                 (else
                  (let* ((back (or (string=? key "ArrowUp") (= modifiers shift-key)))
                         (at (max 0 (min (- count 1) (+ (Panel-selected panel) (if back -1 1))))))
                    (stay (State-panel-set state (Some (Panel-selected-set panel at)))))))))))

    ;; ---- Search and creation tasks ----

    (: search-due (-> State I64 Step))
    (define (search-due state generation)
      (match (State-panel state)
        ((Some (Panel (Searching (Search source (Debouncing))) query _))
         (if (and (= generation (State-generation state)) (not (string=? query "")))
             (Step (mode-set state (Searching (Search source (Fetching)))) (None)
                   (list (once (lambda () (Found generation (search-run source query))))))
             (stay state)))
        (_ (stay state))))

    (: searched (-> State I64 (Result search-Results Failure) Step))
    (define (searched state generation result)
      (match (State-panel state)
        ((Some (Panel (Searching (Search source (Fetching))) _ _))
         (if (= generation (State-generation state))
             (stay (mode-set state (Searching (Search source (Finished result)))))
             (stay state)))
        (_ (stay state))))

    (: creating (-> State Step))
    (define (creating state)
      (match (State-panel state)
        ((Some (Panel (Creating (Creation directory #f _)) path _))
         (if (string=? path "") (stay state)
             (let ((generation (State-generation state)))
               (Step (mode-set state (Creating (Creation directory #t ""))) (None)
                     (list (once (lambda ()
                                   (Created generation
                                            (api "POST" (string-append
                                                         (if directory
                                                             "/api/directory?path="
                                                             "/api/file?path=")
                                                         (url-component path)) (Nil) "")))))))))
        (_ (stay state))))

    ;; Closing does not undo a write. Its watcher event still updates the file
    ;; tree, but only the interaction that submitted it may navigate on success.
    (: created (-> State I64 (Result Json Failure) Step))
    (define (created state generation result)
      (match (State-panel state)
        ((Some (Panel (Creating (Creation directory #t _)) path _))
         (if (= generation (State-generation state))
             (match result
               ((Ok _) (selected state (CreatedPath path directory)))
               ((Err failure)
                (stay (mode-set state
                                (Creating (Creation directory #f (Failure-message failure)))))))
             (stay state)))
        (_ (stay state))))

    ;; ---- Choices ----

    (struct Choice
      ((label String)
       (detail String)
       (action Action)))

    ;; Ordered characters are sufficient for paths and symbolic command names.
    (: matches? (-> String String Bool))
    (define (matches? query text)
      (let loop ((wanted (string->list (string-downcase query)))
                 (text (string->list (string-downcase text))))
        (match wanted
          ((Nil) #t)
          ((Cons char rest)
           (if (char-whitespace? char) (loop rest text)
               (match text
                 ((Nil) #f)
                 ((Cons next more) (loop (if (char=? char next) rest wanted) more))))))))

    (: choices (-> Context Panel (List Choice)))
    (define (choices context panel)
      (let ((query (Panel-query panel)))
        (match (Panel-mode panel)
          ((Commands)
           (map (lambda (entry) (Choice (Entry-name entry) (Entry-keys entry)
                                        (Choose (InvokeNamed (Entry-name entry)))))
                (filter (lambda (entry) (matches? query (Entry-name entry)))
                        (Context-commands context))))
          ((Files)
           (map (lambda (path) (Choice path "" (Choose (OpenPath path))))
                (take (filter (lambda (path) (matches? query path)) (Context-paths context)) 200)))
          ((Creating (Creation directory pending _))
           (if (or pending (string=? query "")) (Nil)
               (list
                (Choice (string-append (if directory "Create directory: " "Create file: ") query)
                        "Enter" (Create)))))
          ((Searching (Search _ (Finished (Ok results)))) (search-choices results))
          ((Searching _) (Nil)))))

    (: location (-> String I64 I64 String))
    (define (location path line column)
      (string-append path ":" (show line) ":" (show column)))

    (: search-choices (-> search-Results (List Choice)))
    (define (search-choices results)
      (match results
        ((search-SavedResults results)
         (map (lambda (hit)
                (let ((point (Hit-point hit)))
                  (Choice (location (Point-file point) (Point-line point) (Point-column point))
                          (Hit-snippet hit) (Choose (OpenSavedHit hit)))))
              (SearchResults-hits results)))
        ((search-DraftResults draft hits _)
         (map (lambda (hit)
                (Choice
                 (location (search-Draft-path draft) (Occurrence-line hit) (Occurrence-column hit))
                 (Occurrence-snippet hit) (Choose (SelectDraftHit draft hit)))) hits))))

    ;; ---- View ----

    (: view (-> State Context (List (Html Message))))
    (define (view state context)
      (match (State-panel state)
        ((None) (Nil))
        ((Some panel)
         (let* ((choices (choices context panel))
                (selected (min (Panel-selected panel) (- (length choices) 1))))
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
                                                              (State-generation state))
                                               (Element "p" (list (Attr "id" "palette-help")
                                                                  (Attr "class" "palette-help"))
                                                        (list
                                                         (Text (panel-help panel)))))))))))))

    (: panel-title (-> Panel String))
    (define (panel-title panel)
      (match (Panel-mode panel)
        ((Commands) "Run a command…")
        ((Files) "Go to file…")
        ((Searching (Search source _))
         (match source
           ((search-SavedProject) "Search saved text…")
           ((search-CurrentDraft _) "Search current file…")))
        ((Creating (Creation directory _ _))
         (if directory "New directory path…" "New file path…"))))

    (: panel-input (-> Panel I64 (Html Message)))
    (define (panel-input panel selected)
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
                     (StringProperty "value" (Panel-query panel))
                     (On "input" (list (Value)) (Allow)
                         (lambda (event) (Query (Event-value event))))
                     (On "keydown" (list (Key)) (Chords panel-chords)
                         (lambda (event) (KeyPressed (Event-key event) (Event-modifiers event)))))
               (Nil)))

    (: panel-results (-> Panel (List Choice) I64 I64 (Html Message)))
    (define (panel-results panel choices selected generation)
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

    (: panel-empty (-> Panel String))
    (define (panel-empty panel)
      (match (Panel-mode panel)
        ((Searching (Search _ phase))
         (if (string=? (Panel-query panel) "") "Type text to search"
             (match phase
               ((Finished (Err failure)) (Failure-message failure))
               ((Finished (Ok _)) "No matches")
               (_ "Searching…"))))
        ((Creating (Creation _ pending _))
         (if pending "Creating…" "Enter a path relative to the project"))
        (_ "No matches")))

    (: panel-help (-> Panel String))
    (define (panel-help panel)
      (match (Panel-mode panel)
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

    (: panel-option (-> Choice I64 Bool I64 (Html Message)))
    (define (panel-option choice index selected generation)
      (Element "button"
               (list (Attr "id" (string-append "command-result-" (show index)))
                     (Attr "class" (if selected "palette-option selected" "palette-option"))
                     (Attr "role" "option") (Attr "aria-selected" (if selected "true" "false"))
                     (Attr "tabindex" "-1")
                     (Attr "data-command"
                           (match (Choice-action choice) ((Choose (InvokeNamed name)) name) (_ "")))
                     (On "mousedown" (Nil) (Always) (lambda (event) (Idle)))
                     (On "click"
                         (Nil)
                         (Allow)
                         (lambda (event) (Pick generation (Choice-action choice)))))
               (list
                (Element "span"
                         (list (Attr "class" "choice-label"))
                         (list (Text (Choice-label choice))))
                (Element "span"
                         (list (Attr "class" "command-keys"))
                         (list (Text (Choice-detail choice)))))))

    (: search-summary (-> search-Results String))
    (define (search-summary results)
      (match results
        ((search-SavedResults results)
         (string-append (limit-notice (SearchResults-limited results))
                        (if (> (SearchResults-skipped results) 0)
                            (string-append " · "
                                           (show (SearchResults-skipped results))
                                           " files skipped")
                            "")))
        ((search-DraftResults _ _ limited) (limit-notice limited))))

    (: limit-notice (-> Bool String))
    (define (limit-notice limited)
      (if limited " · Results limited; narrow your query" ""))

    (: panel-chords (List Chord))
    (define panel-chords
      (Cons (Chord "Tab" shift-key)
            (map (lambda (key) (Chord key 0)) (list "ArrowUp" "ArrowDown" "Enter" "Escape" "Tab"))))
    ))
