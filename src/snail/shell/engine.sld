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

    (define (parse-manifest (path String) (text String)) (→ Manifest)
      (match (manifest-of (directory-of path) (string->json text))
        ((Some manifest) manifest)
        ((None) (panic (string-append path " is not the modules.json of a program")))))

    (define (manifest-of (directory String) (json (Option Json))) (→ (Option Manifest))
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

    (define (modules-of (entries (List Json))) (→ (Option (List (Pair String Object))))
      (fold-right (lambda (entry rest)
                    (match (Pair rest (Pair (json-member entry "name") (object-of (Some entry))))
                      ((Pair (Some rest) (Pair (Some (JsonString name)) (Some object)))
                       (Some (Cons (Pair name object) rest)))
                      (_ (None))))
                  (Some (Nil))
                  entries))

    ;; The objects among `entries`, each with a digest.

    (define (objects-of (entries (List Json))) (→ (List Object))
      (concatenate (map (lambda (entry)
                          (match (object-of (Some entry))
                            ((Some object) (list object))
                            ((None) (Nil))))
                        entries)))

    (define (object-of (json (Option Json))) (→ (Option Object))
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

    (define (json-text (json Json) (name String) (default String)) (→ String)
      (match (json-member json name)
        ((Some (JsonString text)) text)
        (_ default)))

    (define (json-array (json Json) (name String)) (→ (List Json))
      (match (json-member json name)
        ((Some (JsonArray items)) items)
        (_ (Nil))))

    ;; A path's directory with its final slash, or "" for a bare name.

    (define (directory-of (path String)) (→ String)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) "")
              ((char=? (string-ref path index) #\/) (substring path 0 (+ index 1)))
              (else (loop (- index 1))))))

    ;; Where an object lies: the store, relative to the manifest, then its
    ;; digest under sha256/.

    (define (object-file (manifest Manifest) (digest String)) (→ String)
      (string-append (● manifest directory) (● manifest store) "sha256/" digest))

    ;; ---- The store ----

    ;; Where the engine reads an object: its bytes by the location
    ;; `object-file` gives, or none when the store cannot give them. Each
    ;; entry handles this once, choosing the backend: the native engine
    ;; reads a file. A read may wait by ticket, as a fetch does
    ;; ((snail shell task)'s `through-host`), so it runs in a task.
    (effect linked-content-store
      ((read-object (Fn String → (Option Bytes) ! tasks))))

    ;; An object the program needs; one the store cannot give is a build
    ;; the engine cannot run.

    (define (object-bytes (manifest Manifest) (name String) (object Object))
      (→ Bytes)
      (! tasks linked-content-store)
      (match (read-object (object-file manifest (● object digest)))
        ((Some bytes) bytes)
        ((None)
         (panic (string-append "cannot read "
                               name
                               ", the object "
                               (● object digest)
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

    

    ;; The status the last main answered.

    

    ;; Links the program the manifest at `path` names, whose text is
    ;; `text`, and runs each main in program order, answering the last
    ;; one's result.

    (define (run-manifest (path String) (text String))
      (→ I64)
      (! mut wasm tasks linked-content-store)
      (let* ((manifest (parse-manifest path text))
             (runtime
              (link-object manifest "the runtime" (● manifest runtime) (None) (Nil))))
        (unless (name-instance runtime "snail.core.support")
          (panic "the host has a runtime for this program already"))
        (let ((libraries (link-libraries manifest runtime (● manifest modules) (Nil))))
          (set! (● enginestate linked) (Some (Linked runtime libraries (assoc-ref libraries "snail.shell.task"))))
          (set! (● enginestate files) (list->vector
                     (map (lambda (object) (object-file manifest (● object digest)))
                          (● manifest files))))
          (run-mains libraries (assoc-ref libraries "snail.shell.task"))
          (● enginestate status))))

    ;; Each library's main in program order. The program's own, last, has
    ;; its definitions initialized and its body run as the first task of
    ;; the scheduler when the program links one, so its statements may
    ;; yield; otherwise its main runs whole, as a library's does.

    (define (run-mains (libraries (List (Pair String Module))) (scheduler (Option Module)))
      (→ Unit)
      (! mut wasm)
      (match libraries
        ((Nil) (unit))
        ((Cons (Pair _ program) (Nil))
         (match (Pair scheduler (module-export program "main:body"))
           ((Pair (Some scheduler) (Ok body))
            (set! (● enginestate status) (call program "main:init" 0))
            (match (run-export-with scheduler "tasks:start-main" body)
              ((Ok _) (unit))
              ((Err error) (panic (load-error-message error)))))
           (_ (set! (● enginestate status) (call program "main" 0)))))
        ((Cons (Pair _ library) rest)
         (set! (● enginestate status) (call library "main" 0))
         (run-mains rest scheduler))))

    (define (program-status) (→ I64) (! mut)
      (● enginestate status))

    ;; Each library linked against the runtime and the libraries before it,
    ;; in program order, and named in the program's namespace, where a
    ;; module the program loads while it runs sees it.

    (define (link-libraries (manifest Manifest)
                            (runtime Module)
                            (modules (List (Pair String Object)))
                            (libraries (List (Pair String Module))))
      (→ (List (Pair String Module)))
      (! wasm tasks linked-content-store)
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

    (define (link-object (manifest Manifest)
                         (name String)
                         (object Object)
                         (runtime (Option Module))
                         (libraries (List (Pair String Module))))
      (→ Module)
      (! wasm tasks linked-content-store)
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

    (define (provider (manifest Manifest)
                      (runtime (Option Module))
                      (libraries (List (Pair String Module)))
                      (import Import))
      (→ Provider)
      (let ((from (● import from)) (name (● import name)))
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

    (define (file-handle (manifest Manifest) (digest String) (index I32)) (→ (Option I32))
      (match (list-tail (● manifest files) (i32->i64 index))
        ((Nil) (None))
        ((Cons object _)
         (if (string=? (● object digest) digest)
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

    (define (engine-turn (now I64)) (→ I64) (! mut wasm host)
      (let* ((program (program-turn now))
             (own (begin (set! (● enginestate turning) (InEngine)) (tasks-turn now))))
        (set! (● enginestate turning) (Idle))
        (if (● enginestate woke)
            (begin (set! (● enginestate woke) #f) 0)
            (sooner program own))))

    (define (program-turn (now I64)) (→ I64) (! mut wasm)
      (match (scheduler)
        ((Some scheduler)
         (set! (● enginestate turning) (InProgram))
         (call scheduler "tasks:turn" now))
        ((None) -1)))

    ;; When the next turn is due, from each scheduler's answer: 0 when a
    ;; task is ready, -1 when none is live, -2 when every live task waits
    ;; on a ticket, and otherwise the milliseconds until a sleeper wakes.

    (define (sooner (a I64) (b I64)) (→ I64)
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

    

    ;; Whether the engine's turn woke a task of the program's, which is
    ;; then ready.

    

    (define (engine-wake (ticket I64)) (→ I32) (! mut wasm)
      (if (tasks-wake! ticket)
          1
          (match (scheduler)
            ((Some scheduler) (i64->i32 (call scheduler "tasks:wake" ticket)))
            ((None) 0))))

    (define (engine-close-tasks) (→ Unit) (! mut wasm host)
      (match (scheduler)
        ((Some scheduler) (call scheduler "tasks:close" 0) (unit))
        ((None) (unit)))
      (tasks-close!))

    (define (engine-running) (→ I64) (! mut wasm)
      (match (● enginestate turning)
        ((InProgram)
         (match (scheduler)
           ((Some scheduler) (call scheduler "tasks:running" 0))
           ((None) 0)))
        ((InEngine) (- 0 (tasks-running)))
        ((Idle) 0)))

    (define (engine-live) (→ I64) (! mut wasm)
      (+ (tasks-live)
         (match (scheduler)
           ((Some scheduler) (call scheduler "tasks:live" 0))
           ((None) 0))))

    (define (scheduler) (→ (Option Module)) (! mut)
      (match (● enginestate linked)
        ((Some linked) (● linked scheduler))
        ((None) (None))))

    ;; Calls an export the program's modules are known to have; one they
    ;; lack is a build the engine cannot run.

    (define (call (instance Module) (name String) (argument I64)) (→ I64) (! wasm)
      (match (run-export instance name argument)
        ((Ok answer) answer)
        ((Err error) (panic (load-error-message error)))))

    ;; Closes the program's runtime, as the host closes its own: the
    ;; status of closing its resources.

    (define (close-program) (→ I32) (! mut wasm)
      (match (● enginestate linked)
        ((Some linked) (i64->i32 (call (● linked runtime) "snail:io/close-all" 0)))
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

    

    

    

    (define (resource-read (ticket I64) (handle I32)) (→ Unit) (! mut wasm linked-content-store)
      (let ((file (vector-ref (● enginestate files) (i32->i64 handle))))
        (dispatch-local (once (lambda ()
                                (let ((bytes (read-object file)))
                                  (when (wake-program! ticket)
                                    (set! (● enginestate answers) (Cons (Pair ticket bytes) (● enginestate answers))))))))))

    ;; Wakes a ticket of the program's, answering whether a task waited on
    ;; it: one that trapped or was closed did not, and its answer is not
    ;; kept.

    (define (wake-program! (ticket I64)) (→ Bool) (! mut wasm)
      (match (scheduler)
        ((Some scheduler)
         (let ((woken (not (= (call scheduler "tasks:wake" ticket) 0))))
           (when woken
             (set! (● enginestate woke) #t))
           woken))
        ((None) #f)))

    (define (resource-finish (ticket I64)) (→ I32) (! mut)
      (let ((answer (assoc-ref (● enginestate answers) ticket)))
        (set! (● enginestate answers) (filter (lambda (answer) (not (= (● answer first) ticket))) (● enginestate answers)))
        (match answer
          ((Some (Some bytes))
           (set! (● enginestate held) bytes)
           (i64->i32 (vector-length bytes)))
          ((Some (None)) (panic "cannot read a linked file: the store does not have it"))
          ((None) (panic "a ticket was finished before its read completed")))))

    (define (resource-byte (index I32)) (→ I32) (! mut)
      (u8->i32 (vector-ref (● enginestate held) (i32->i64 index))))
(struct EngineState
  ((linked (Option Linked))
   (status I64)
   (turning Turning)
   (woke Bool)
   (files (Vector String))
   (answers (List (Pair I64 (Option Bytes))))
   (held Bytes)))
(define enginestate (→ EngineState) (EngineState (None) 0 (Idle) #f (ann (list->vector (Nil)) (Vector String)) (Nil) #u8))

))
