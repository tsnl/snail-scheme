;; Deriving resolves its helpers even when the library does not import them.
(define-library (sample representation)
  (export
   Envelope)
  (import
   (only (snail core base) record String List))
  (begin
    (record Envelope
      ((name String)
       (contents (List String)))
      (deriving Repr))))
