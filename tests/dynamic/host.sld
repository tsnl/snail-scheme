;; Loads what other builds hold while it runs. The arguments are the
;; module of the plugin's library (cell), which this program does not
;; import, and the manifests of the plugin's two builds. The function cell
;; exports under its global name is cast unchecked. The plugin's
;; `summarize` takes and returns values of the shared library (project),
;; which cross by reference; the stale build is refused before anything is
;; called, and so is a function the plugin does not offer.
(import
 (snail core base)
 (snail core io)
 (snail shell wasm)
 (project))

(define (run-cell (file String)) (→ Unit) (! wasm fs output-port)
  (match (load-module "cell" file)
    ((Ok cell)
     (match (module-export cell "cell:run")
       ((Ok function) (display ((ann (unsafe-cast function) (Fn I64 → I64)) 41)) (newline))
       ((Err error) (write-line (load-error-message error)))))
    ((Err error) (write-line (load-error-message error)))))

(define (summarizer (plugin Plugin) (name String))
  (→ (Result (Fn Project → Report) LoadError))
  (! wasm)
  (plugin-function plugin name))

(define project (→ Project) (Project "Atlas" "Ada" (list 3 5 5)))

(define (summarize-with (manifest String) (name String)) (→ Unit) (! wasm fs output-port)
  (match (load-plugin manifest)
    ((Ok plugin)
     (match (summarizer plugin name)
       ((Ok summarize)
        (let ((report (summarize project)))
          (write-line
           (string-append (● report name) ": " (i64->string (● report tasks)) " tasks, "
                          (i64->string (● report days)) " days"))))
       ((Err error) (write-line (load-error-message error)))))
    ((Err error) (write-line (load-error-message error)))))

(match (command-line)
  ((Cons _ (Cons cell (Cons plugin (Cons stale (Nil)))))
   (run-cell cell)
   (summarize-with plugin "summarize")
   (summarize-with stale "summarize")
   (summarize-with plugin "missing")
   (summarize-with plugin "main")
   (summarize-with "build/tests/dynamic/missing/modules.json" "summarize"))
  (_ (panic "usage: host CELL-MODULE PLUGIN-MANIFEST STALE-MANIFEST")))
