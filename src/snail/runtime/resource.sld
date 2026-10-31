;; The bytes of a linked file, as every host provides them, by the handle
;; the program was linked with. A host reads a file only when the program
;; asks: `read` starts reading it under a ticket of (snail shell task) and
;; returns at once; once the ticket wakes, `finish` answers the file's
;; length and holds its bytes, which `byte` reads, until the next `finish`.
;; (snail shell resource)'s `resource` effect defaults to these.
(define-library (snail runtime resource)
  (export
   read
   finish
   byte)
  (import
   (snail core base))
  (begin
    (extern read "snail.runtime.resource" "read" (-> I64 I32 Unit))
    (extern finish "snail.runtime.resource" "finish" (-> I64 I32))
    (extern byte "snail.runtime.resource" "byte" (-> I32 U8))))
