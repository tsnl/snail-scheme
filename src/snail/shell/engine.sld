;; The engine: links a program compiled one library at a time from its
;; modules.json and runs it. A host starts one module, an entry program
;; built on this library, with the manifest, and does only what a host
;; must: the Wasm primitives of (snail shell wasm), its device services,
;; and the loop that turns the scheduler. The entry chooses where objects
;; come from by handling `linked-content-store`: the native engine
;; (bootstrap/engine.sld), which Node (host/native/run-snail.mjs) and
;; wasmtime (crates/snail) start with the manifest's path in
;; SNAIL_MANIFEST, reads files. The engine reads each object the manifest
;; names through the store, links the runtime and then each library
;; against the providers it chooses, the rules host/browser/load.mjs still
;; keeps for the page, runs each main in program order, and serves the
;; files the program links. A read through the store may wait, so linking
;; and each read of a file are tasks of the engine's own scheduler, which
;; the host turns, through the engine's exports, together with the
;; program's.
(define-library (snail shell engine)
  (export
   linked-content-store
   read-object
   run-manifest
   program-status
   engine-turn
   engine-wake
   engine-close-tasks
   engine-running
   engine-live
   resource-read
   resource-finish
   resource-byte
   close-program)
  (import
   (snail core base)
   (only (snail core forms) host)
   (snail shell json)
   (snail shell json read)
   (snail shell task)
   (snail shell wasm))
  (begin

    ;; ---- The manifest ----

    ;; An object as the manifest names it: the digest that names it in the
    ;; store, and its size.
    (struct Object
      ((digest String)
       (size I64)))

    ;; The manifest, with the directory it was read from: the store its
    ;; objects are in, relative to it, the runtime, each library's module
    ;; by name in program order, and the files the program links.
    (struct Manifest
      ((directory String)
       (store String)
       (runtime Object)
       (modules (List (Pair String Object)))
       (files (List Object))))

    ;; The manifest at `path`, whose text the entry read.
    (: parse-manifest (-> String String Manifest))
    (define (parse-manifest path text)
      (match (manifest-of (directory-of path) (string->json text))
        ((Some manifest) manifest)
        ((None) (panic (string-append path " is not the modules.json of a program")))))

    (: manifest-of (-> String (Option Json) (Option Manifest)))
    (define (manifest-of directory json)
      (match json
        ((Some json)
         (match (Pair (object-of (json-member json "runtime"))
                      (modules-of (json-array json "modules")))
           ((Pair (Some runtime) (Some modules))
            (Some (Manifest directory
                            (json-text json "store" "store/")
                            runtime
                            modules
                            (objects-of (json-array json "files")))))
           (_ (None))))
        ((None) (None))))

    (: modules-of (-> (List Json) (Option (List (Pair String Object)))))
    (define (modules-of entries)
      (fold-right (lambda (entry rest)
                    (match (Pair rest (Pair (json-member entry "name") (object-of (Some entry))))
                      ((Pair (Some rest) (Pair (Some (JsonString name)) (Some object)))
                       (Some (Cons (Pair name object) rest)))
                      (_ (None))))
                  (Some (Nil))
                  entries))

    ;; The objects among `entries`, each with a digest.
    (: objects-of (-> (List Json) (List Object)))
    (define (objects-of entries)
      (concatenate (map (lambda (entry)
                          (match (object-of (Some entry))
                            ((Some object) (list object))
                            ((None) (Nil))))
                        entries)))

    (: object-of (-> (Option Json) (Option Object)))
    (define (object-of json)
      (match json
        ((Some entry)
         (match (json-member entry "digest")
           ((Some (JsonString digest))
            (Some (Object digest
                          (match (json-member entry "size")
                            ((Some (JsonInteger size)) size)
                            (_ 0)))))
           (_ (None))))
        ((None) (None))))

    (: json-text (-> Json String String String))
    (define (json-text json name default)
      (match (json-member json name)
        ((Some (JsonString text)) text)
        (_ default)))

    (: json-array (-> Json String (List Json)))
    (define (json-array json name)
      (match (json-member json name)
        ((Some (JsonArray items)) items)
        (_ (Nil))))

    ;; A path's directory with its final slash, or "" for a bare name.
    (: directory-of (-> String String))
    (define (directory-of path)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) "")
              ((char=? (string-ref path index) #\/) (substring path 0 (+ index 1)))
              (else (loop (- index 1))))))

    ;; Where an object lies: the store, relative to the manifest, then its
    ;; digest under sha256/.
    (: object-file (-> Manifest String String))
    (define (object-file manifest digest)
      (string-append (Manifest-directory manifest) (Manifest-store manifest) "sha256/" digest))

    ;; ---- The store ----

    ;; Where the engine reads an object: its bytes by the location
    ;; `object-file` gives, or none when the store cannot give them. Each
    ;; entry handles this once, choosing the backend: the native engine
    ;; reads a file. A read may wait by ticket, as a fetch does
    ;; ((snail shell task)'s `through-host`), so it runs in a task.
    (effect linked-content-store
      ((read-object (-> String (Option Bytes) ! tasks))))

    ;; An object the program needs; one the store cannot give is a build
    ;; the engine cannot run.
    (: object-bytes (-> Manifest String Object Bytes ! tasks linked-content-store))
    (define (object-bytes manifest name object)
      (match (read-object (object-file manifest (Object-digest object)))
        ((Some bytes) bytes)
        ((None)
         (panic (string-append "cannot read "
                               name
                               ", the object "
                               (Object-digest object)
                               " of its store")))))

    ;; ---- Linking ----

    ;; What the engine linked: the runtime, each library's instance by
    ;; name, and the scheduler, the instance of (snail shell task) when the
    ;; program links it.
    (struct Linked
      ((runtime Module)
       (libraries (List (Pair String Module)))
       (scheduler (Option Module))))

    ;; What runs: set once the program is linked, and read by every export
    ;; the host calls after.
    (: linked (Ref (Option Linked)))
    (define linked (ref (None)))

    ;; The status the last main answered.
    (: status (Ref I64))
    (define status (ref 0))

    ;; Links the program the manifest at `path` names, whose text is
    ;; `text`, and runs each main in program order, answering the last
    ;; one's result.
    (: run-manifest (-> String String I64 ! mut wasm tasks linked-content-store))
    (define (run-manifest path text)
      (let* ((manifest (parse-manifest path text))
             (runtime
              (link-object manifest "the runtime" (Manifest-runtime manifest) (None) (Nil))))
        (unless (name-instance runtime "snail.core.support")
          (panic "the host has a runtime for this program already"))
        (let ((libraries (link-libraries manifest runtime (Manifest-modules manifest) (Nil))))
          (ref-set! linked
                    (Some (Linked runtime libraries (assoc-ref libraries "snail.shell.task"))))
          (ref-set! files
                    (list->vector
                     (map (lambda (object) (object-file manifest (Object-digest object)))
                          (Manifest-files manifest))))
          (run-mains libraries (assoc-ref libraries "snail.shell.task"))
          (ref-get status))))

    ;; Each library's main in program order. The program's own, last, has
    ;; its definitions initialized and its body run as the first task of
    ;; the scheduler when the program links one, so its statements may
    ;; yield; otherwise its main runs whole, as a library's does.
    (: run-mains (-> (List (Pair String Module)) (Option Module) Unit ! mut wasm))
    (define (run-mains libraries scheduler)
      (match libraries
        ((Nil) (unit))
        ((Cons (Pair _ program) (Nil))
         (match (Pair scheduler (module-export program "main:body"))
           ((Pair (Some scheduler) (Ok body))
            (ref-set! status (call program "main:init" 0))
            (match (run-export-with scheduler "tasks:start-main" body)
              ((Ok _) (unit))
              ((Err error) (panic (load-error-message error)))))
           (_ (ref-set! status (call program "main" 0)))))
        ((Cons (Pair _ library) rest)
         (ref-set! status (call library "main" 0))
         (run-mains rest scheduler))))

    (: program-status (-> I64 ! mut))
    (define (program-status)
      (ref-get status))

    ;; Each library linked against the runtime and the libraries before it,
    ;; in program order, and named in the program's namespace, where a
    ;; module the program loads while it runs sees it.
    (: link-libraries
       (-> Manifest Module (List (Pair String Object)) (List (Pair String Module))
           (List (Pair String Module))
           ! wasm tasks linked-content-store))
    (define (link-libraries manifest runtime modules libraries)
      (match modules
        ((Nil) (reverse libraries))
        ((Cons (Pair name object) rest)
         (let ((instance (link-object manifest name object (Some runtime) libraries)))
           (unless (name-instance instance name)
             (panic
              (string-append "no library may be linked as " name ", which the host provides")))
           (link-libraries manifest runtime rest (Cons (Pair name instance) libraries))))))

    ;; An object compiled and linked, called `name` in a failure, against
    ;; the providers its imports call for.
    (: link-object
       (-> Manifest String Object (Option Module) (List (Pair String Module)) Module
           ! wasm tasks linked-content-store))
    (define (link-object manifest name object runtime libraries)
      (let ((compiled
             (match (compile-bytes (object-bytes manifest name object))
               ((Some compiled) compiled)
               ((None) (panic (string-append name " is not a WebAssembly module"))))))
        (match (link-module name
                            compiled
                            (map (lambda (import) (provider manifest runtime libraries import))
                                 (module-imports compiled)))
          ((Ok instance) instance)
          ((Err error) (panic (load-error-message error))))))

    ;; What provides an import, as host/browser/load.mjs's `moduleImports`
    ;; decides: the runtime's export for "snail.core.support", a library's
    ;; for its name, the handle of a linked file for "snail.runtime.link",
    ;; this engine's own service for "snail.runtime.resource", and the
    ;; host's function otherwise, or one that fails if called when the host
    ;; lacks it, as a library's module may import a service, such as the
    ;; screen, that this host lacks and the program never calls.
    (: provider (-> Manifest (Option Module) (List (Pair String Module)) Import Provider))
    (define (provider manifest runtime libraries import)
      (let ((from (Import-from import)) (name (Import-name import)))
        (cond ((string=? from "snail.core.support")
               (match runtime
                 ((Some runtime) (ExportOf runtime name))
                 ((None) (Unprovided))))
              ((string=? from "snail.runtime.link")
               (match (file-handle manifest name 0)
                 ((Some handle) (ConstantOf handle))
                 ((None) (Unprovided))))
              ((string=? from "snail.runtime.resource")
               (ExportOf loading-program (string-append "resource:" name)))
              (else
               (match (assoc-ref libraries from)
                 ((Some library) (ExportOf library name))
                 ((None) (HostIfProvided)))))))

    ;; A linked file's handle: its position among the manifest's files.
    (: file-handle (-> Manifest String I32 (Option I32)))
    (define (file-handle manifest digest index)
      (match (list-tail (Manifest-files manifest) (i32->i64 index))
        ((Nil) (None))
        ((Cons object _)
         (if (string=? (Object-digest object) digest)
             (Some index)
             (file-handle manifest digest (+ index 1))))))

    ;; ---- Turns ----

    ;; The engine's tasks, linking and each read of a linked file, run in
    ;; its own scheduler, the program's in the program's. The host drives
    ;; the two as one through these exports: a turn runs the program's
    ;; turn, then the engine's, whose reads may wake the program's tasks,
    ;; and answers when the next turn is due for either. Waking a ticket
    ;; readies the engine's task waiting on it, or else the program's.
    ;; Each scheduler numbers its tickets from the clock of its first turn,
    ;; and the program's comes once linking is done, so the two share a
    ;; ticket only if the engine took a thousand a millisecond while it
    ;; linked.
    (: engine-turn (-> I64 I64 ! mut wasm host))
    (define (engine-turn now)
      (let* ((program (program-turn now))
             (own (begin (ref-set! turning (InEngine)) (tasks-turn now))))
        (ref-set! turning (Idle))
        (if (ref-get woke)
            (begin (ref-set! woke #f) 0)
            (sooner program own))))

    (: program-turn (-> I64 I64 ! mut wasm))
    (define (program-turn now)
      (match (scheduler)
        ((Some scheduler)
         (ref-set! turning (InProgram))
         (call scheduler "tasks:turn" now))
        ((None) -1)))

    ;; When the next turn is due, from each scheduler's answer: 0 when a
    ;; task is ready, -1 when none is live, -2 when every live task waits
    ;; on a ticket, and otherwise the milliseconds until a sleeper wakes.
    (: sooner (-> I64 I64 I64))
    (define (sooner a b)
      (cond ((or (= a 0) (= b 0)) 0)
            ((= a -1) b)
            ((= b -1) a)
            ((= a -2) b)
            ((= b -2) a)
            (else (min a b))))

    ;; Which scheduler is turning. A trap unwinds out of the turn and
    ;; leaves it set, so `engine-running` names the task that trapped: the
    ;; program's by its id, and the engine's own by its id negated.
    (enum Turning
      (Idle)
      (InProgram)
      (InEngine))

    (: turning (Ref Turning))
    (define turning (ref (Idle)))

    ;; Whether the engine's turn woke a task of the program's, which is
    ;; then ready.
    (: woke (Ref Bool))
    (define woke (ref #f))

    (: engine-wake (-> I64 I32 ! mut wasm))
    (define (engine-wake ticket)
      (if (tasks-wake! ticket)
          1
          (match (scheduler)
            ((Some scheduler) (i64->i32 (call scheduler "tasks:wake" ticket)))
            ((None) 0))))

    (: engine-close-tasks (-> Unit ! mut wasm host))
    (define (engine-close-tasks)
      (match (scheduler)
        ((Some scheduler) (call scheduler "tasks:close" 0) (unit))
        ((None) (unit)))
      (tasks-close!))

    (: engine-running (-> I64 ! mut wasm))
    (define (engine-running)
      (match (ref-get turning)
        ((InProgram)
         (match (scheduler)
           ((Some scheduler) (call scheduler "tasks:running" 0))
           ((None) 0)))
        ((InEngine) (- 0 (tasks-running)))
        ((Idle) 0)))

    (: engine-live (-> I64 ! mut wasm))
    (define (engine-live)
      (+ (tasks-live)
         (match (scheduler)
           ((Some scheduler) (call scheduler "tasks:live" 0))
           ((None) 0))))

    (: scheduler (-> (Option Module) ! mut))
    (define (scheduler)
      (match (ref-get linked)
        ((Some linked) (Linked-scheduler linked))
        ((None) (None))))

    ;; Calls an export the program's modules are known to have; one they
    ;; lack is a build the engine cannot run.
    (: call (-> Module String I64 I64 ! wasm))
    (define (call instance name argument)
      (match (run-export instance name argument)
        ((Ok answer) answer)
        ((Err error) (panic (load-error-message error)))))

    ;; Closes the program's runtime, as the host closes its own: the
    ;; status of closing its resources.
    (: close-program (-> I32 ! mut wasm))
    (define (close-program)
      (match (ref-get linked)
        ((Some linked) (i64->i32 (call (Linked-runtime linked) "snail:io/close-all" 0)))
        ((None) 0)))

    ;; ---- Linked files ----

    ;; The `resource` effect of (snail shell resource), as a host serves
    ;; it: a task of the program's starts reading a file by handle under
    ;; its ticket, finishes the ticket for the file's length, and then
    ;; reads the bytes held until the next finish. The read is a task of
    ;; the engine's, which reads the object through the store and then
    ;; wakes the program's ticket; a file the store cannot give traps the
    ;; program's task as it finishes. `files` holds each linked file's
    ;; location, by handle.
    (: files (Ref (Vector String)))
    (define files (ref (ann (list->vector (Nil)) (Vector String))))

    (: answers (Ref (List (Pair I64 (Option Bytes)))))
    (define answers (ref (Nil)))

    (: held (Ref Bytes))
    (define held (ref #u8()))

    (: resource-read (-> I64 I32 Unit ! mut wasm linked-content-store))
    (define (resource-read ticket handle)
      (let ((file (vector-ref (ref-get files) (i32->i64 handle))))
        (dispatch-local (once (lambda ()
                                (let ((bytes (read-object file)))
                                  (when (wake-program! ticket)
                                    (ref-set! answers
                                              (Cons (Pair ticket bytes) (ref-get answers))))))))))

    ;; Wakes a ticket of the program's, answering whether a task waited on
    ;; it: one that trapped or was closed did not, and its answer is not
    ;; kept.
    (: wake-program! (-> I64 Bool ! mut wasm))
    (define (wake-program! ticket)
      (match (scheduler)
        ((Some scheduler)
         (let ((woken (not (= (call scheduler "tasks:wake" ticket) 0))))
           (when woken
             (ref-set! woke #t))
           woken))
        ((None) #f)))

    (: resource-finish (-> I64 I32 ! mut))
    (define (resource-finish ticket)
      (let ((answer (assoc-ref (ref-get answers) ticket)))
        (ref-set! answers
                  (filter (lambda (answer) (not (= (Pair-first answer) ticket))) (ref-get answers)))
        (match answer
          ((Some (Some bytes))
           (ref-set! held bytes)
           (i64->i32 (vector-length bytes)))
          ((Some (None)) (panic "cannot read a linked file: the store does not have it"))
          ((None) (panic "a ticket was finished before its read completed")))))

    (: resource-byte (-> I32 I32 ! mut))
    (define (resource-byte index)
      (u8->i32 (vector-ref (ref-get held) (i32->i64 index))))))
