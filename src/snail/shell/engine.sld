;; The engine links a manifest's modules and schedules their main in the
;; same owned scheduler as its loading and file work. Its metadata holds only
;; a weak scheduler reference, so saved work cannot retain the engine owner.
(define-library (snail shell engine)
  (export
   linked-content-store
   read-object
   Engine make-engine run-manifest
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
   (only (snail core forms) host Funcref)
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
                       (if (module-name-available? name rest)
                           (Some (Cons (Pair name object) rest)) (None)))
                      (_ (None))))
                  (Some (Nil))
                  entries))

    ;; The parsed tail is also the set of names already accepted. Library
    ;; imports cannot shadow runtime services or ambiguously name a provider.
    (define (module-name-available? (name String) (rest (List (Pair String Object)))) (→ Bool)
      (and (not (string=? name ""))
           (not (string=? name "snail.core.support"))
           (not (and (>= (string-length name) 14)
                     (string=? (substring name 0 14) "snail.runtime.")))
           (not (any? (lambda (entry) (string=? name (● entry first))) rest))))

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

    ;; The host owns Engine. Work captures EngineState, which contains only
    ;; ordinary heap data and a weak scheduler reference. The loaded instances
    ;; are held by host handles and by their importers; engine metadata need
    ;; not keep another library registry.
    (struct Engine
      ((scheduler Scheduler)
       (state EngineState)))

    (struct EngineState
      ((scheduler WeakScheduler)
       (runtime (Option Module))
       (status I64)
       (files (Vector String))
       (answers (List (Pair I64 (Option Bytes))))
       (held Bytes)))

    (define (make-engine) (→ Engine)
      (let ((scheduler (make-scheduler)))
        (Engine scheduler
                (EngineState (rc-downgrade scheduler) (None) 0 (make-vector 0 "") (Nil) #u8()))))

    ;; Startup transfers metadata into one task; that task does not capture
    ;; Engine or its strong scheduler owner. Program work joins the same FIFO.
    (define (run-manifest (engine Engine) (path String) (text String))
      (→ Unit) (! mut host wasm linked-content-store)
      (let ((state (● engine state)))
        (dispatch-in (● engine scheduler)
                     (once (lambda () (link-manifest state (parse-manifest path text))))))
      (unit))

    (define (link-manifest (state EngineState) (manifest Manifest))
      (→ Unit) (! mut host wasm tasks linked-content-store)
      (let ((runtime (link-object manifest "the runtime" (● manifest runtime) (None) (Nil))))
        (bind-runtime runtime)
        (set! (● state runtime) (Some runtime))
        (set! (● state files)
              (list->vector (map (lambda (object) (object-file manifest (● object digest)))
                                 (● manifest files))))
        (run-main state (link-libraries manifest runtime (● manifest modules) (Nil)))))

    (define (run-main (state EngineState) (libraries (List (Pair String Module))))
      (→ Unit) (! mut host wasm)
      (match libraries
        ((Nil) (panic "the manifest has no program"))
        ((Cons (Pair _ program) (Nil))
         (match (module-export program "main:body")
           ((Ok body) (start-loaded-main state body))
           ((Err _) (panic "the program has no main function"))))
        ((Cons _ rest) (run-main state rest))))

    (define (start-loaded-main (state EngineState) (body Funcref)) (→ Unit) (! mut host)
      (match (weak-rc-upgrade (● state scheduler))
        ((Some scheduler) (start-main scheduler body))
        ((None) (panic "the engine's scheduler has closed"))))

    (define (program-status (engine Engine)) (→ I64) (! mut host)
      (● (● engine state) status))

    ;; Each library linked against the runtime and the libraries before it,
    ;; in program order. The local list supplies each import explicitly.

    (define (link-libraries (manifest Manifest)
                            (runtime Module)
                            (modules (List (Pair String Object)))
                            (libraries (List (Pair String Module))))
      (→ (List (Pair String Module)))
      (! wasm tasks linked-content-store)
      (match modules
        ((Nil) (reverse libraries))
        ((Cons (Pair name object) rest)
         (let ((instance (if (string=? name "snail.core.control") (loading-program)
                             (link-object manifest name object (Some runtime) libraries))))
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
               (HostProvided))
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

    ;; ---- Driving and closing ----

    ;; One scheduler means one ticket space and one bounded FIFO turn. Loading
    ;; work and program work have the same lifetime and cancellation protocol.
    (define (engine-turn (engine Engine) (now I64)) (→ I64) (! mut host)
      (tasks-turn (● engine scheduler) now))

    (define (engine-wake (engine Engine) (ticket I64)) (→ I32) (! mut host)
      (if (tasks-wake! (● engine scheduler) ticket) 1 0))

    (define (engine-close-tasks (engine Engine)) (→ Unit) (! mut host)
      (tasks-close! (● engine scheduler)))

    (define (engine-running (engine Engine)) (→ I64) (! mut host)
      (tasks-running (● engine scheduler)))

    (define (engine-live (engine Engine)) (→ I64) (! mut host)
      (tasks-live (● engine scheduler)))

    ;; Calls an export the program's modules are known to have; one they
    ;; lack is a build the engine cannot run.

    (define (call (instance Module) (name String) (argument I64)) (→ I64) (! wasm)
      (match (run-export instance name argument)
        ((Ok answer) answer)
        ((Err error) (panic (load-error-message error)))))

    ;; Closes the program's runtime, as the host closes its own: the
    ;; status of closing its resources.

    (define (close-program (engine Engine)) (→ I32) (! mut host wasm)
      (match (● (● engine state) runtime)
        ((Some runtime) (i64->i32 (call runtime "snail:io/close-all" 0)))
        ((None) 0)))

    ;; ---- Linked files ----

    ;; The host's resource imports forward to these entries with its engine
    ;; owner. A file-read task captures metadata alone. Its completion wakes
    ;; the program's ticket in the same scheduler, after installing the bytes.
    (define (resource-read (engine Engine) (ticket I64) (handle I32))
      (→ Unit) (! mut host linked-content-store)
      (let* ((state (● engine state)) (file (vector-ref (● state files) (i32->i64 handle))))
        (dispatch-in (● engine scheduler)
                     (once (lambda ()
                             (let ((bytes (read-object file)))
                               (set! (● state answers) (Cons (Pair ticket bytes) (● state answers)))
                               (unless (wake-task! (● state scheduler) ticket)
                                 (take-answer state ticket) (unit))))))
        (unit)))

    (define (take-answer (state EngineState) (ticket I64)) (→ (Option (Option Bytes))) (! mut)
      (let ((answer (assoc-ref (● state answers) ticket)))
        (set! (● state answers)
              (filter (lambda (answer) (not (= (● answer first) ticket))) (● state answers)))
        answer))

    (define (resource-finish (engine Engine) (ticket I64)) (→ I32) (! mut host)
      (let ((state (● engine state)))
        (match (take-answer state ticket)
          ((Some (Some bytes))
           (set! (● state held) bytes)
           (i64->i32 (vector-length bytes)))
          ((Some (None)) (panic "cannot read a linked file: the store does not have it"))
          ((None) (panic "a ticket was finished before its read completed")))))

    (define (resource-byte (engine Engine) (index I32)) (→ I32) (! mut host)
      (u8->i32 (vector-ref (● (● engine state) held) (i32->i64 index))))))
