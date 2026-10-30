;; The bytes of a linked file, as every host provides them: its length and
;; each byte, by the handle the program was linked with. (snail shell
;; resource)'s `resource` effect defaults to these.
(define-library (snail runtime resource)
  (export
   length
   byte)
  (import
   (snail core base))
  (begin
    (extern length "snail.runtime.resource" "length" (-> I32 I32))
    (extern byte "snail.runtime.resource" "byte" (-> I32 I32 U8))))
