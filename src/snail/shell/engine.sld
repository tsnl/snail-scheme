;; The engine links a manifest's modules and schedules their main in the
;; same scheduler as its loading and file work.
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
   (only (snail shell compiler read)
         Syntax
         Atom
         Ident
         Form
         DString
         DInt
         read-text
         compiling)
   (snail shell task)
   (snail shell wasm))
  (begin

    ;; ---- The manifest ----

    ;; An object as the manifest names it: the digest that names it in the
    ;; store, and its size.
    (record Object
      ((digest String)
       (size I64)))

    ;; The manifest, with the directory it was read from, whose store/ holds
    ;; its objects: the runtime, each library's module by name in program
    ;; order, and the files the program links.
    (record Manifest
      ((directory String)
       (runtime Object)
       (modules (List (Pair String Object)))
       (files (List Object))))

    ;; The manifest at `path`, whose text the entry read: one list of
    ;; `(runtime "DIGEST" SIZE)`, then `(module "LIBRARY" "DIGEST" SIZE)` and
    ;; `(file "DIGEST" SIZE)` entries, read by the compiler's reader.

    (define (parse-manifest (path String) (text String)) (→ Manifest)
      (match (compiling (lambda () (read-text text path)))
        ((Ok (Cons (Form (Cons (Form (Cons (Ident "runtime" _ _) runtime) _) entries) _) (Nil)))
         (fold-right (lambda (entry manifest) (with-entry path manifest entry))
                     (new Manifest (directory (directory-of path))
                          (runtime (object-of path runtime))
                          (modules (Nil))
                          (files (Nil)))
                     entries))
        (_ (not-a-manifest path))))

    ;; `manifest` with `entry` before what it holds, as the entries are
    ;; folded from the last.

    (define (with-entry (path String) (manifest Manifest) (entry Syntax)) (→ Manifest)
      (match entry
        ((Form (Cons (Ident "module" _ _) (Cons (Atom (DString name) _) object)) _)
         (if (module-name-available? name (● manifest modules))
             (Manifest-modules-set manifest
                                   (Cons (new Pair (first name) (second (object-of path object)))
                                         (● manifest modules)))
             (panic (string-append path " may not link a library as " name))))
        ((Form (Cons (Ident "file" _ _) object) _)
         (Manifest-files-set manifest (Cons (object-of path object) (● manifest files))))
        (_ (not-a-manifest path))))

    (define (object-of (path String) (fields (List Syntax))) (→ Object)
      (match fields
        ((Cons (Atom (DString digest) _) (Cons (Atom (DInt size) _) (Nil)))
         (new Object (digest digest) (size size)))
        (_ (not-a-manifest path))))

    (define (not-a-manifest (path String)) (→ A) (∀ (A))
      (panic (string-append path " is not the manifest of a program")))

    ;; Library imports cannot shadow runtime services or ambiguously name a
    ;; provider.
    (define (module-name-available? (name String) (named (List (Pair String Object)))) (→ Bool)
      (and (not (string=? name ""))
           (not (string=? name "snail.core.support"))
           (not (and (>= (string-length name) 14)
                     (string=? (substring name 0 14) "snail.runtime.")))
           (not (any? (lambda (entry) (string=? name (● entry first))) named))))

    ;; A path's directory with its final slash, or "" for a bare name.

    (define (directory-of (path String)) (→ String)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) "")
              ((char=? (string-ref path index) #\/) (substring path 0 (+ index 1)))
              (else (loop (- index 1))))))

    ;; Where an object lies: store/ beside the manifest, under sha256/,
    ;; sharded by the digest's first two hex digits.

    (define (object-file (manifest Manifest) (digest String)) (→ String)
      (string-append (● manifest directory) "store/sha256/" (substring digest 0 2) "/" digest))

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

    ;; The host holds the engine, and its work holds it too. The loaded
    ;; instances are held by host handles and by their importers; engine
    ;; metadata need not keep another library registry.
    (record Engine
      ((scheduler Scheduler)
       (runtime (Option Module))
       (status I64)
       (files (Vector String))
       (answers (List (Pair I64 (Option Bytes))))
       (held Bytes)))

    (define (make-engine) (→ Engine)
      (new Engine
        (scheduler (make-scheduler))
        (runtime (None))
        (status 0)
        (files (make-vector 0 ""))
        (answers (Nil))
        (held #u8())))

    ;; Startup links in one task. Program work joins the same FIFO.
    (define (run-manifest (engine Engine) (path String) (text String))
      (→ Unit) (! mut host wasm linked-content-store)
      (dispatch-in (● engine scheduler)
                   (lambda () (link-manifest engine (parse-manifest path text))))
      (unit))

    (define (link-manifest (engine Engine) (manifest Manifest))
      (→ Unit) (! mut host wasm tasks linked-content-store)
      (let ((runtime (link-object manifest "the runtime" (● manifest runtime) (None) (Nil))))
        (bind-runtime runtime)
        (set! (● engine runtime) (Some runtime))
        (set! (● engine files)
              (list->vector (map (lambda (object) (object-file manifest (● object digest)))
                                 (● manifest files))))
        (run-main engine (link-libraries manifest runtime (● manifest modules) (Nil)))))

    (define (run-main (engine Engine) (libraries (List (Pair String Module))))
      (→ Unit) (! mut host wasm)
      (match libraries
        ((Nil) (panic "the manifest has no program"))
        ((Cons (Pair _ program) (Nil))
         (match (module-export program "main:body")
           ((Ok body) (start-main (● engine scheduler) body))
           ((Err _) (panic "the program has no main function"))))
        ((Cons _ rest) (run-main engine rest))))

    (define (program-status (engine Engine)) (→ I64)
      (● engine status))

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
           (link-libraries manifest
                           runtime
                           rest
                           (Cons (new Pair (first name) (second instance)) libraries))))))

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

    ;; One scheduler means one ticket space and one turn. Loading
    ;; work and program work have the same lifetime.
    (define (engine-turn (engine Engine) (now I64)) (→ I64) (! mut host)
      (tasks-turn (● engine scheduler) now))

    (define (engine-wake (engine Engine) (ticket I64)) (→ I32) (! mut)
      (if (tasks-wake! (● engine scheduler) ticket) 1 0))

    (define (engine-close-tasks (engine Engine)) (→ Unit) (! mut)
      (tasks-close! (● engine scheduler)))

    (define (engine-running (engine Engine)) (→ I64)
      (tasks-running (● engine scheduler)))

    (define (engine-live (engine Engine)) (→ I64)
      (tasks-live (● engine scheduler)))

    ;; Calls an export the program's modules are known to have; one they
    ;; lack is a build the engine cannot run.

    (define (call (instance Module) (name String) (argument I64)) (→ I64) (! wasm)
      (match (run-export instance name argument)
        ((Ok answer) answer)
        ((Err error) (panic (load-error-message error)))))

    ;; Closes the program's runtime, as the host closes its own: the
    ;; status of closing its resources.

    (define (close-program (engine Engine)) (→ I32) (! wasm)
      (match (● engine runtime)
        ((Some runtime) (i64->i32 (call runtime "snail:io/close-all" 0)))
        ((None) 0)))

    ;; ---- Linked files ----

    ;; The host's resource imports forward to these entries with its engine.
    ;; A file-read task's completion wakes the program's ticket in the same
    ;; scheduler, after installing the bytes.
    (define (resource-read (engine Engine) (ticket I64) (handle I32))
      (→ Unit) (! mut host linked-content-store)
      (let ((file (vector-ref (● engine files) (i32->i64 handle))))
        (dispatch-in (● engine scheduler)
                     (lambda ()
                       (let ((bytes (read-object file)))
                         (set! (● engine answers)
                               (Cons (new Pair (first ticket) (second bytes))
                                     (● engine answers)))
                         (unless (tasks-wake! (● engine scheduler) ticket)
                           (take-answer engine ticket) (unit)))))
        (unit)))

    (define (take-answer (engine Engine) (ticket I64)) (→ (Option (Option Bytes))) (! mut)
      (let ((answer (assoc-ref (● engine answers) ticket)))
        (set! (● engine answers)
              (filter (lambda (answer) (not (= (● answer first) ticket))) (● engine answers)))
        answer))

    (define (resource-finish (engine Engine) (ticket I64)) (→ I32) (! mut)
      (match (take-answer engine ticket)
        ((Some (Some bytes))
         (set! (● engine held) bytes)
         (i64->i32 (vector-length bytes)))
        ((Some (None)) (panic "cannot read a linked file: the store does not have it"))
        ((None) (panic "a ticket was finished before its read completed"))))

    (define (resource-byte (engine Engine) (index I32)) (→ I32)
      (u8->i32 (vector-ref (● engine held) (i32->i64 index))))))
