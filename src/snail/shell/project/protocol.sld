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
   Project-name
   Project-directory
   Project-files
   Project-directories
   Snapshot-text
   Snapshot-revision
   Point-file
   Point-line
   Point-column
   Report-severity
   Report-message
   Report-source
   Build-phase
   Build-id
   Build-diagnostics
   Attempt-build
   Attempt-pid
   Attempt-phase
   Attempt-code
   Attempt-signal
   Attempt-error
   Attempt-stdout
   Attempt-stderr
   Run-target
   Run-desired
   Run-attempt
   Run-wanted
   Run-available
   ServerState-instance
   ServerState-files
   ServerState-build
   ServerState-runs
   Hit-point
   Hit-revision
   Hit-snippet
   SearchResults-hits
   SearchResults-skipped
   SearchResults-limited
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
       (runs (List Run))))

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

    (: field (All (T) (requires (Copy T)) (-> Json String (-> Json (Option T)) (Option T))))
    (define (field json name read)
      (match (json-member json name)
        ((Some value) (read value))
        ((None) (None))))

    (: optional (All (T) (requires (Copy T)) (-> (-> Json (Option T)) Json (Option (Option T)))))
    (define (optional read json)
      (match json
        ((JsonNull) (Some (None)))
        (_ (reading ((value (read json))) (Some value)))))

    (: items (All (T) (requires (Copy T)) (-> (-> Json (Option T)) Json (Option (List T)))))
    (define (items read json)
      (match json
        ((JsonArray values) (read-items read values))
        (_ (None))))

    (: read-items
       (All (T) (requires (Copy T)) (-> (-> Json (Option T)) (List Json) (Option (List T)))))
    (define (read-items read values)
      (match values
        ((Nil) (Some (Nil)))
        ((Cons first rest)
         (reading ((value (read first)) (tail (read-items read rest))) (Cons value tail)))))

    (: read-string (-> Json (Option String)))
    (define (read-string json)
      (match json ((JsonString text) (Some text)) (_ (None))))

    (: read-nonempty (-> Json (Option String)))
    (define (read-nonempty json)
      (match json ((JsonString text) (if (string=? text "") (None) (Some text))) (_ (None))))

    (: read-integer (-> Json (Option I64)))
    (define (read-integer json)
      (match json ((JsonInteger value) (Some value)) (_ (None))))

    (: read-natural (-> Json (Option I64)))
    (define (read-natural json)
      (match json ((JsonInteger value) (if (>= value 0) (Some value) (None))) (_ (None))))

    (: read-positive (-> Json (Option I64)))
    (define (read-positive json)
      (match json ((JsonInteger value) (if (> value 0) (Some value) (None))) (_ (None))))

    (: read-bool (-> Json (Option Bool)))
    (define (read-bool json)
      (match json ((JsonBool value) (Some value)) (_ (None))))

    (: read-nullable-string (-> Json (Option String)))
    (define (read-nullable-string json)
      (match json ((JsonNull) (Some "")) (_ (read-string json))))

    (: nullable-string (-> String Json))
    (define (nullable-string text)
      (if (string=? text "") (JsonNull) (JsonString text)))

    (: maybe-json (All (T) (requires (Copy T)) (-> (-> T Json) (Option T) Json)))
    (define (maybe-json write value)
      (match value ((Some item) (write item)) ((None) (JsonNull))))

    (: read-build-phase (-> Json (Option String)))
    (define (read-build-phase json)
      (match json
        ((JsonString text)
         (if (member? text (list "starting" "building" "succeeded" "failed" "superseded" "fatal"))
             (Some text) (None)))
        (_ (None))))

    (: read-run-phase (-> Json (Option String)))
    (define (read-run-phase json)
      (match json
        ((JsonString text)
         (if (member? text (list "starting" "running" "stopping" "exited" "failed"))
             (Some text) (None)))
        (_ (None))))

    (: read-desired (-> Json (Option (Option I64))))
    (define (read-desired json)
      (optional (lambda (value) (field value "build" read-natural)) json))

    (: desired->json (-> (Option I64) Json))
    (define (desired->json desired)
      (maybe-json (lambda (build) (JsonObject (list (Pair "build" (JsonInteger build))))) desired))

    ;; ---- Codecs ----

    (: project->json (-> Project Json))
    (define (project->json value)
      (JsonObject
       (list
        (Pair "name" (JsonString (Project-name value)))
        (Pair "directory" (JsonString (Project-directory value)))
        (Pair "files" (JsonArray (map JsonString (Project-files value))))
        (Pair "directories" (JsonArray (map JsonString (Project-directories value)))))))

    (: json->project (-> Json (Option Project)))
    (define (json->project json)
      (reading ((name (field json "name" read-string))
                (directory (field json "directory" read-nonempty))
                (files (field json "files" (lambda (json) (items read-string json))))
                (directories (field json "directories" (lambda (json) (items read-string json)))))
               (Project name directory files directories)))

    (: file->json (-> Snapshot Json))
    (define (file->json value)
      (JsonObject
       (list
        (Pair "text" (JsonString (Snapshot-text value)))
        (Pair "revision" (JsonString (Snapshot-revision value))))))

    (: json->file (-> Json (Option Snapshot)))
    (define (json->file json)
      (reading ((text (field json "text" read-string))
                (revision (field json "revision" read-nonempty)))
               (Snapshot text revision)))

    (: point->json (-> Point Json))
    (define (point->json value)
      (JsonObject
       (list
        (Pair "file" (JsonString (Point-file value)))
        (Pair "line" (JsonInteger (Point-line value)))
        (Pair "column" (JsonInteger (Point-column value))))))

    (: json->point (-> Json (Option Point)))
    (define (json->point json)
      (reading ((file (field json "file" read-nonempty))
                (line (field json "line" read-positive))
                (column (field json "column" read-positive)))
               (Point file line column)))

    (: report->json (-> Report Json))
    (define (report->json value)
      (JsonObject
       (list
        (Pair "severity" (JsonString (Report-severity value)))
        (Pair "message" (JsonString (Report-message value)))
        (Pair "source" (maybe-json point->json (Report-source value))))))

    (: json->report (-> Json (Option Report)))
    (define (json->report json)
      (reading ((severity (field json "severity" read-string))
                (message (field json "message" read-string))
                (source (field json "source" (lambda (json) (optional json->point json)))))
               (Report severity message source)))

    (: build->json (-> Build Json))
    (define (build->json value)
      (JsonObject
       (list
        (Pair "phase" (JsonString (Build-phase value)))
        (Pair "id" (JsonInteger (Build-id value)))
        (Pair "diagnostics" (JsonArray (map report->json (Build-diagnostics value)))))))

    (: json->build (-> Json (Option Build)))
    (define (json->build json)
      (reading ((phase (field json "phase" read-build-phase))
                (id (field json "id" read-natural))
                (diagnostics (field json "diagnostics" (lambda (json) (items json->report json)))))
               (Build phase id diagnostics)))

    (: attempt->json (-> Attempt Json))
    (define (attempt->json value)
      (JsonObject
       (list
        (Pair "build" (JsonInteger (Attempt-build value)))
        (Pair "pid" (maybe-json JsonInteger (Attempt-pid value)))
        (Pair "phase" (JsonString (Attempt-phase value)))
        (Pair "code" (maybe-json JsonInteger (Attempt-code value)))
        (Pair "signal" (nullable-string (Attempt-signal value)))
        (Pair "error" (nullable-string (Attempt-error value)))
        (Pair "stdout" (JsonString (Attempt-stdout value)))
        (Pair "stderr" (JsonString (Attempt-stderr value))))))

    (: json->attempt (-> Json (Option Attempt)))
    (define (json->attempt json)
      (reading ((build (field json "build" read-natural))
                (pid (field json "pid" (lambda (json) (optional read-natural json))))
                (phase (field json "phase" read-run-phase))
                (code (field json "code" (lambda (json) (optional read-integer json))))
                (signal (field json "signal" read-nullable-string))
                (error (field json "error" read-nullable-string))
                (stdout (field json "stdout" read-string))
                (stderr (field json "stderr" read-string)))
               (Attempt build pid phase code signal error stdout stderr)))

    (: run->json (-> Run Json))
    (define (run->json value)
      (JsonObject
       (list
        (Pair "target" (JsonString (Run-target value)))
        (Pair "desired" (desired->json (Run-desired value)))
        (Pair "attempt" (maybe-json attempt->json (Run-attempt value)))
        (Pair "wanted" (JsonBool (Run-wanted value)))
        (Pair "available" (JsonBool (Run-available value))))))

    (: json->run (-> Json (Option Run)))
    (define (json->run json)
      (reading ((target (field json "target" read-nonempty))
                (desired (field json "desired" read-desired))
                (attempt (field json "attempt" (lambda (json) (optional json->attempt json))))
                (wanted (field json "wanted" read-bool))
                (available (field json "available" read-bool)))
               (Run target desired attempt wanted available)))

    (: state->json (-> ServerState Json))
    (define (state->json value)
      (JsonObject
       (list
        (Pair "instance" (JsonString (ServerState-instance value)))
        (Pair "files" (JsonInteger (ServerState-files value)))
        (Pair "build" (build->json (ServerState-build value)))
        (Pair "runs" (JsonArray (map run->json (ServerState-runs value)))))))

    (: json->state (-> Json (Option ServerState)))
    (define (json->state json)
      (reading ((instance (field json "instance" read-nonempty))
                (files (field json "files" read-natural))
                (build (field json "build" json->build))
                (runs (field json "runs" (lambda (json) (items json->run json)))))
               (ServerState instance files build runs)))

    (: search->json (-> SearchResults Json))
    (define (search->json value)
      (JsonObject
       (list
        (Pair "hits" (JsonArray (map hit->json (SearchResults-hits value))))
        (Pair "skipped" (JsonInteger (SearchResults-skipped value)))
        (Pair "limited" (JsonBool (SearchResults-limited value))))))

    (: json->search (-> Json (Option SearchResults)))
    (define (json->search json)
      (reading ((hits (field json "hits" (lambda (json) (items json->hit json))))
                (skipped (field json "skipped" read-natural))
                (limited (field json "limited" read-bool)))
               (SearchResults hits skipped limited)))

    (: hit->json (-> Hit Json))
    (define (hit->json hit)
      (JsonObject (list (Pair "path" (JsonString (Point-file (Hit-point hit))))
                        (Pair "line" (JsonInteger (Point-line (Hit-point hit))))
                        (Pair "column" (JsonInteger (Point-column (Hit-point hit))))
                        (Pair "revision" (JsonString (Hit-revision hit)))
                        (Pair "snippet" (JsonString (Hit-snippet hit))))))

    (: json->hit (-> Json (Option Hit)))
    (define (json->hit json)
      (reading ((path (field json "path" read-nonempty))
                (line (field json "line" read-positive))
                (column (field json "column" read-positive))
                (revision (field json "revision" read-nonempty))
                (snippet (field json "snippet" read-string)))
               (Hit (Point path line column) revision snippet)))

    (: message->json (-> String Json))
    (define (message->json message)
      (JsonObject (list (Pair "message" (JsonString message)))))

    (: json->message (-> Json (Option String)))
    (define (json->message json)
      (field json "message" read-string))

    ;; ---- Events ----

    ;; One ordered stream, one complete snapshot on connect and on change.
    ;; The instance distinguishes server lifetimes. Files is an invalidation
    ;; counter: clients list paths on change, not after every process-output byte.
    ;; No replay cursor is needed: reconnection starts from current state.
    (: event-kind String)
    (define event-kind "snapshot")

    (: state->event (-> ServerState String))
    (define (state->event state)
      (string-append "event: " event-kind "\ndata: " (json->string (state->json state)) "\n\n"))

    (: read-event (-> String (Option ServerState)))
    (define (read-event text)
      (match (string->json text)
        ((Some json) (json->state json))
        ((None) (None))))))
