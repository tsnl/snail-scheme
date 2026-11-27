;; A resident model owns its scene and optional skin. A trace stores the glTF
;; accessors, materials and placements alongside the exact input buffer bytes.
(define-library (snail shell graphics renderer model)
  (export ModelResource make-model-resource release-model! model-command restore-model)
  (import
   (snail core base)
   (snail shell json)
   (snail shell wire)
   (snail shell gpu)
   (snail shell graphics api-trace)
   (snail shell graphics gltf)
   (snail shell graphics forward lights)
   (snail shell graphics forward scene))
  (begin
    (record ModelResource
      ((scene Scene)
       (moving (Option MovingScene))))
    (record BufferLayout
      ((start I64)
       (length I64)) (deriving Serialize Deserialize))
    (record ModelLayout
      ((buffers (List BufferLayout))
       (size I64)
       (images (List ImageSource))
       (materials (List Material))
       (placements (List Placed))
       (lights (List Punctual))
       (light-capacity I64)
       (skin-joints I64)
       (skin-vertices I64))
      (deriving Serialize Deserialize))
    (enum ImageSource
      (ImageBlock ((index I64)))
      (BufferImage ((buffer I64) (offset I64) (size I64)))
      (deriving Serialize Deserialize))

    (define (make-model-resource (gpu Gpu) (g Gltf) (buffers (List Bytes))
                                 (files (List (Pair String Bytes))) (images (Option SceneImages))
                                 (skin (Option SkinLayout)) (lights (List Punctual)) (capacity I64))
      (→ ModelResource)
      (let ((s (upload-resolved gpu g buffers files images lights capacity)))
        (match skin
          ((Some layout) (let ((m (skin-with-layout gpu s layout)))
                           (new ModelResource (scene (● m scene)) (moving (Some m)))))
          ((None) (new ModelResource (scene s) (moving (None)))))))
    (define (release-model! (gpu Gpu) (r ModelResource)) (→ Unit)
      (match (● r moving) ((Some m) (release-moving-scene gpu m))
             ((None) (release-scene gpu (● r scene)))))

    ;; Buffer-view images already live in one of the vertex or index payloads.
    (define (image-sources (images (List Source))
                           (files (List (Pair String Bytes)))
                           (buffers (List Bytes)))
      (→ (Pair (List ImageSource) (List Bytes)))
      (let loop ((left images) (index (+ 1 (length buffers))) (sources (Nil)) (extra (Nil)))
        (match left
          ((Nil) (new Pair (first (reverse sources)) (second (reverse extra))))
          ((Cons im rest)
           (match im
             ((ViewSource n at size) (loop rest index (Cons (BufferImage n at size) sources) extra))
             (_ (loop rest (+ index 1) (Cons (ImageBlock index) sources)
                      (Cons (source-bytes im files buffers) extra))))))))
    (define (model-command (id I64) (g Gltf) (buffers (List Bytes))
                           (files (List (Pair String Bytes))) (skin (Option SkinLayout))
                           (lights (List Punctual)) (capacity I64)) (→ ApiCommand)
                           (let* ((images (image-sources (● g images) files buffers))
                                  (layout (new ModelLayout (size (● g size))
                                               (buffers (map (lambda (b)
                                                               (new BufferLayout
                                                                 (start (● b start))
                                                                 (length (● b length))))
                                                             (● g buffers)))
                                               (images (● images first))
                                               (materials (● g materials))
                                               (placements (● g placed))
                                               (lights lights) (light-capacity capacity)
                                               (skin-joints
                                                (match skin ((Some s) (● s joints)) (_ 0)))
                                               (skin-vertices
                                                (match skin ((Some s) (● s vertices)) (_ 0))))))
                             (new ApiCommand (op "createModel")
                                  (args (trace-object (list (trace-field "id" (JsonInteger id))
                                                            (trace-field "primitives"
                                                                         (JsonInteger
                                                                          (length (● g placed))))
                                                            (trace-field "materials"
                                                                         (JsonInteger (length (● g
                                                                                                 materials)))))))
                                  (blocks (Cons (serialize layout)
                                                (append buffers
                                                        (append (● images second)
                                                                (match skin
                                                                  ((Some s) (list (● s bytes)))
                                                                  (_ (Nil))))))))))
    (define (restore-model (gpu Gpu) (cmd ApiCommand)) (→ ModelResource)
      (let* ((layout (ann (command-value cmd 0) ModelLayout))
             (_ (unless (> (length (● cmd blocks)) (length (● layout buffers)))
                  (panic "missing renderer mesh buffers")))
             (raw (take (list-tail (● cmd blocks) 1) (length (● layout buffers))))
             (buffers (map (lambda (pair)
                             (let ((b (● pair first)) (bytes (● pair second)))
                               (unless (and (>= (● b start) 0)
                                            (= (● b length) (array-length bytes))
                                            (<= (+ (● b start) (● b length)) (● layout size)))
                                 (panic "invalid renderer mesh buffer"))
                               (new Buffer
                                 (source (DataSource bytes))
                                 (start (● b start))
                                 (length (● b length)))))
                           (zip (● layout buffers) raw)))
             (images (map (lambda (im) (match im ((ImageBlock n) (DataSource (command-block cmd n)))
                                              ((BufferImage n at size) (ViewSource n at size))))
                          (● layout images)))
             (g (new Gltf (buffers buffers) (size (● layout size)) (images images)
                     (materials (● layout materials)) (placed (● layout placements))))
             (skin (if (= (● layout skin-joints) 0) (None)
                       (Some (new SkinLayout
                               (bytes (command-block cmd (- (length (● cmd blocks)) 1)))
                               (joints (● layout skin-joints))
                               (vertices (● layout skin-vertices)))))))
        (make-model-resource gpu
                             g
                             raw
                             (Nil)
                             (None)
                             skin
                             (● layout lights)
                             (● layout light-capacity))))))
