;; A deliberately small Scheme-style shader language. Both product surfaces
;; can import its macros, AST constructors and compiler as ordinary libraries.
(define-library (webgpu shader)
  (export gpu ShaderExpression shader-zero shader-one shader-position shader-color
          shader-normal shader-project shader-lambert shader-vec4 shader-product
          compile-shader compile-scene-shader shader-valid? shader-text)
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
        (shader-normal)
        (shader-project
         (position ShaderExpression))
        (shader-lambert
         (color ShaderExpression)
         (normal ShaderExpression))
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
      (syntax-rules (zero one position color normal project lambert vec4 *)
        ((_ zero) (shader-zero))
        ((_ one) (shader-one))
        ((_ position) (shader-position))
        ((_ color) (shader-color))
        ((_ normal) (shader-normal))
        ((_ (project value)) (shader-project (gpu value)))
        ((_ (lambert shade direction)) (shader-lambert (gpu shade) (gpu direction)))
        ((_ (vec4 xy z w)) (shader-vec4 (gpu xy) (gpu z) (gpu w)))
        ((_ (* left right)) (shader-product (gpu left) (gpu right)))))

    ;; ---- Stage and width checking ----

    ;; Zero means invalid. Successful widths are 1, 2 or 4. The compiler checks
    ;; both trees once before emission; a result owns either WGSL or a diagnostic.
    (define (product-width left right)
      (cond ((or (= left 0) (= right 0)) 0)
            ((= left 1) right) ((= right 1) left)
            ((= left right) left) (else 0)))
    (define (expression-width expression vertex? scene?)
      (match expression
        ((shader-zero) 1) ((shader-one) 1)
        ((shader-position) (if vertex? (if scene? 3 2) 0)) ((shader-color) 4)
        ((shader-normal) (if scene? 3 0))
        ((shader-project position)
         (if (and scene? vertex? (= (expression-width position vertex? scene?) 3)) 4 0))
        ((shader-lambert color normal)
         (if (and scene? (not vertex?) (= (expression-width color vertex? scene?) 4)
                  (= (expression-width normal vertex? scene?) 3)) 4 0))
        ((shader-vec4 xy z w)
         (if (and (= (expression-width xy vertex? scene?) 2)
                  (= (expression-width z vertex? scene?) 1) (= (expression-width w vertex? scene?) 1)) 4 0))
        ((shader-product left right)
         (product-width (expression-width left vertex? scene?) (expression-width right vertex? scene?)))))

    ;; ---- WGSL emission ----

    ;; Successful width/stage checks cover every subtree. The private emitter
    ;; reads those same immutable trees, so no second checked AST is needed.
    (define (expression-source expression)
      (match expression
        ((shader-zero) "0.0") ((shader-one) "1.0")
        ((shader-position) "input.position") ((shader-color) "input.color")
        ((shader-normal) "input.normal")
        ((shader-project position)
         (string-append "(scene.view_projection * vec4f(" (expression-source position) ", 1.0))"))
        ((shader-lambert color normal)
         (string-append "lambert(" (expression-source color) ", " (expression-source normal) ")"))
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
      (cond ((not (= (expression-width vertex #t #f) 4))
             (compiled-shader #f "vertex expression must produce vec4; check operand widths"))
            ((not (= (expression-width fragment #f #f) 4))
             (compiled-shader #f "fragment expression must produce vec4; position is vertex-only"))
            (else (compiled-shader #t (module-source vertex fragment)))))

    ;; ---- Lit indexed scenes share the checked expression language ----

    ;; Vertex alpha carries emission; ambient.w carries per-batch opacity.
    ;; The host draws translucent previews after opaque surfaces, without depth writes.
    ;; reveal.xy is the world center, z the advancing front and w the half-edge.
    ;; Negative w disables clipping, zero clips sharply, positive w feathers.
    ;; Both edges are continuous within triangles, never quantized to geometry.
    (define (scene-module-source vertex fragment)
      (string-append
       "struct Scene { view_projection: mat4x4f, sun: vec4f, ambient: vec4f, motion: vec4f, reveal: vec4f };\n"
       "@group(0) @binding(0) var<uniform> scene: Scene;\n"
       "struct VertexInput { @location(0) position: vec3f, @location(1) normal: vec3f, @location(2) color: vec4f, @location(3) previous: vec3f };\n"
       "struct VertexOutput { @builtin(position) position: vec4f, @location(0) normal: vec3f, @location(1) color: vec4f, @location(2) world: vec2f };\n"
       "fn revealed(world: vec2f) -> f32 {\n"
       "  if (scene.reveal.w < 0.0) { return 1.0; }\n"
       "  let distance = length(world - scene.reveal.xy);\n"
       "  if (scene.reveal.w == 0.0) { return select(0.0, 1.0, distance <= scene.reveal.z); }\n"
       "  return 1.0 - smoothstep(scene.reveal.z - scene.reveal.w, scene.reveal.z + scene.reveal.w, distance);\n}\n"
       "fn lambert(color: vec4f, normal: vec3f) -> vec4f {\n"
       "  let diffuse = max(dot(normalize(normal), scene.sun.xyz), 0.0) * scene.sun.w;\n"
       "  let illumination = mix(scene.ambient.xyz + vec3f(diffuse), vec3f(1.0), color.a);\n"
       "  return vec4f(color.rgb * illumination, scene.ambient.w);\n}\n"
       "@vertex fn vertex_main(source: VertexInput) -> VertexOutput {\n"
       "  var input = source;\n  input.position = mix(source.previous, source.position, scene.motion.x);\n"
       "  var output: VertexOutput;\n  output.position = " (expression-source vertex) ";\n"
       "  output.normal = input.normal;\n  output.color = input.color;\n  output.world = input.position.xy;\n  return output;\n}\n"
       "@fragment fn fragment_main(input: VertexOutput) -> @location(0) vec4f {\n"
       "  let coverage = revealed(input.world);\n  if (coverage <= 0.0) { discard; }\n"
       "  let color = " (expression-source fragment) ";\n"
       "  return vec4f(color.rgb, color.a * coverage);\n}\n"))
    (define (compile-scene-shader vertex fragment)
      (cond ((not (= (expression-width vertex #t #t) 4))
             (compiled-shader #f "scene vertex expression must produce vec4; project accepts vec3"))
            ((not (= (expression-width fragment #f #t) 4))
             (compiled-shader #f "scene fragment expression must produce vec4; lambert accepts color and normal"))
            (else (compiled-shader #t (scene-module-source vertex fragment)))))))
