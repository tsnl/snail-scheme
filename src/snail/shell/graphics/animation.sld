;; A clip edits local transforms. The hierarchy places those transforms in
;; the instance, then inverse binds carry rest vertices to their posed joints.
(define-library (snail shell graphics animation)
  (export Transform Rig RigNode Joint Track Clip Property Translation Rotation Scale
          Interpolation
          Stepped
          Linear
          SkinBinding
          rigid-binding
          Influence
          v4
          unit-matrix
          matrix-from
          sample-pose
          blend-poses
          blend-branch
          named-branch
          named-node
          posed-nodes
          skin-palette
          matrix-product
          joint-palette
          clip-time
          rigid-influence
          shift-influence)
  (import
   (snail core base)
   (only (snail shell math) sin acos)
   (snail shell graphics pod))
  (begin
    (define (v4 (x F32) (y F32) (z F32) (w F32)) (→ Vec4f)
      (new Vec4f (x x) (y y) (z z) (w w)))
    (define unit-matrix (→ Mat4x4f)
      (new Mat4x4f (x (v4 1.0 0.0 0.0 0.0)) (y (v4 0.0 1.0 0.0 0.0))
           (z (v4 0.0 0.0 1.0 0.0)) (w (v4 0.0 0.0 0.0 1.0))))
    (define (matrix-from (values (List F64))) (→ Mat4x4f)
      (let ((a (list->array (map f64->f32 values))))
        (let ((col (lambda ((i I64)) (→ Vec4f)
                     (v4 (array-ref a i)
                         (array-ref a (+ i 1))
                         (array-ref a (+ i 2))
                         (array-ref a (+ i 3))))))
          (new Mat4x4f (x (col 0)) (y (col 4)) (z (col 8)) (w (col 12))))))

    (define (times (a Vec4f) (k F32)) (→ Vec4f)
      (v4 (* k (● a x)) (* k (● a y)) (* k (● a z)) (* k (● a w))))
    (define (plus (a Vec4f) (b Vec4f)) (→ Vec4f)
      (v4 (+ (● a x) (● b x)) (+ (● a y) (● b y)) (+ (● a z) (● b z)) (+ (● a w) (● b w))))
    (define (dot4 (a Vec4f) (b Vec4f)) (→ F32)
      (+ (+ (* (● a x) (● b x)) (* (● a y) (● b y)))
         (+ (* (● a z) (● b z)) (* (● a w) (● b w)))))
    (define (product-column (a Mat4x4f) (v Vec4f)) (→ Vec4f)
      (plus (plus (times (● a x) (● v x)) (times (● a y) (● v y)))
            (plus (times (● a z) (● v z)) (times (● a w) (● v w)))))
    (define (matrix-product (a Mat4x4f) (b Mat4x4f)) (→ Mat4x4f)
      (new Mat4x4f (x (product-column a (● b x))) (y (product-column a (● b y)))
           (z (product-column a (● b z))) (w (product-column a (● b w)))))

    ;; ---- Local poses ----

    (record Transform
      ((translation Vec4f)
       (rotation Vec4f)
       (scale Vec4f)))
    (define (matrix-of (t Transform)) (→ Mat4x4f)
      (let* ((q (● t rotation)) (x (● q x)) (y (● q y)) (z (● q z)) (w (● q w)) (s (● t scale))
             (p (● t translation)))
        (new Mat4x4f
          (x (times (v4 (- 1.0 (* 2.0 (+ (* y y) (* z z)))) (* 2.0 (+ (* x y) (* z w)))
                        (* 2.0 (- (* x z) (* y w))) 0.0) (● s x)))
          (y (times (v4 (* 2.0 (- (* x y) (* z w))) (- 1.0 (* 2.0 (+ (* x x) (* z z))))
                        (* 2.0 (+ (* y z) (* x w))) 0.0) (● s y)))
          (z (times (v4 (* 2.0 (+ (* x z) (* y w))) (* 2.0 (- (* y z) (* x w)))
                        (- 1.0 (* 2.0 (+ (* x x) (* y y)))) 0.0) (● s z)))
          (w (v4 (● p x) (● p y) (● p z) 1.0)))))

    (record RigNode
      ((name String)
       (node I64)
       (parent I64)
       (fixed (Option Mat4x4f))))
    (record Joint
      ((node I64)
       (inverse-bind Mat4x4f)))
    (record Rig
      ((rest (Array Transform))
       (hierarchy (List RigNode))
       (joints (List Joint))))
    (enum Property (Translation) (Rotation) (Scale))
    (enum Interpolation (Stepped) (Linear))
    (record Track
      ((node I64)
       (property Property)
       (rule Interpolation)
       (times (Array F64))
       (values (Array Vec4f))))
    (record Clip
      ((name String)
       (duration F64)
       (tracks (List Track))))

    (define (lerp (a Vec4f) (b Vec4f) (t F32)) (→ Vec4f)
      (plus (times a (- 1.0 t)) (times b t)))
    ;; q and -q encode the same rotation. Take the short arc, with normalized
    ;; lerp near coincident keys to avoid dividing by the sine of zero.
    (define (slerp (a Vec4f) (b Vec4f) (t F32)) (→ Vec4f)
      (let* ((dot (dot4 a b)) (end (if (< dot 0.0) (times b -1.0) b)) (c (min 1.0 (abs dot))))
        (if (> c 0.9995)
            (let ((q (lerp a end t))) (times q (/ 1.0 (sqrt (dot4 q q)))))
            (let* ((angle (acos (f32->f64 c))) (part (* angle (f32->f64 t))) (size (sin angle)))
              (plus (times a (f64->f32 (/ (sin (- angle part)) size)))
                    (times end (f64->f32 (/ (sin part) size))))))))

    (define (clip-time (clip Clip) (seconds F64) (looping Bool)) (→ F64)
      (let ((d (● clip duration)))
        (if (and looping (> d 0.0))
            (- seconds (* d (floor (/ seconds d))))
            (max 0.0 (min seconds d)))))

    ;; With at least two keys, find the last one at or before t.
    (define (left-key (keys (Array F64)) (t F64) (lo I64) (hi I64)) (→ I64)
      (let ((mid (quotient (+ lo hi) 2)))
        (cond ((<= (- hi lo) 1) lo)
              ((<= (array-ref keys mid) t) (left-key keys t mid hi))
              (else (left-key keys t lo mid)))))
    (define (sample-track (track Track) (t F64)) (→ Vec4f)
      (let* ((keys (● track times)) (vs (● track values)) (end (- (array-length keys) 1)))
        (cond ((<= t (array-ref keys 0)) (array-ref vs 0))
              ((>= t (array-ref keys end)) (array-ref vs end))
              (else (let* ((i (left-key keys t 0 end)) (a (array-ref vs i)))
                      (match (● track rule)
                        ((Stepped) a)
                        ((Linear)
                         (let* ((start (array-ref keys i))
                                (f (f64->f32 (/ (- t start) (- (array-ref keys (+ i 1)) start)))))
                           ((match (● track property) ((Rotation) slerp) (_ lerp))
                            a (array-ref vs (+ i 1)) f)))))))))

    ;; The asset is shared. Only the new pose's array is written.
    (define (sample-pose (rig Rig) (clip Clip) (t F64)) (→ (Array Transform))
      (let ((pose (array-copy (● rig rest))))
        (for-each (lambda (track)
                    (let* ((i (● track node)) (local (array-ref pose i)) (v (sample-track track t)))
                      (array-set! pose i
                                  (match (● track property)
                                    ((Translation) (Transform-translation-set local v))
                                    ((Rotation) (Transform-rotation-set local v))
                                    ((Scale) (Transform-scale-set local v)))))) (● clip tracks))
        pose))
    (define (blend-local (u Transform) (v Transform) (t F32)) (→ Transform)
      (cond ((<= t 0.0) u) ((>= t 1.0) v)
            (else (new Transform (translation (lerp (● u translation) (● v translation) t))
                       (scale (lerp (● u scale) (● v scale) t))
                       (rotation (slerp (● u rotation) (● v rotation) t))))))
    (define (blend-poses (a (Array Transform)) (b (Array Transform)) (t F32)) (→ (Array Transform))
      (cond ((<= t 0.0) a) ((>= t 1.0) b)
            (else (array-generate (array-length a)
                                  (lambda (i) (blend-local (array-ref a i) (array-ref b i) t))))))
    (define (named-node (rig Rig) (name String)) (→ (Option I64))
      (match (find (lambda (link) (string=? (● link name) name)) (● rig hierarchy))
        ((Some link) (Some (● link node))) (_ (None))))
    (define (named-branch (rig Rig) (name String)) (→ (List I64))
      (let ((selected (make-array (array-length (● rig rest)) #f)))
        (reverse (fold-left (lambda (found link)
                              (let ((p (● link parent)) (i (● link node)))
                                (if (or (string=? (● link name) name)
                                        (and (>= p 0) (array-ref selected p)))
                                    (begin (array-set! selected i #t) (Cons i found)) found)))
                            (Nil)
                            (● rig hierarchy)))))
    (define (blend-branch (a (Array Transform)) (b (Array Transform)) (t F32) (branch (List I64)))
      (→ (Array Transform))
      (let ((pose (array-copy a)))
        (for-each (lambda (i) (array-set! pose i (blend-local (array-ref a i) (array-ref b i) t)))
                  branch)
        pose))

    ;; ---- Skinning ----

    ;; Parents precede children, including ancestors which are not joints.
    ;; Applying the instance at each root keeps inverse binds in model space.
    (define (posed-nodes (rig Rig) (pose (Array Transform)) (instance Mat4x4f)) (→ (Array Mat4x4f))
      (let ((world (make-array (array-length pose) unit-matrix)))
        (for-each (lambda (link)
                    (let ((parent (● link parent)) (i (● link node)))
                      (array-set! world i (matrix-product
                                           (if (< parent 0) instance (array-ref world parent))
                                           (match (● link fixed)
                                             ((Some m) m)
                                             ((None) (matrix-of (array-ref pose i))))))))
                  (● rig hierarchy))
        world))
    (define (skin-palette (rig Rig) (world (Array Mat4x4f))) (→ (List Mat4x4f))
      (map
       (lambda (joint) (matrix-product (array-ref world (● joint node)) (● joint inverse-bind)))
       (● rig joints)))
    (define (joint-palette (rig Rig) (pose (Array Transform)) (instance Mat4x4f)) (→ (List Mat4x4f))
      (skin-palette rig (posed-nodes rig pose instance)))

    (record Influence
      ((joints Vec4i)
       (weights Vec4f))
      (deriving Pod))
    ;; A mesh instance consumes consecutive palette slots. Indices in the
    ;; mesh stay local, so the same binding can be used for several actors.
    (record SkinBinding
      ((slots I64)
       (vertices (List Influence))))
    (define (rigid-binding (count I64)) (→ SkinBinding)
      (unless (> count 0) (panic "invalid moving vertex range"))
      (let ((v (rigid-influence 0)))
        (new SkinBinding (slots 1) (vertices (map (lambda (_) v) (iota count))))))
    (define (rigid-influence (slot I32)) (→ Influence)
      (new Influence (joints (new Vec4i (x slot) (y slot) (z slot) (w slot)))
           (weights (v4 1.0 0.0 0.0 0.0))))
    (define (shift-influence (influence Influence) (base I32)) (→ Influence)
      (let ((j (● influence joints)))
        (Influence-joints-set influence
                              (new Vec4i (x (+ base (● j x))) (y (+ base (● j y)))
                                   (z (+ base (● j z))) (w (+ base (● j w)))))))))
