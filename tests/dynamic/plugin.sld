;; A plugin: a program built apart from the host, which exposes
;; `summarize` for programs that load it. It is built twice, against the
;; shared library (project) and against a stale declaration of it. It
;; imports (cell) only so that its build holds that library's module, which
;; the host loads by itself.
(import
 (snail core base)
 (cell)
 (project))

;; A pure compile-time value; loading the plugin runs no initializer.
(define label (→ String) (string-append "summary of " "the project"))

(define (summarize (project Project)) (→ Report)
  (Report (string-append label " " (● project name))
          (length (● project estimates))
          (fold-left + 0 (● project estimates))))

(expose summarize "summarize" dynamic)

;; A normal entry is present but was not exposed with the dynamic ABI.
(define (main) (→ Unit) (unit))
