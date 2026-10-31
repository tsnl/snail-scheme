;; Files a library links instead of embedding, as Python's
;; importlib.resources names a package's data. `(link-file "path")` ties
;; the file beside the library's source to the library, as `include-bytes`
;; names one, but as a dependency rather than as bytes: the build ships the
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

    ;; The handle the host gave the file when it linked the module.
    (struct LinkedResource
      ((handle I32)))

    (type Resource LinkedResource)

    ;; Constructor identifiers keep their definition scope, so the template
    ;; constructs a Resource where the user cannot name its constructor.
    (define-syntax link-file
      (syntax-rules ()
        ((_ path) (LinkedResource (link-handle path)))))

    ;; ---- Reading ----

    ;; A linked file's bytes, by handle. By default the host reads the file
    ;; from resources/ beside the payload the first time a task asks for
    ;; it, and the task waits until it has; a handler can serve it
    ;; otherwise.
    (effect resource
      ((resource-bytes (-> I32 Bytes ! tasks)))
      (default ((resource-bytes host-bytes))))

    ;; The host holds the bytes from `finish` until its next `finish`, and
    ;; nothing between the two calls lets another task run.
    (: host-bytes (-> I32 Bytes ! tasks))
    (define (host-bytes handle)
      (through-host (lambda (ticket) (host-read ticket handle))
                    (lambda (ticket)
                      (vector-generate (i32->i64 (host-finish ticket))
                                       (lambda (index) (host-byte (i64->i32 index)))))))

    ;; The file's bytes, as they were when the host first read them.
    (: read-resource (-> Resource Bytes ! resource tasks))
    (define (read-resource linked)
      (resource-bytes (LinkedResource-handle linked)))

    ))
