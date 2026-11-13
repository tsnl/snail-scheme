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

    (struct Project
      ((name String)
       (directory String)
       (files (List String))
       (directories (List String))))

    (struct Snapshot
      ((text String)
       (revision String)))

    (struct Point
      ((file String)
       (line I64)
       (column I64)))

    (struct Report
      ((severity String)
       (message String)
       (source (Option Point))))

    (struct Build
      ((phase String)
       (id I64)
       (diagnostics (List Report))))

    (struct Attempt
      ((build I64)
       (pid (Option I64))
       (phase String)
       (code (Option I64))
       (signal String)
       (error String)
       (stdout String)
       (stderr String)))

    (struct Run
      ((target String)
       (desired (Option I64))
       (attempt (Option Attempt))
       (wanted Bool)
       (available Bool)))

    (struct ServerState
      ((instance String)
       (files I64)
       (build Build)
       (runs (List Run))
       (editor String)
       (editor-problem String)))

    ;; Search coordinates belong to one saved revision, never to a draft.
    (struct Hit
      ((point Point)
       (revision String)
       (snippet String)))

    (struct SearchResults
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
      (⊨ (Copy T) (Drop (!) T))
      (match (json-member json name)
        ((Some value) (read value))
        ((None) (None))))

    (define (optional (read (Fn Json → (Option T))) (json Json))
      (→ (Option (Option T)))
      (∀ (T))
      (⊨ (Copy T) (Drop (!) T))
      (match json
        ((JsonNull) (Some (None)))
        (_ (reading ((value (read json))) (Some value)))))

    (define (items (read (Fn Json → (Option T))) (json Json))
      (→ (Option (List T)))
      (∀ (T))
      (⊨ (Copy T) (Drop (!) T))
      (match json
        ((JsonArray values) (read-items read values))
        (_ (None))))

    (define (read-items (read (Fn Json → (Option T))) (values (List Json)))
      (→ (Option (List T)))
      (∀ (T))
      (⊨ (Copy T) (Drop (!) T))
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
      (⊨ (Copy T) (Drop (!) T))
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
      (maybe-json (lambda (build) (JsonObject (list (Pair "build" (JsonInteger build))))) desired))

    ;; ---- Codecs ----

    (define (project->json (value Project)) (→ Json)
      (JsonObject
       (list
        (Pair "name" (JsonString (● value name)))
        (Pair "directory" (JsonString (● value directory)))
        (Pair "files" (JsonArray (map JsonString (● value files))))
        (Pair "directories" (JsonArray (map JsonString (● value directories)))))))

    (define (json->project (json Json)) (→ (Option Project))
      (reading ((name (field json "name" read-string))
                (directory (field json "directory" read-nonempty))
                (files (field json "files" (lambda (json) (items read-string json))))
                (directories (field json "directories" (lambda (json) (items read-string json)))))
               (Project name directory files directories)))

    (define (file->json (value Snapshot)) (→ Json)
      (JsonObject
       (list
        (Pair "text" (JsonString (● value text)))
        (Pair "revision" (JsonString (● value revision))))))

    (define (json->file (json Json)) (→ (Option Snapshot))
      (reading ((text (field json "text" read-string))
                (revision (field json "revision" read-nonempty)))
               (Snapshot text revision)))

    (define (point->json (value Point)) (→ Json)
      (JsonObject
       (list
        (Pair "file" (JsonString (● value file)))
        (Pair "line" (JsonInteger (● value line)))
        (Pair "column" (JsonInteger (● value column))))))

    (define (json->point (json Json)) (→ (Option Point))
      (reading ((file (field json "file" read-nonempty))
                (line (field json "line" read-positive))
                (column (field json "column" read-positive)))
               (Point file line column)))

    (define (report->json (value Report)) (→ Json)
      (JsonObject
       (list
        (Pair "severity" (JsonString (● value severity)))
        (Pair "message" (JsonString (● value message)))
        (Pair "source" (maybe-json point->json (● value source))))))

    (define (json->report (json Json)) (→ (Option Report))
      (reading ((severity (field json "severity" read-string))
                (message (field json "message" read-string))
                (source (field json "source" (lambda (json) (optional json->point json)))))
               (Report severity message source)))

    (define (build->json (value Build)) (→ Json)
      (JsonObject
       (list
        (Pair "phase" (JsonString (● value phase)))
        (Pair "id" (JsonInteger (● value id)))
        (Pair "diagnostics" (JsonArray (map report->json (● value diagnostics)))))))

    (define (json->build (json Json)) (→ (Option Build))
      (reading ((phase (field json "phase" read-build-phase))
                (id (field json "id" read-natural))
                (diagnostics (field json "diagnostics" (lambda (json) (items json->report json)))))
               (Build phase id diagnostics)))

    (define (attempt->json (value Attempt)) (→ Json)
      (JsonObject
       (list
        (Pair "build" (JsonInteger (● value build)))
        (Pair "pid" (maybe-json JsonInteger (● value pid)))
        (Pair "phase" (JsonString (● value phase)))
        (Pair "code" (maybe-json JsonInteger (● value code)))
        (Pair "signal" (nullable-string (● value signal)))
        (Pair "error" (nullable-string (● value error)))
        (Pair "stdout" (JsonString (● value stdout)))
        (Pair "stderr" (JsonString (● value stderr))))))

    (define (json->attempt (json Json)) (→ (Option Attempt))
      (reading ((build (field json "build" read-natural))
                (pid (field json "pid" (lambda (json) (optional read-natural json))))
                (phase (field json "phase" read-run-phase))
                (code (field json "code" (lambda (json) (optional read-integer json))))
                (signal (field json "signal" read-nullable-string))
                (error (field json "error" read-nullable-string))
                (stdout (field json "stdout" read-string))
                (stderr (field json "stderr" read-string)))
               (Attempt build pid phase code signal error stdout stderr)))

    (define (run->json (value Run)) (→ Json)
      (JsonObject
       (list
        (Pair "target" (JsonString (● value target)))
        (Pair "desired" (desired->json (● value desired)))
        (Pair "attempt" (maybe-json attempt->json (● value attempt)))
        (Pair "wanted" (JsonBool (● value wanted)))
        (Pair "available" (JsonBool (● value available))))))

    (define (json->run (json Json)) (→ (Option Run))
      (reading ((target (field json "target" read-nonempty))
                (desired (field json "desired" read-desired))
                (attempt (field json "attempt" (lambda (json) (optional json->attempt json))))
                (wanted (field json "wanted" read-bool))
                (available (field json "available" read-bool)))
               (Run target desired attempt wanted available)))

    (define (state->json (value ServerState)) (→ Json)
      (JsonObject
       (list
        (Pair "instance" (JsonString (● value instance)))
        (Pair "files" (JsonInteger (● value files)))
        (Pair "build" (build->json (● value build)))
        (Pair "runs" (JsonArray (map run->json (● value runs))))
        (Pair "editor" (JsonString (● value editor)))
        (Pair "editor-problem" (JsonString (● value editor-problem))))))

    (define (json->state (json Json)) (→ (Option ServerState))
      (reading ((instance (field json "instance" read-nonempty))
                (files (field json "files" read-natural))
                (build (field json "build" json->build))
                (runs (field json "runs" (lambda (json) (items json->run json))))
                (editor (field json "editor" read-nonempty))
                (editor-problem (field json "editor-problem" read-string)))
               (ServerState instance files build runs editor editor-problem)))

    (define (search->json (value SearchResults)) (→ Json)
      (JsonObject
       (list
        (Pair "hits" (JsonArray (map hit->json (● value hits))))
        (Pair "skipped" (JsonInteger (● value skipped)))
        (Pair "limited" (JsonBool (● value limited))))))

    (define (json->search (json Json)) (→ (Option SearchResults))
      (reading ((hits (field json "hits" (lambda (json) (items json->hit json))))
                (skipped (field json "skipped" read-natural))
                (limited (field json "limited" read-bool)))
               (SearchResults hits skipped limited)))

    (define (hit->json (hit Hit)) (→ Json)
      (JsonObject (list (Pair "path" (JsonString (● (● hit point) file)))
                        (Pair "line" (JsonInteger (● (● hit point) line)))
                        (Pair "column" (JsonInteger (● (● hit point) column)))
                        (Pair "revision" (JsonString (● hit revision)))
                        (Pair "snippet" (JsonString (● hit snippet))))))

    (define (json->hit (json Json)) (→ (Option Hit))
      (reading ((path (field json "path" read-nonempty))
                (line (field json "line" read-positive))
                (column (field json "column" read-positive))
                (revision (field json "revision" read-nonempty))
                (snippet (field json "snippet" read-string)))
               (Hit (Point path line column) revision snippet)))

    (define (message->json (message String)) (→ Json)
      (JsonObject (list (Pair "message" (JsonString message)))))

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
