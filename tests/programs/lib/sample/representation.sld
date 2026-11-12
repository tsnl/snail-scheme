;; Deriving resolves its helpers even when the library does not import them.
(define-library (sample representation)
  (export
   Envelope)
  (import
   (only (snail core base) struct String List))
  (begin
    (struct Envelope
      ((name String)
       (contents (List String)))
      (deriving Repr))))
