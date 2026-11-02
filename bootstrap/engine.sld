;; The native engine, which stage 0 builds (`scripts/snail-tool cli-tools`)
;; and host/native/run-snail.mjs and `snail run-wasm` start to run a
;; program compiled one library at a time: SNAIL_MANIFEST names its
;; modules.json. Its store is files, read where the manifest says, and the
;; host turns the engine's scheduler and the program's through the exports
;; below ((snail shell engine)). The engine links in its first task, so a
;; host turns it once before it reads `engine:status`.
(import
 (snail core base)
 (snail core io)
 (snail shell engine)
 (only (snail shell wasm) wasm))

;; The store is files: an object is read at once, and one that is not
;; there is none.
(: with-files (All (A e) (-> (-> A ! linked-content-store e) A ! fs e)))
(define (with-files body)
  (handle linked-content-store
      ((read-object (lambda (path)
                      (if (file-exists? path)
                          (Some (read-bytes path))
                          (None)))))
    (body)))

(: read-file-resource (-> I64 I32 Unit ! mut fs wasm))
(define (read-file-resource ticket handle)
  (with-files (lambda () (resource-read ticket handle))))

(expose engine-turn "engine:turn")
(expose engine-wake "engine:wake")
(expose engine-close-tasks "engine:close-tasks")
(expose engine-running "engine:running")
(expose engine-live "engine:live")
(expose read-file-resource "resource:read")
(expose resource-finish "resource:finish")
(expose resource-byte "resource:byte")
(expose program-status "engine:status")
(expose close-program "engine:close")

(match (environment-variable "SNAIL_MANIFEST")
  ((Some manifest) (with-files (lambda () (run-manifest manifest (read-file manifest)))) (unit))
  ((None) (panic "the engine needs SNAIL_MANIFEST, the modules.json of the program to run")))
