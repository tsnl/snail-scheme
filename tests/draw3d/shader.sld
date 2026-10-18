(define-library (tests draw3d shader)
  (export answer)
  (import
   (scheme base)
   (draw3d shaders))
  (begin (define answer shader-entry)))
