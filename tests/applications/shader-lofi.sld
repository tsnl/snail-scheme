(define-library (tests shader-lofi)
  (export answer)
  (import (lofi core) (lofi base) (webgpu shader))
  (begin
    (def answer (-> I32)
         (lambda () (if (shader-valid? (compile-shader (gpu (vec4 position zero one)) (gpu color))) 1 0)))))
