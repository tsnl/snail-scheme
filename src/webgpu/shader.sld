;; A deliberately small Scheme-style shader language. Both product surfaces
;; can import its macros, AST constructors and compiler as ordinary libraries.
(define-library (webgpu shader)
  (export gpu ShaderExpression shader-zero shader-one shader-position shader-color
          shader-vec4 shader-product compile-shader shader-valid? shader-text)
  (import
   (scheme base)
   (only (lofi base) string-append)
   (only (lofi core) datatype match))
  (begin

    ;; ---- Shader syntax ----

    ;; Names and operators are closed constructors, so source text cannot be
    ;; injected through a string. The initial vertex layout is position:vec2f
    ;; and color:vec4f; the fragment stage receives the interpolated color.
    (define ShaderExpression
      (datatype ()
        (shader-zero)
        (shader-one)
        (shader-position)
        (shader-color)
        (shader-vec4
         (xy ShaderExpression)
         (z ShaderExpression)
         (w ShaderExpression))
        (shader-product
         (left ShaderExpression)
         (right ShaderExpression))))
    (define ShaderResult
      (datatype ()
        (compiled-shader
         (valid Bool shader-valid?)
         (text String shader-text))))
    (define-syntax gpu
      (syntax-rules (zero one position color vec4 *)
        ((_ zero) (shader-zero))
        ((_ one) (shader-one))
        ((_ position) (shader-position))
        ((_ color) (shader-color))
        ((_ (vec4 xy z w)) (shader-vec4 (gpu xy) (gpu z) (gpu w)))
        ((_ (* left right)) (shader-product (gpu left) (gpu right)))))

    ;; ---- Stage and width checking ----

    ;; Zero means invalid. Successful widths are 1, 2 or 4. The compiler checks
    ;; both trees once before emission; a result owns either WGSL or a diagnostic.
    (define (product-width left right)
      (cond ((or (= left 0) (= right 0)) 0)
            ((= left 1) right) ((= right 1) left)
            ((= left right) left) (else 0)))
    (define (expression-width expression vertex?)
      (match expression
        ((shader-zero) 1) ((shader-one) 1)
        ((shader-position) (if vertex? 2 0)) ((shader-color) 4)
        ((shader-vec4 xy z w)
         (if (and (= (expression-width xy vertex?) 2)
                  (= (expression-width z vertex?) 1) (= (expression-width w vertex?) 1)) 4 0))
        ((shader-product left right)
         (product-width (expression-width left vertex?) (expression-width right vertex?)))))

    ;; ---- WGSL emission ----

    ;; Successful width/stage checks cover every subtree. The private emitter
    ;; reads those same immutable trees, so no second checked AST is needed.
    (define (expression-source expression)
      (match expression
        ((shader-zero) "0.0") ((shader-one) "1.0")
        ((shader-position) "input.position") ((shader-color) "input.color")
        ((shader-vec4 xy z w)
         (string-append "vec4f(" (expression-source xy) ", " (expression-source z)
                        ", " (expression-source w) ")"))
        ((shader-product left right)
         (string-append "(" (expression-source left) " * " (expression-source right) ")"))))
    (define (module-source vertex fragment)
      (string-append
       "struct VertexInput { @location(0) position: vec2f, @location(1) color: vec4f };\n"
       "struct VertexOutput { @builtin(position) position: vec4f, @location(0) color: vec4f };\n"
       "@vertex fn vertex_main(input: VertexInput) -> VertexOutput {\n"
       "  var output: VertexOutput;\n  output.position = " (expression-source vertex) ";\n"
       "  output.color = input.color;\n  return output;\n}\n"
       "@fragment fn fragment_main(input: VertexOutput) -> @location(0) vec4f {\n"
       "  return " (expression-source fragment) ";\n}\n"))
    (define (compile-shader vertex fragment)
      (cond ((not (= (expression-width vertex #t) 4))
             (compiled-shader #f "vertex expression must produce vec4; check operand widths"))
            ((not (= (expression-width fragment #f) 4))
             (compiled-shader #f "fragment expression must produce vec4; position is vertex-only"))
            (else (compiled-shader #t (module-source vertex fragment)))))))
