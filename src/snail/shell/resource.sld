;; Files a library links instead of embedding, as Python's
;; importlib.resources names a package's data. `(link-file "path")` ties
;; the file beside the library's source to the library as a dependency. The build ships the
;; file beside the payload, and the program holds a Resource, a handle. A
;; host reads a file only when the program asks for it, by
;; `read-resource`, which performs `resource` and waits for the host as a
;; task does, since a page can only fetch the file.
;;
;; A Resource can only come from `link-file`: the type is exported without
;; its constructor, so holding one is evidence that its file ships.
(define-library (snail shell resource)
  (export
   Resource
   link-file
   resource
   read-resource)
  (import
   (snail core base)
   (prefix (snail runtime resource) host-)
   (only (snail core forms) link-handle)
   (only (snail shell task) tasks through-host))
  (begin

    ;; ---- Resources ----

    ;; The constant stores code for a linker symbol, not a runtime handle.
    ;; Calling it resolves this instance's handle when the resource is read;
    ;; constructing a Resource is completely evaluable at compile time.
    (struct LinkedResource
      ((handle (fn → I32))))

    (type Resource LinkedResource)

    ;; Constructor identifiers keep their definition scope, so the template
    ;; constructs a Resource where the user cannot name its constructor.
    (define-syntax link-file
      (syntax-rules ()
        ((_ path) (LinkedResource (fn () (link-handle path))))))

    ;; ---- Reading ----

    ;; A linked file's bytes, by handle. By default the host reads the
    ;; file, an object of the program's store, the first time a task asks
    ;; for it, and the task waits until it has; a handler can serve it
    ;; otherwise.
    (effect resource
      ((resource-bytes (Fn I32 → Bytes ! tasks)))
      (default ((resource-bytes host-bytes))))

    ;; The host holds the bytes from `finish` until its next `finish`, and
    ;; nothing between the two calls lets another task run.

    (define (host-bytes (handle I32)) (→ Bytes) (! tasks)
      (through-host (lambda (ticket) (host-read ticket handle))
                    (lambda (ticket)
                      (vector-generate (i32->i64 (host-finish ticket))
                                       (lambda (index) (host-byte (i64->i32 index)))))))

    ;; The file's bytes, as they were when the host first read them.

    (define (read-resource (linked Resource)) (→ Bytes) (! resource tasks)
      (resource-bytes ((● linked handle))))

    ))
