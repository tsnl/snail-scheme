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

    (: field
       (All (T)
            (requires (Copy T))
            (impl (Fn Json String (dyn (Fn Json -> (Option T))) -> (Option T)))))
    (define (field json name read)
      (match (json-member json name)
        ((Some value) (read value))
        ((None) (None))))

    (: optional
       (All (T)
            (requires (Copy T))
            (impl (Fn (dyn (Fn Json -> (Option T))) Json -> (Option (Option T))))))
    (define (optional read json)
      (match json
        ((JsonNull) (Some (None)))
        (_ (reading ((value (read json))) (Some value)))))

    (: items
       (All (T)
            (requires (Copy T))
            (impl (Fn (dyn (Fn Json -> (Option T))) Json -> (Option (List T))))))
    (define (items read json)
      (match json
        ((JsonArray values) (read-items read values))
        (_ (None))))

    (: read-items
       (All (T)
            (requires (Copy T))
            (impl (Fn (dyn (Fn Json -> (Option T))) (List Json) -> (Option (List T))))))
    (define (read-items read values)
      (match values
        ((Nil) (Some (Nil)))
        ((Cons first rest)
         (reading ((value (read first)) (tail (read-items read rest))) (Cons value tail)))))

    (: read-string (impl (Fn Json -> (Option String))))
    (define (read-string json)
      (match json ((JsonString text) (Some text)) (_ (None))))

    (: read-nonempty (impl (Fn Json -> (Option String))))
    (define (read-nonempty json)
      (match json ((JsonString text) (if (string=? text "") (None) (Some text))) (_ (None))))

    (: read-integer (impl (Fn Json -> (Option I64))))
    (define (read-integer json)
      (match json ((JsonInteger value) (Some value)) (_ (None))))

    (: read-natural (impl (Fn Json -> (Option I64))))
    (define (read-natural json)
      (match json ((JsonInteger value) (if (>= value 0) (Some value) (None))) (_ (None))))

    (: read-positive (impl (Fn Json -> (Option I64))))
    (define (read-positive json)
      (match json ((JsonInteger value) (if (> value 0) (Some value) (None))) (_ (None))))

    (: read-bool (impl (Fn Json -> (Option Bool))))
    (define (read-bool json)
      (match json ((JsonBool value) (Some value)) (_ (None))))

    (: read-nullable-string (impl (Fn Json -> (Option String))))
    (define (read-nullable-string json)
      (match json ((JsonNull) (Some "")) (_ (read-string json))))

    (: nullable-string (impl (Fn String -> Json)))
    (define (nullable-string text)
      (if (string=? text "") (JsonNull) (JsonString text)))

    (: maybe-json (All (T) (requires (Copy T)) (impl (Fn (dyn (Fn T -> Json)) (Option T) -> Json))))
    (define (maybe-json write value)
      (match value ((Some item) (write item)) ((None) (JsonNull))))

    (: read-build-phase (impl (Fn Json -> (Option String))))
    (define (read-build-phase json)
      (match json
        ((JsonString text)
         (if (member? text (list "starting" "building" "succeeded" "failed" "superseded" "fatal"))
             (Some text) (None)))
        (_ (None))))

    (: read-run-phase (impl (Fn Json -> (Option String))))
    (define (read-run-phase json)
      (match json
        ((JsonString text)
         (if (member? text (list "starting" "running" "stopping" "exited" "failed"))
             (Some text) (None)))
        (_ (None))))

    (: read-desired (impl (Fn Json -> (Option (Option I64)))))
    (define (read-desired json)
      (optional (lambda (value) (field value "build" read-natural)) json))

    (: desired->json (impl (Fn (Option I64) -> Json)))
    (define (desired->json desired)
      (maybe-json (lambda (build) (JsonObject (list (Pair "build" (JsonInteger build))))) desired))

    ;; ---- Codecs ----

    (: project->json (impl (Fn Project -> Json)))
    (define (project->json value)
      (JsonObject
       (list
        (Pair "name" (JsonString (::name value)))
        (Pair "directory" (JsonString (::directory value)))
        (Pair "files" (JsonArray (map JsonString (::files value))))
        (Pair "directories" (JsonArray (map JsonString (::directories value)))))))

    (: json->project (impl (Fn Json -> (Option Project))))
    (define (json->project json)
      (reading ((name (field json "name" read-string))
                (directory (field json "directory" read-nonempty))
                (files (field json "files" (lambda (json) (items read-string json))))
                (directories (field json "directories" (lambda (json) (items read-string json)))))
               (Project name directory files directories)))

    (: file->json (impl (Fn Snapshot -> Json)))
    (define (file->json value)
      (JsonObject
       (list
        (Pair "text" (JsonString (::text value)))
        (Pair "revision" (JsonString (::revision value))))))

    (: json->file (impl (Fn Json -> (Option Snapshot))))
    (define (json->file json)
      (reading ((text (field json "text" read-string))
                (revision (field json "revision" read-nonempty)))
               (Snapshot text revision)))

    (: point->json (impl (Fn Point -> Json)))
    (define (point->json value)
      (JsonObject
       (list
        (Pair "file" (JsonString (::file value)))
        (Pair "line" (JsonInteger (::line value)))
        (Pair "column" (JsonInteger (::column value))))))

    (: json->point (impl (Fn Json -> (Option Point))))
    (define (json->point json)
      (reading ((file (field json "file" read-nonempty))
                (line (field json "line" read-positive))
                (column (field json "column" read-positive)))
               (Point file line column)))

    (: report->json (impl (Fn Report -> Json)))
    (define (report->json value)
      (JsonObject
       (list
        (Pair "severity" (JsonString (::severity value)))
        (Pair "message" (JsonString (::message value)))
        (Pair "source" (maybe-json point->json (::source value))))))

    (: json->report (impl (Fn Json -> (Option Report))))
    (define (json->report json)
      (reading ((severity (field json "severity" read-string))
                (message (field json "message" read-string))
                (source (field json "source" (lambda (json) (optional json->point json)))))
               (Report severity message source)))

    (: build->json (impl (Fn Build -> Json)))
    (define (build->json value)
      (JsonObject
       (list
        (Pair "phase" (JsonString (::phase value)))
        (Pair "id" (JsonInteger (::id value)))
        (Pair "diagnostics" (JsonArray (map report->json (::diagnostics value)))))))

    (: json->build (impl (Fn Json -> (Option Build))))
    (define (json->build json)
      (reading ((phase (field json "phase" read-build-phase))
                (id (field json "id" read-natural))
                (diagnostics (field json "diagnostics" (lambda (json) (items json->report json)))))
               (Build phase id diagnostics)))

    (: attempt->json (impl (Fn Attempt -> Json)))
    (define (attempt->json value)
      (JsonObject
       (list
        (Pair "build" (JsonInteger (::build value)))
        (Pair "pid" (maybe-json JsonInteger (::pid value)))
        (Pair "phase" (JsonString (::phase value)))
        (Pair "code" (maybe-json JsonInteger (::code value)))
        (Pair "signal" (nullable-string (::signal value)))
        (Pair "error" (nullable-string (::error value)))
        (Pair "stdout" (JsonString (::stdout value)))
        (Pair "stderr" (JsonString (::stderr value))))))

    (: json->attempt (impl (Fn Json -> (Option Attempt))))
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

    (: run->json (impl (Fn Run -> Json)))
    (define (run->json value)
      (JsonObject
       (list
        (Pair "target" (JsonString (::target value)))
        (Pair "desired" (desired->json (::desired value)))
        (Pair "attempt" (maybe-json attempt->json (::attempt value)))
        (Pair "wanted" (JsonBool (::wanted value)))
        (Pair "available" (JsonBool (::available value))))))

    (: json->run (impl (Fn Json -> (Option Run))))
    (define (json->run json)
      (reading ((target (field json "target" read-nonempty))
                (desired (field json "desired" read-desired))
                (attempt (field json "attempt" (lambda (json) (optional json->attempt json))))
                (wanted (field json "wanted" read-bool))
                (available (field json "available" read-bool)))
               (Run target desired attempt wanted available)))

    (: state->json (impl (Fn ServerState -> Json)))
    (define (state->json value)
      (JsonObject
       (list
        (Pair "instance" (JsonString (::instance value)))
        (Pair "files" (JsonInteger (::files value)))
        (Pair "build" (build->json (::build value)))
        (Pair "runs" (JsonArray (map run->json (::runs value))))
        (Pair "editor" (JsonString (::editor value)))
        (Pair "editor-problem" (JsonString (::editor-problem value))))))

    (: json->state (impl (Fn Json -> (Option ServerState))))
    (define (json->state json)
      (reading ((instance (field json "instance" read-nonempty))
                (files (field json "files" read-natural))
                (build (field json "build" json->build))
                (runs (field json "runs" (lambda (json) (items json->run json))))
                (editor (field json "editor" read-nonempty))
                (editor-problem (field json "editor-problem" read-string)))
               (ServerState instance files build runs editor editor-problem)))

    (: search->json (impl (Fn SearchResults -> Json)))
    (define (search->json value)
      (JsonObject
       (list
        (Pair "hits" (JsonArray (map hit->json (::hits value))))
        (Pair "skipped" (JsonInteger (::skipped value)))
        (Pair "limited" (JsonBool (::limited value))))))

    (: json->search (impl (Fn Json -> (Option SearchResults))))
    (define (json->search json)
      (reading ((hits (field json "hits" (lambda (json) (items json->hit json))))
                (skipped (field json "skipped" read-natural))
                (limited (field json "limited" read-bool)))
               (SearchResults hits skipped limited)))

    (: hit->json (impl (Fn Hit -> Json)))
    (define (hit->json hit)
      (JsonObject (list (Pair "path" (JsonString (::file (::point hit))))
                        (Pair "line" (JsonInteger (::line (::point hit))))
                        (Pair "column" (JsonInteger (::column (::point hit))))
                        (Pair "revision" (JsonString (::revision hit)))
                        (Pair "snippet" (JsonString (::snippet hit))))))

    (: json->hit (impl (Fn Json -> (Option Hit))))
    (define (json->hit json)
      (reading ((path (field json "path" read-nonempty))
                (line (field json "line" read-positive))
                (column (field json "column" read-positive))
                (revision (field json "revision" read-nonempty))
                (snippet (field json "snippet" read-string)))
               (Hit (Point path line column) revision snippet)))

    (: message->json (impl (Fn String -> Json)))
    (define (message->json message)
      (JsonObject (list (Pair "message" (JsonString message)))))

    (: json->message (impl (Fn Json -> (Option String))))
    (define (json->message json)
      (field json "message" read-string))

    ;; ---- Events ----

    ;; One ordered stream, one complete snapshot on connect and on change.
    ;; The instance distinguishes server lifetimes. Files is an invalidation
    ;; counter: clients list paths on change, not after every process-output byte.
    ;; No replay cursor is needed: reconnection starts from current state.
    (: event-kind String)
    (define event-kind "snapshot")

    (: state->event (impl (Fn ServerState -> String)))
    (define (state->event state)
      (string-append "event: " event-kind "\ndata: " (json->string (state->json state)) "\n\n"))

    (: read-event (impl (Fn String -> (Option ServerState))))
    (define (read-event text)
      (match (string->json text)
        ((Some json) (json->state json))
        ((None) (None))))))
