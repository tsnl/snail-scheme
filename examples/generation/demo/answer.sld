;; This recipe executes as Wasm. Its String result is the source of a separate
;; library, which the driver parses and checks like any other file.
(generate-library (demo answer)
                  (import
                   (only (lofi base) string-append * i32->i64)
                   (only (lofi scalar-text) i64->string))
                  (string-append "(define-library (demo answer) (export main)"
                                 " (begin (def main (-> I32) (lambda () "
                                 (i64->string (i32->i64 (* 6 7))) "))))"))
