(define-library (tests shader)
  (export answer)
  (import (scheme base) (webgpu shader) (only (lofi core) ann -> I32))
  (begin
    (define-syntax clip (syntax-rules () ((_) (gpu (vec4 position zero one)))))
    (define answer
      (ann (lambda ()
             (if (and (shader-valid? (compile-shader (clip) (gpu (* color one))))
                      (not (shader-valid? (compile-shader (gpu (* position color)) (gpu color))))
                      (not (shader-valid? (compile-shader (clip) (gpu position))))) 1 0)) (-> I32)))))
