;; Files a library links instead of embedding, as Python's
;; importlib.resources names a package's data. `(link-file "path")` ties
;; the file beside the library's source to the library as a dependency. The build ships the
;; file beside the payload, and the program holds a Resource, a handle. A
;; host reads a file only when the program asks for it, by
;; `read-resource`, which asks its `Resources` and waits for the host as a
;; task does, since a page can only fetch the file. `read-resources`
;; reads several at once: a page fetches them together.
;;
;; A Resource can only come from `link-file`: the type is exported without
;; its constructor, so holding one is evidence that its file ships.
(define-library (snail shell resource)
  (export
   Resource
   link-file
   Resources
   host-resources
   read-resource
   read-resources)
  (import
   (snail core base)
   (only (snail core io) Host)
   (prefix (snail runtime resource) host-)
   (only (snail core forms) link-handle)
   (only (snail shell task) ticket await))
  (begin

    ;; ---- Resources ----

    ;; The closure resolves this instance's linker symbol when the resource
    ;; is read. Constructing it does not fetch the file.
    (record LinkedResource
      ((handle (Fn → I32))))

    (type Resource LinkedResource)

    ;; Constructor identifiers keep their definition scope, so the template
    ;; constructs a Resource where the user cannot name its constructor.
    (define-syntax link-file
      (syntax-rules ()
        ((_ path) (new LinkedResource (handle (lambda () (link-handle path)))))))

    ;; ---- Reading ----

    ;; Linked files' bytes, by handle, in the order asked. `host-resources`
    ;; has the host read each file, an object of the program's store, the
    ;; first time a task asks for it, and the task waits until it has;
    ;; another `Resources` can serve them otherwise.
    (capability Resources
      ((resource-bytes (Fn (List I32) → (List Bytes)))))

    (define (host-resources (host Host)) (→ Resources)
      (new Resources
        (resource-bytes host-bytes)))

    ;; Every read starts, under a ticket of its own, before the task waits,
    ;; so the host reads the files together; the task waits once, for all
    ;; of them, then takes each file's bytes in order.

    (define (host-bytes (handles (List I32))) (→ (List Bytes))
      (let ((ids (map (lambda (handle) (let ((id (ticket))) (host-read id handle) id)) handles)))
        (await ids)
        (map held-bytes ids)))

    ;; The host holds a file's bytes from `finish` until its next `finish`,
    ;; and nothing between the two calls lets another task run.

    (define (held-bytes (id I64)) (→ Bytes)
      (array-generate (i32->i64 (host-finish id)) (lambda (index) (host-byte (i64->i32 index)))))

    ;; The file's bytes, as they were when the host first read them.

    (define (read-resource (resources Resources) (linked Resource)) (→ Bytes)
      (list-ref (read-resources resources (list linked)) 0))

    ;; Each file's bytes, in the order given, the files read together.

    (define (read-resources (resources Resources) (linked (List Resource)))
      (→ (List Bytes))
      (resource-bytes resources (map (lambda (file) ((● file handle))) linked)))

    ))
