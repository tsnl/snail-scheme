;; Direct source tools inspect a debug build. The build driver supplies the
;; selected mode as a constant before checking a browser or native program.
(define-library (snail shell build-mode)
  (export debug-build?)
  (import
   (snail core base))
  (begin (define debug-build? (→ Bool) #t)))
