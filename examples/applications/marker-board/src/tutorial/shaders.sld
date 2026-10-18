(define-library (tutorial shaders)
  (export shader-entry)
  (import
   (scheme base)
   (webgpu shader)
   (browser application)
   (only (lofi core) ann -> I32))
  (begin

    ;; ---- Pass through the renderer's position and color ----

    (define shader (compile-shader (gpu (vec4 position zero one)) (gpu color)))
    (define shader-entry
      (ann (lambda (index)
             (let ((value (text-scalar (shader-text shader) index)))
               (if (and (< index 0) (not (shader-valid? shader))) (- 0 value) value)))
           (-> I32 I32)))))
