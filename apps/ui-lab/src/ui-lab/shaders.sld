;; App-authored shader code contains Scheme forms, not embedded WGSL.
(define-library (ui-lab shaders)
  (export shader-entry)
  (import
   (scheme base)
   (webgpu shader)
   (browser application)
   (only (lofi core) ann -> I32))
  (begin
    ;; Composition is ordinary Scheme macro expansion before shader checking.
    (define-syntax clip-position
      (syntax-rules () ((_ ) (gpu (vec4 position zero one)))))
    (define program (compile-shader (clip-position) (gpu (* color one))))
    (define shader-entry
      (ann (lambda (index)
             (let ((value (text-scalar (shader-text program) index)))
               (if (and (< index 0) (not (shader-valid? program))) (- 0 value) value)))
           (-> I32 I32)))))
