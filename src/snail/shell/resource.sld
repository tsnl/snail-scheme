;; Files a library links instead of embedding, as Python's
;; importlib.resources names a package's data. `(link-bytes "path")`
;; names a file beside the library's source, as `include-bytes` does, but
;; the build ships the file beside the payload rather than in it, and the
;; program holds a Resource, a handle, rather than the bytes. Each file may
;; be read on its own, by `read-resource`, which performs `resource`.
;;
;; A Resource can only come from `link-bytes`: the type is exported without
;; its constructor, so holding one is evidence that its file ships. The
;; hosts read every file a program links before it starts, so reading one
;; never waits, in a browser page as in Node, and needs no file system.
(define-library (snail shell resource)
  (export
   Resource
   link-bytes
   resource
   read-resource)
  (import
   (snail core base)
   (only (snail core forms) link-file))
  (begin

    ;; ---- Resources ----

    ;; The handle the host gave the file when it linked the module.
    (struct LinkedResource
      ((handle I32)))

    (type Resource LinkedResource)

    ;; Constructor identifiers keep their definition scope, so the template
    ;; constructs a Resource where the user cannot name its constructor.
    (define-syntax link-bytes
      (syntax-rules ()
        ((_ path) (LinkedResource (link-file path)))))

    ;; ---- Reading ----

    ;; A linked file's length and bytes, by handle. The hosts read the files
    ;; from resources/ beside the payload before the program starts, so
    ;; neither operation waits; a handler can serve them otherwise.
    (effect resource
      ((resource-length (-> I32 I32))
       (resource-byte (-> I32 I32 U8)))
      (host "snail.resource"
            ((resource-length "length")
             (resource-byte "byte"))))

    ;; The file's bytes, as they were when the program was linked.
    (: read-resource (-> Resource Bytes ! resource))
    (define (read-resource linked)
      (let ((handle (LinkedResource-handle linked)))
        (vector-generate (i32->i64 (resource-length handle))
                         (lambda (index) (resource-byte handle (i64->i32 index))))))

    ))
