;; Scalar boundary for native bounded file reads. Paths are staged without
;; suspension. An operation ID names the read; its ticket names the waiter.
(define-library (snail runtime native async-files)
  (export path-character start-read finish byte)
  (import
   (snail core base))
  (begin
    (extern path-character
            "snail.runtime.native.async-files"
            "path-character"
            (Fn Char → Unit))
    (extern start-read "snail.runtime.native.async-files" "start-read" (Fn I64 I32 → I64))
    (extern finish "snail.runtime.native.async-files" "finish" (Fn I64 → I32))
    (extern byte "snail.runtime.native.async-files" "byte" (Fn I32 → I32))))
