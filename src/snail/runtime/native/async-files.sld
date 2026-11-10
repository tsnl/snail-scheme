;; Scalar boundary for native bounded file reads. Paths are staged without
;; suspension. An operation ID owns reception; its ticket names the waiter.
(define-library (snail runtime native async-files)
  (export path-character start-read finish cancel byte)
  (import
   (snail core base))
  (begin
    (extern path-character "snail.runtime.native.async-files" "path-character" (-> Char Unit))
    (extern start-read "snail.runtime.native.async-files" "start-read" (-> I64 I32 I64))
    (extern finish "snail.runtime.native.async-files" "finish" (-> I64 I32))
    (extern cancel "snail.runtime.native.async-files" "cancel" (-> I64 Unit))
    (extern byte "snail.runtime.native.async-files" "byte" (-> I32 I32))))
