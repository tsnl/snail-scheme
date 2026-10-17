(import
 (lofi core))
(def local (syntax-rules () ((_ name) (begin (def name 42) name))))
;; Expression begin still confines the definition to its own block.
(def result (local hidden))
hidden
