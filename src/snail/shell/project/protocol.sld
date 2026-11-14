;; The project service and its browser clients share these values and JSON
;; codecs. Decoding either constructs the complete value or refuses the reply;
;; a missing field never becomes an empty project or a stopped process.
(define-library (snail shell project protocol)
  (export
   Project
   Snapshot
   Point
   Report
   Build
   Attempt
   Run
   ServerState
   SearchResults
   Hit
   project->json
   json->project
   file->json
   json->file
   point->json
   json->point
   report->json
   json->report
   build->json
   json->build
   attempt->json
   json->attempt
   run->json
   json->run
   state->json
   json->state
   search->json
   json->search
   event-kind
   state->event
   read-event
   message->json
   json->message
   Run-wanted-set
   Run-available-set)
  (import
   (snail core base)
   (snail shell json)
   (snail shell json read))
  (begin

    ;; ---- Values ----

    (record Project
      ((name String)
       (directory String)
       (files (List String))
       (directories (List String))))

    (record Snapshot
      ((text String)
       (revision String)))

    (record Point
      ((file String)
       (line I64)
       (column I64)))

    (record Report
      ((severity String)
       (message String)
       (source (Option Point))))

    (record Build
      ((phase String)
       (id I64)
       (diagnostics (List Report))))

    (record Attempt
      ((build I64)
       (pid (Option I64))
       (phase String)
       (code (Option I64))
       (signal String)
       (error String)
       (stdout String)
       (stderr String)))

    (record Run
      ((target String)
       (desired (Option I64))
       (attempt (Option Attempt))
       (wanted Bool)
       (available Bool)))

    (record ServerState
      ((instance String)
       (files I64)
       (build Build)
       (runs (List Run))
       (editor String)
       (editor-problem String)))

    ;; Search coordinates belong to one saved revision, never to a draft.
    (record Hit
      ((point Point)
       (revision String)
       (snippet String)))

    (record SearchResults
      ((hits (List Hit))
       (skipped I64)
       (limited Bool)))

    ;; ---- Reading fields ----

    ;; Name a sequence of successful parses without nesting the record below it.
    (define-syntax reading
      (syntax-rules ()
        ((_ () value) (Some value))
        ((_ ((name expression) rest ...) value)
         (match expression
           ((Some name) (reading (rest ...) value))
           ((None) (None))))))

    (define (field (json Json) (name String) (read (Fn Json → (Option T))))
      (→ (Option T))
      (∀ (T))
      (match (json-member json name)
        ((Some value) (read value))
        ((None) (None))))

    (define (optional (read (Fn Json → (Option T))) (json Json))
      (→ (Option (Option T)))
      (∀ (T))
      (match json
        ((JsonNull) (Some (None)))
        (_ (reading ((value (read json))) (Some value)))))

    (define (items (read (Fn Json → (Option T))) (json Json))
      (→ (Option (List T)))
      (∀ (T))
      (match json
        ((JsonArray values) (read-items read values))
        (_ (None))))

    (define (read-items (read (Fn Json → (Option T))) (values (List Json)))
      (→ (Option (List T)))
      (∀ (T))
      (match values
        ((Nil) (Some (Nil)))
        ((Cons first rest)
         (reading ((value (read first)) (tail (read-items read rest))) (Cons value tail)))))

    (define (read-string (json Json)) (→ (Option String))
      (match json ((JsonString text) (Some text)) (_ (None))))

    (define (read-nonempty (json Json)) (→ (Option String))
      (match json ((JsonString text) (if (string=? text "") (None) (Some text))) (_ (None))))

    (define (read-integer (json Json)) (→ (Option I64))
      (match json ((JsonInteger value) (Some value)) (_ (None))))

    (define (read-natural (json Json)) (→ (Option I64))
      (match json ((JsonInteger value) (if (>= value 0) (Some value) (None))) (_ (None))))

    (define (read-positive (json Json)) (→ (Option I64))
      (match json ((JsonInteger value) (if (> value 0) (Some value) (None))) (_ (None))))

    (define (read-bool (json Json)) (→ (Option Bool))
      (match json ((JsonBool value) (Some value)) (_ (None))))

    (define (read-nullable-string (json Json)) (→ (Option String))
      (match json ((JsonNull) (Some "")) (_ (read-string json))))

    (define (nullable-string (text String)) (→ Json)
      (if (string=? text "") (JsonNull) (JsonString text)))

    (define (maybe-json (write (Fn T → Json)) (value (Option T)))
      (→ Json)
      (∀ (T))
      (match value ((Some item) (write item)) ((None) (JsonNull))))

    (define (read-build-phase (json Json)) (→ (Option String))
      (match json
        ((JsonString text)
         (if (member? text (list "starting" "building" "succeeded" "failed" "superseded" "fatal"))
             (Some text) (None)))
        (_ (None))))

    (define (read-run-phase (json Json)) (→ (Option String))
      (match json
        ((JsonString text)
         (if (member? text (list "starting" "running" "stopping" "exited" "failed"))
             (Some text) (None)))
        (_ (None))))

    (define (read-desired (json Json)) (→ (Option (Option I64)))
      (optional (lambda (value) (field value "build" read-natural)) json))

    (define (desired->json (desired (Option I64))) (→ Json)
      (maybe-json
       (lambda (build) (JsonObject (list (new Pair (first "build") (second (JsonInteger build))))))
       desired))

    ;; ---- Codecs ----

    (define (project->json (value Project)) (→ Json)
      (JsonObject
       (list
        (new Pair (first "name") (second (JsonString (● value name))))
        (new Pair (first "directory") (second (JsonString (● value directory))))
        (new Pair (first "files") (second (JsonArray (map JsonString (● value files)))))
        (new Pair
          (first "directories")
          (second (JsonArray (map JsonString (● value directories))))))))

    (define (json->project (json Json)) (→ (Option Project))
      (reading ((name (field json "name" read-string))
                (directory (field json "directory" read-nonempty))
                (files (field json "files" (lambda (json) (items read-string json))))
                (directories (field json "directories" (lambda (json) (items read-string json)))))
               (new Project
                 (name name)
                 (directory directory)
                 (files files)
                 (directories directories))))

    (define (file->json (value Snapshot)) (→ Json)
      (JsonObject
       (list
        (new Pair (first "text") (second (JsonString (● value text))))
        (new Pair (first "revision") (second (JsonString (● value revision)))))))

    (define (json->file (json Json)) (→ (Option Snapshot))
      (reading ((text (field json "text" read-string))
                (revision (field json "revision" read-nonempty)))
               (new Snapshot (text text) (revision revision))))

    (define (point->json (value Point)) (→ Json)
      (JsonObject
       (list
        (new Pair (first "file") (second (JsonString (● value file))))
        (new Pair (first "line") (second (JsonInteger (● value line))))
        (new Pair (first "column") (second (JsonInteger (● value column)))))))

    (define (json->point (json Json)) (→ (Option Point))
      (reading ((file (field json "file" read-nonempty))
                (line (field json "line" read-positive))
                (column (field json "column" read-positive)))
               (new Point (file file) (line line) (column column))))

    (define (report->json (value Report)) (→ Json)
      (JsonObject
       (list
        (new Pair (first "severity") (second (JsonString (● value severity))))
        (new Pair (first "message") (second (JsonString (● value message))))
        (new Pair (first "source") (second (maybe-json point->json (● value source)))))))

    (define (json->report (json Json)) (→ (Option Report))
      (reading ((severity (field json "severity" read-string))
                (message (field json "message" read-string))
                (source (field json "source" (lambda (json) (optional json->point json)))))
               (new Report (severity severity) (message message) (source source))))

    (define (build->json (value Build)) (→ Json)
      (JsonObject
       (list
        (new Pair (first "phase") (second (JsonString (● value phase))))
        (new Pair (first "id") (second (JsonInteger (● value id))))
        (new Pair
          (first "diagnostics")
          (second (JsonArray (map report->json (● value diagnostics))))))))

    (define (json->build (json Json)) (→ (Option Build))
      (reading ((phase (field json "phase" read-build-phase))
                (id (field json "id" read-natural))
                (diagnostics (field json "diagnostics" (lambda (json) (items json->report json)))))
               (new Build (phase phase) (id id) (diagnostics diagnostics))))

    (define (attempt->json (value Attempt)) (→ Json)
      (JsonObject
       (list
        (new Pair (first "build") (second (JsonInteger (● value build))))
        (new Pair (first "pid") (second (maybe-json JsonInteger (● value pid))))
        (new Pair (first "phase") (second (JsonString (● value phase))))
        (new Pair (first "code") (second (maybe-json JsonInteger (● value code))))
        (new Pair (first "signal") (second (nullable-string (● value signal))))
        (new Pair (first "error") (second (nullable-string (● value error))))
        (new Pair (first "stdout") (second (JsonString (● value stdout))))
        (new Pair (first "stderr") (second (JsonString (● value stderr)))))))

    (define (json->attempt (json Json)) (→ (Option Attempt))
      (reading ((build (field json "build" read-natural))
                (pid (field json "pid" (lambda (json) (optional read-natural json))))
                (phase (field json "phase" read-run-phase))
                (code (field json "code" (lambda (json) (optional read-integer json))))
                (signal (field json "signal" read-nullable-string))
                (error (field json "error" read-nullable-string))
                (stdout (field json "stdout" read-string))
                (stderr (field json "stderr" read-string)))
               (new Attempt
                 (build build)
                 (pid pid)
                 (phase phase)
                 (code code)
                 (signal signal)
                 (error error)
                 (stdout stdout)
                 (stderr stderr))))

    (define (run->json (value Run)) (→ Json)
      (JsonObject
       (list
        (new Pair (first "target") (second (JsonString (● value target))))
        (new Pair (first "desired") (second (desired->json (● value desired))))
        (new Pair (first "attempt") (second (maybe-json attempt->json (● value attempt))))
        (new Pair (first "wanted") (second (JsonBool (● value wanted))))
        (new Pair (first "available") (second (JsonBool (● value available)))))))

    (define (json->run (json Json)) (→ (Option Run))
      (reading ((target (field json "target" read-nonempty))
                (desired (field json "desired" read-desired))
                (attempt (field json "attempt" (lambda (json) (optional json->attempt json))))
                (wanted (field json "wanted" read-bool))
                (available (field json "available" read-bool)))
               (new Run
                 (target target)
                 (desired desired)
                 (attempt attempt)
                 (wanted wanted)
                 (available available))))

    (define (state->json (value ServerState)) (→ Json)
      (JsonObject
       (list
        (new Pair (first "instance") (second (JsonString (● value instance))))
        (new Pair (first "files") (second (JsonInteger (● value files))))
        (new Pair (first "build") (second (build->json (● value build))))
        (new Pair (first "runs") (second (JsonArray (map run->json (● value runs)))))
        (new Pair (first "editor") (second (JsonString (● value editor))))
        (new Pair (first "editor-problem") (second (JsonString (● value editor-problem)))))))

    (define (json->state (json Json)) (→ (Option ServerState))
      (reading ((instance (field json "instance" read-nonempty))
                (files (field json "files" read-natural))
                (build (field json "build" json->build))
                (runs (field json "runs" (lambda (json) (items json->run json))))
                (editor (field json "editor" read-nonempty))
                (editor-problem (field json "editor-problem" read-string)))
               (new ServerState
                 (instance instance)
                 (files files)
                 (build build)
                 (runs runs)
                 (editor editor)
                 (editor-problem editor-problem))))

    (define (search->json (value SearchResults)) (→ Json)
      (JsonObject
       (list
        (new Pair (first "hits") (second (JsonArray (map hit->json (● value hits)))))
        (new Pair (first "skipped") (second (JsonInteger (● value skipped))))
        (new Pair (first "limited") (second (JsonBool (● value limited)))))))

    (define (json->search (json Json)) (→ (Option SearchResults))
      (reading ((hits (field json "hits" (lambda (json) (items json->hit json))))
                (skipped (field json "skipped" read-natural))
                (limited (field json "limited" read-bool)))
               (new SearchResults (hits hits) (skipped skipped) (limited limited))))

    (define (hit->json (hit Hit)) (→ Json)
      (JsonObject (list (new Pair (first "path") (second (JsonString (● (● hit point) file))))
                        (new Pair (first "line") (second (JsonInteger (● (● hit point) line))))
                        (new Pair (first "column") (second (JsonInteger (● (● hit point) column))))
                        (new Pair (first "revision") (second (JsonString (● hit revision))))
                        (new Pair (first "snippet") (second (JsonString (● hit snippet)))))))

    (define (json->hit (json Json)) (→ (Option Hit))
      (reading ((path (field json "path" read-nonempty))
                (line (field json "line" read-positive))
                (column (field json "column" read-positive))
                (revision (field json "revision" read-nonempty))
                (snippet (field json "snippet" read-string)))
               (new Hit
                 (point (new Point (file path) (line line) (column column)))
                 (revision revision)
                 (snippet snippet))))

    (define (message->json (message String)) (→ Json)
      (JsonObject (list (new Pair (first "message") (second (JsonString message))))))

    (define (json->message (json Json)) (→ (Option String))
      (field json "message" read-string))

    ;; ---- Events ----

    ;; One ordered stream, one complete snapshot on connect and on change.
    ;; The instance distinguishes server lifetimes. Files is an invalidation
    ;; counter: clients list paths on change, not after every process-output byte.
    ;; No replay cursor is needed: reconnection starts from current state.

    (define (event-kind) (→ String) "snapshot")

    (define (state->event (state ServerState)) (→ String)
      (string-append "event: " (event-kind) "\ndata: " (json->string (state->json state)) "\n\n"))

    (define (read-event (text String)) (→ (Option ServerState))
      (match (string->json text)
        ((Some json) (json->state json))
        ((None) (None))))))
