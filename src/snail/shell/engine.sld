;; The native engine: links a program compiled one library at a time from
;; its modules.json and runs it. A host, Node (host/native/run-snail.mjs)
;; or wasmtime (crates/snail), starts this one module with the manifest's
;; path in SNAIL_MANIFEST and the program's arguments, and does only what
;; a host must: WASI, the Wasm primitives of (snail shell wasm), its device
;; services, and the loop that turns the program's scheduler. The engine
;; reads the manifest and each object from the store it names, links the
;; runtime and then each library against the providers it chooses, the
;; rules host/browser/load.mjs still keeps for the page, runs each main in
;; program order, and serves the files the program links, which it reads
;; when a task asks. The host sees the program's scheduler through the
;; engine's exports, which forward to it: `tasks:turn`, `tasks:wake`,
;; `tasks:close`, `tasks:running` and `tasks:live`, as (snail shell task)
;; names them, so a host drives a linked program and this alike.
(define-library (snail shell engine)
  (export
   run-manifest
   program-status
   tasks-turn
   tasks-wake
   tasks-close
   tasks-running
   tasks-live
   resource-read
   resource-finish
   resource-byte
   close-program)
  (import
   (snail core base)
   (snail core io)
   (snail shell json)
   (snail shell json read)
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

    (: read-manifest (-> String Manifest ! fs))
    (define (read-manifest path)
      (match (manifest-of (directory-of path) (string->json (read-file path)))
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

    ;; Links the program the manifest at `path` names and runs each main in
    ;; program order, answering the last one's result.
    (: run-manifest (-> String I64 ! mut fs wasm))
    (define (run-manifest path)
      (let* ((manifest (read-manifest path))
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
           ! fs wasm))
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
       (-> Manifest String Object (Option Module) (List (Pair String Module)) Module ! fs wasm))
    (define (link-object manifest name object runtime libraries)
      (let ((compiled
             (match (compile-bytes (read-bytes (object-file manifest (Object-digest object))))
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

    ;; ---- The scheduler ----

    ;; The host drives the program's scheduler through these, which forward
    ;; to the instance of (snail shell task); a program without one has no
    ;; task to run, so its turn answers -1 at once. A turn also wakes the
    ;; tickets of the files read during it, which (snail shell task)
    ;; readies for the next turn, so a turn that woke one answers 0.
    (: tasks-turn (-> I64 I64 ! mut wasm))
    (define (tasks-turn now)
      (match (scheduler)
        ((Some scheduler)
         (let ((answer (call scheduler "tasks:turn" now)))
           (if (wake-pending! scheduler) 0 answer)))
        ((None) -1)))

    (: tasks-wake (-> I64 I32 ! mut wasm))
    (define (tasks-wake ticket)
      (match (scheduler)
        ((Some scheduler) (i64->i32 (call scheduler "tasks:wake" ticket)))
        ((None) 0)))

    (: tasks-close (-> Unit ! mut wasm))
    (define (tasks-close)
      (match (scheduler)
        ((Some scheduler) (call scheduler "tasks:close" 0) (unit))
        ((None) (unit))))

    (: tasks-running (-> I64 ! mut wasm))
    (define (tasks-running)
      (match (scheduler)
        ((Some scheduler) (call scheduler "tasks:running" 0))
        ((None) 0)))

    (: tasks-live (-> I64 ! mut wasm))
    (define (tasks-live)
      (match (scheduler)
        ((Some scheduler) (call scheduler "tasks:live" 0))
        ((None) 0)))

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

    ;; The `resource` effect of (snail shell resource), as the host served
    ;; it: a task starts reading a file by handle under its ticket, which
    ;; is woken after the turn; it finishes the ticket for the file's
    ;; length, and then reads the bytes held until the next finish. The
    ;; read itself happens here and now, from the store, so a file that
    ;; cannot be read traps the task that asked.
    (: files (Ref (Vector String)))
    (define files (ref (ann (list->vector (Nil)) (Vector String))))

    (: answers (Ref (List (Pair I64 Bytes))))
    (define answers (ref (Nil)))

    (: pending (Ref (List I64)))
    (define pending (ref (Nil)))

    (: held (Ref Bytes))
    (define held (ref #u8()))

    (: resource-read (-> I64 I32 Unit ! mut fs))
    (define (resource-read ticket handle)
      (let ((bytes (read-bytes (vector-ref (ref-get files) (i32->i64 handle)))))
        (ref-set! answers (Cons (Pair ticket bytes) (ref-get answers)))
        (ref-set! pending (Cons ticket (ref-get pending)))))

    (: resource-finish (-> I64 I32 ! mut))
    (define (resource-finish ticket)
      (match (assoc-ref (ref-get answers) ticket)
        ((Some bytes)
         (ref-set! answers
                   (filter (lambda (answer) (not (= (Pair-first answer) ticket)))
                           (ref-get answers)))
         (ref-set! held bytes)
         (i64->i32 (vector-length bytes)))
        ((None) (panic "a ticket was finished before its read completed"))))

    (: resource-byte (-> I32 I32 ! mut))
    (define (resource-byte index)
      (u8->i32 (vector-ref (ref-get held) (i32->i64 index))))

    ;; Wakes each ticket read since the last turn, oldest first, answering
    ;; whether there was one.
    (: wake-pending! (-> Module Bool ! mut wasm))
    (define (wake-pending! scheduler)
      (let ((tickets (reverse (ref-get pending))))
        (ref-set! pending (Nil))
        (for-each (lambda (ticket) (call scheduler "tasks:wake" ticket) (unit)) tickets)
        (not (null? tickets))))))
