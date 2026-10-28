;; A plugin: a program built apart from the host, which exposes
;; `summarize` for programs that load it. It is built twice, against the
;; shared library (project) and against a stale declaration of it. It
;; imports (cell) only so that its build holds that library's module, which
;; the host loads by itself.
(import
 (snail-core base)
 (cell)
 (project))

;; Set when the plugin's main runs, which loading it must do first.
(: label String)
(define label (string-append "summary of " "the project"))

(: summarize (-> Project Report))
(define (summarize project)
  (Report (string-append label " " (Project-name project)) (length (Project-estimates project)) (fold-left + 0 (Project-estimates project))))

(expose summarize "summarize" dynamic)
