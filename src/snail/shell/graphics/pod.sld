;; Plain old data: values laid out as WGSL lays out its types in buffers,
;; so bytes packed here read in a shader as the struct it declares. A
;; record deriving Pod is one source of truth for a shader interface: its
;; Shape gives the WGSL declaration, its size and alignment, and its
;; vertex attributes, and `pack` writes a list of its values.
;;
;;   (record Vertex
;;     ((position Vec3f)
;;      (uv Vec2f))
;;     (deriving Pod))
;;
;;   (define vertex-shape (→ (Shape Vertex)) (shape))
;;   (declarations vertex-shape)   ; "struct Vertex {\n  position: vec3f,\n  uv: vec2f,\n}\n"
;;   (pack vertex-shape (list v0 v1 v2))   ; three 32-byte strides
;;
;; A shape is built by walking the record's fields, so a program keeps
;; each one it uses as a top-level value, made once, and passes it to
;; `pack` and `pod-bytes`.
;;
;; Layouts follow WGSL's rules for storage buffers: a field sits at the
;; next multiple of its alignment, a struct's alignment is its largest
;; field's, and its size is rounded up to that alignment. A vec3 takes 12
;; bytes but aligns to 16, so an F32 may follow it in the same 16.
(define-library (snail shell graphics pod)
  (export
   Pod
   shape
   pod-align
   pod-write
   derive-pod
   Shape
   Layout
   FieldLayout
   Vec2f
   Vec3f
   Vec4f
   Vec2i
   Vec4i
   Mat4x4f
   declarations
   stride
   pack
   pod-bytes
   vertex-layout)
  (import
   (snail core base)
   (snail shell gpu))
  (begin

    ;; ---- Layouts ----

    ;; A type as WGSL writes it, how large it is and where it may start,
    ;; its format as a vertex attribute if it can be one, a struct's
    ;; fields, and the struct declarations it needs, each after those it
    ;; names.
    (record Layout
      ((wgsl String)
       (size I64)
       (align I64)
       (format (Option VertexFormat))
       (fields (List FieldLayout))
       (structs (List String))))

    (record FieldLayout
      ((name String)
       (offset I64)
       (layout Layout)))

    ;; The layout of T, which `shape` finds by the type alone.
    (record (Shape T)
      ((layout Layout)))

    ;; `pod-write` writes a value at `at`, already aligned, and answers
    ;; where it ends; `pod-align` is the alignment its type has, read from
    ;; a value so that writing never builds a Shape.
    (typeclass (Pod T)
      (declare (shape) (→ (Shape T)))
      (declare (pod-align (value T)) (→ I64))
      (declare (pod-write (value T) (bytes Bytes) (at I64)) (→ I64)))

    (define (align-up (at I64) (align I64)) (→ I64)
      (* (quotient (+ at (- align 1)) align) align))

    (define (scalar-shape (wgsl String) (size I64) (align I64) (format VertexFormat)) (→ (Shape T))
      (∀ (T))
      (new Shape
        (layout (new Layout
                  (wgsl wgsl)
                  (size size)
                  (align align)
                  (format (Some format))
                  (fields (Nil))
                  (structs (Nil))))))

    ;; ---- Structs ----

    ;; The struct `name` with these fields in order: each at the next
    ;; multiple of its alignment, and the size rounded up to the largest.

    (define (struct-shape (record-name String) (fields (List (Pair String Layout))))
      (→ (Shape T))
      (∀ (T))
      (let* ((name (wgsl-name record-name))
             (placed (place-fields fields 0 (Nil)))
             (align (fold-left max 1 (map (lambda (field) (● field layout align)) placed)))
             (end (fold-left max 0 (map field-end placed))))
        (new Shape
          (layout (new Layout
                    (wgsl name)
                    (size (align-up end align))
                    (align align)
                    (format (None))
                    (fields placed)
                    (structs (append (delete-duplicates string=?
                                                        (concatenate
                                                         (map
                                                          (lambda (field) (● field layout structs))
                                                          placed)))
                                     (list (struct-declaration name placed)))))))))

    (define (place-fields (fields (List (Pair String Layout))) (at I64) (placed (List FieldLayout)))
      (→ (List FieldLayout))
      (match fields
        ((Nil) (reverse placed))
        ((Cons field rest)
         (let ((offset (align-up at (● field second align))))
           (place-fields rest
                         (+ offset (● field second size))
                         (Cons (new FieldLayout
                                 (name (● field first))
                                 (offset offset)
                                 (layout (● field second)))
                               placed))))))

    (define (field-end (field FieldLayout)) (→ I64)
      (+ (● field offset) (● field layout size)))

    (define (struct-declaration (name String) (fields (List FieldLayout))) (→ String)
      (string-concatenate
       (concatenate (list (list "struct " name " {\n")
                          (map (lambda (field)
                                 (string-append "  "
                                                (wgsl-name (● field name))
                                                ": "
                                                (● field layout wgsl)
                                                ",\n"))
                               fields)
                          (list "}\n")))))

    ;; WGSL spells hyphens in record and field names as underscores.
    (define (wgsl-name (name String)) (→ String)
      (list->string (map (lambda (c) (if (char=? c #\-) #\_ c)) (string->list name))))

    ;; A derived field: its label and the layout of its type.

    (define (field-layout (name String) (shape (Shape F))) (→ (Pair String Layout)) (∀ (F))
      (new Pair (first name) (second (● shape layout))))

    ;; Each field at the next multiple of its alignment.

    (define (place (value T) (bytes Bytes) (at I64)) (→ I64) (∀ (T)) (⊨ (Pod T))
      (pod-write value bytes (align-up at (pod-align value))))

    ;; A record of Pod fields, without parameters, derives Pod.

    (define-syntax derive-pod
      (syntax-rules (record)
        ((_ record (name) (case text (field label label-text type) ...))
         (instance (Pod name)
           (define shape
             (lambda ()
               (struct-shape text
                             (list (field-layout label-text ((lambda () (→ (Shape type)) (shape))))
                                   ...))))
           (define pod-align
             (lambda (value)
               (match value
                 ((case field ...) (fold-left max 1 (list (pod-align field) ...))))))
           (define pod-write
             (lambda (value bytes at)
               (match value
                 ((case field ...)
                  (let* ((end at) (end (place field bytes end)) ...)
                    (align-up end (pod-align value)))))))))))

    ;; ---- Packing ----

    (define (declarations (shape (Shape T))) (→ String) (∀ (T))
      (string-concatenate (● shape layout structs)))

    ;; The distance between neighbours in an array of T.

    (define (stride (shape (Shape T))) (→ I64) (∀ (T))
      (align-up (● shape layout size) (● shape layout align)))

    ;; The bytes are local to this call, so packing is pure.

    (define (pack (shape (Shape T)) (values (List T))) (→ Bytes) (∀ (T)) (⊨ (Pod T))
      (let* ((step (stride shape))
             (bytes (make-array (* step (length values)) (i32->u8 0))))
        (fold-left
         (lambda (at value) (pod-write value bytes at) (+ at step))
         0
         values)
        bytes))

    ;; One value, as a uniform buffer holds it.

    (define (pod-bytes (shape (Shape T)) (value T)) (→ Bytes) (∀ (T)) (⊨ (Pod T))
      (pack shape (list value)))

    ;; A vertex buffer of T: each field an attribute, at consecutive
    ;; locations from `first`. Every field must have a vertex format.

    (define (vertex-layout (shape (Shape T)) (step VertexStep) (first I32)) (→ VertexBufferLayout)
      (∀ (T))
      (new VertexBufferLayout
        (stride (i64->i32 (stride shape)))
        (step step)
        (attributes (map-indexed (lambda (index field)
                                   (new VertexAttribute
                                     (format (attribute-format (● shape layout wgsl) field))
                                     (offset (i64->i32 (● field offset)))
                                     (location (+ first (i64->i32 index)))))
                                 (● shape layout fields)))))

    (define (attribute-format (struct String) (field FieldLayout)) (→ VertexFormat)
      (match (● field layout format)
        ((Some format) format)
        ((None)
         (panic (string-append "pod: field "
                               (● field name)
                               " of "
                               struct
                               " is a "
                               (● field layout wgsl)
                               ", which no vertex attribute holds")))))

    ;; ---- Scalars ----

    (define (write-word (bytes Bytes) (at I64) (word I32)) (→ I64)
      (for-each (lambda (index)
                  (array-set! bytes
                              (+ at index)
                              (i32->u8
                               (i32-and (i32-shift-right/logical word (i64->i32 (* 8 index)))
                                        255))))
                (iota 4))
      (+ at 4))

    (instance (Pod F32)
      (define shape (lambda () (scalar-shape "f32" 4 4 (Float32))))
      (define pod-align (lambda (value) 4))
      (define pod-write (lambda (value bytes at) (write-word bytes at (f32->bits value)))))

    (instance (Pod I32)
      (define shape (lambda () (scalar-shape "i32" 4 4 (Sint32))))
      (define pod-align (lambda (value) 4))
      (define pod-write (lambda (value bytes at) (write-word bytes at value))))

    ;; ---- Vectors and matrices ----

    ;; WGSL's own types, as records: their layouts are WGSL's, not those
    ;; of structs with the same fields.
    (record Vec2f
      ((x F32)
       (y F32))
      (deriving Repr))

    (record Vec3f
      ((x F32)
       (y F32)
       (z F32))
      (deriving Repr))

    (record Vec4f
      ((x F32)
       (y F32)
       (z F32)
       (w F32))
      (deriving Repr))

    (record Vec2i
      ((x I32)
       (y I32))
      (deriving Repr))

    (record Vec4i
      ((x I32)
       (y I32)
       (z I32)
       (w I32))
      (deriving Repr))

    ;; Four columns, as WGSL stores a matrix.
    (record Mat4x4f
      ((x Vec4f)
       (y Vec4f)
       (z Vec4f)
       (w Vec4f))
      (deriving Repr))

    (define (words (bytes Bytes) (at I64) (values (List I32))) (→ I64)
      (fold-left (lambda (at value) (write-word bytes at value)) at values))

    (define (floats (bytes Bytes) (at I64) (values (List F32))) (→ I64)
      (words bytes at (map f32->bits values)))

    (instance (Pod Vec2f)
      (define shape (lambda () (scalar-shape "vec2f" 8 8 (Float32x2))))
      (define pod-align (lambda (value) 8))
      (define pod-write
        (lambda (value bytes at) (floats bytes at (list (● value x) (● value y))))))

    (instance (Pod Vec3f)
      (define shape (lambda () (scalar-shape "vec3f" 12 16 (Float32x3))))
      (define pod-align (lambda (value) 16))
      (define pod-write
        (lambda (value bytes at)
          (floats bytes at (list (● value x) (● value y) (● value z))))))

    (instance (Pod Vec4f)
      (define shape (lambda () (scalar-shape "vec4f" 16 16 (Float32x4))))
      (define pod-align (lambda (value) 16))
      (define pod-write
        (lambda (value bytes at)
          (floats bytes at (list (● value x) (● value y) (● value z) (● value w))))))

    (instance (Pod Vec2i)
      (define shape (lambda () (scalar-shape "vec2i" 8 8 (Sint32x2))))
      (define pod-align (lambda (value) 8))
      (define pod-write
        (lambda (value bytes at) (words bytes at (list (● value x) (● value y))))))

    (instance (Pod Vec4i)
      (define shape (lambda () (scalar-shape "vec4i" 16 16 (Sint32x4))))
      (define pod-align (lambda (value) 16))
      (define pod-write
        (lambda (value bytes at)
          (words bytes at (list (● value x) (● value y) (● value z) (● value w))))))

    ;; A matrix is no vertex attribute; an instance's transform is four.

    (instance (Pod Mat4x4f)
      (define shape
        (lambda ()
          (new Shape
            (layout (new Layout
                      (wgsl "mat4x4f")
                      (size 64)
                      (align 16)
                      (format (None))
                      (fields (Nil))
                      (structs (Nil)))))))
      (define pod-align (lambda (value) 16))
      (define pod-write
        (lambda (value bytes at)
          (fold-left (lambda (at column) (pod-write column bytes at))
                     at
                     (list (● value x) (● value y) (● value z) (● value w))))))

    ))
