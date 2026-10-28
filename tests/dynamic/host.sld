;; Loads what other builds hold while it runs. The arguments are the
;; module of the plugin's library (cell), which this program does not
;; import, and the manifests of the plugin's two builds. The function cell
;; exports under its global name is cast unchecked. The plugin's
;; `summarize` takes and returns values of the shared library (project),
;; which cross by reference; the stale build is refused before anything is
;; called, and so is a function the plugin does not offer.
(import
 (snail-core base)
 (snail-core io)
 (snail-core wasm)
 (project))

(: run-cell (-> String Unit ! wasm fs console))
(define (run-cell file)
  (match (load-module "cell" file)
    ((Ok cell)
     (match (module-export cell "cell:run")
       ((Ok function) (display ((ann (unsafe-cast function) (-> I64 I64)) 41)) (newline))
       ((Err error) (write-line (load-error-message error)))))
    ((Err error) (write-line (load-error-message error)))))

(: summarizer (-> Plugin String (Result (-> Project Report) LoadError) ! wasm))
(define (summarizer plugin name)
  (plugin-function plugin name))

(: project Project)
(define project (Project "Atlas" "Ada" (list 3 5 5)))

(: summarize-with (-> String String Unit ! wasm fs console))
(define (summarize-with manifest name)
  (match (load-plugin manifest)
    ((Ok plugin)
     (match (summarizer plugin name)
       ((Ok summarize)
        (let ((report (summarize project)))
          (write-line (string-append (Report-name report) ": " (i64->string (Report-tasks report)) " tasks, "
                                     (i64->string (Report-days report)) " days"))))
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
