;; A small glTF scene read: two buffers laid end to end, an interleaved
;; view and a packed one, a node turned a quarter about y and moved above
;; its parent, which scales by 2, and a masked, emissive material; the
;; second buffer a data: URI, the second image in a buffer view. Then a
;; GLB file, its JSON naming the binary chunk and a padded data: URI, and
;; scenes that cannot be read, each with why.
(import
 (snail core base)
 (snail core io)
 (snail shell utf8)
 (snail shell graphics gltf))

(define scene
  (→ String)
  (string-append
   "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,\"scenes\":[{\"nodes\":[0]}],"
   "\"nodes\":[{\"scale\":[2,2,2],\"children\":[1]},"
   "{\"rotation\":[0,0.7071067811865476,0,0.7071067811865476],\"translation\":[0,1,0],\"mesh\":0}],"
   "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"TEXCOORD_0\":1},\"indices\":2,\"material\":0},"
   "{\"attributes\":{\"POSITION\":0},\"mode\":1}]}],"
   "\"materials\":[{\"pbrMetallicRoughness\":{\"baseColorFactor\":[1,0.5,0.25,1],\"baseColorTexture\":{\"index\":0},"
   "\"metallicFactor\":0},\"alphaMode\":\"MASK\",\"alphaCutoff\":0.25,\"emissiveFactor\":[1,1,0],"
   "\"extensions\":{\"KHR_materials_emissive_strength\":{\"emissiveStrength\":4.5}}}],"
   "\"textures\":[{\"source\":1}],\"images\":[{\"uri\":\"a.png\"},{\"bufferView\":1,\"mimeType\":\"image/png\"}],"
   "\"buffers\":[{\"uri\":\"one.bin\",\"byteLength\":61},"
   "{\"uri\":\"data:application/octet-stream;base64,AAECAwQF\",\"byteLength\":6}],"
   "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":60,\"byteStride\":20},"
   "{\"buffer\":1,\"byteOffset\":0,\"byteLength\":6}],"
   "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\","
   "\"min\":[-1,0,0],\"max\":[1,1,0]},"
   "{\"bufferView\":0,\"byteOffset\":12,\"componentType\":5126,\"count\":3,\"type\":\"VEC2\"},"
   "{\"bufferView\":1,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}]}"))

(define (source-text (source Source)) (→ String)
  (match source
    ((FileSource path) path)
    ((DataSource bytes) (string-append "data " (bytes-text bytes)))
    ((ViewSource buffer offset length)
     (string-join (map show (list buffer offset length)) " "))))

(define (bytes-text (bytes Bytes)) (→ String)
  (string-join (map (lambda (byte) (show (u8->i32 byte))) (array->list bytes)) " "))

(define (sources (gltf-sources (List Source))) (→ String)
  (string-join (map source-text gltf-sources) ", "))

;; A GLB file: its header, then its JSON chunk padded with spaces and its
;; binary chunk, each after its length and type.
(define (glb (json String) (bin Bytes)) (→ Bytes)
  (let* ((padded (string-append json
                                (make-string (remainder (- 4 (remainder (string-length json) 4)) 4)
                                             #\space)))
         (text (string->utf8 padded)))
    (array-concatenate (list (string->utf8 "glTF")
                             (word 2)
                             (word (+ 28 (+ (array-length text) (array-length bin))))
                             (word (array-length text))
                             (string->utf8 "JSON")
                             text
                             (word (array-length bin))
                             (string->utf8 "BIN")
                             (make-array 1 (i32->u8 0))
                             bin))))

(define (word (value I64)) (→ Bytes)
  (array-generate 4
                  (lambda (index)
                    (i32->u8 (i64->i32 (remainder (quotient value (expt 256 index)) 256))))))

(define (expt (base I64) (power I64)) (→ I64) (if (= power 0) 1 (* base (expt base (- power 1)))))

(define (attribute-text (attribute Attribute)) (→ String)
  (string-join (map show
                    (list (● attribute offset)
                          (● attribute stride)
                          (● attribute component)
                          (● attribute count)))
               " "))

(define (numbers (values (List F64))) (→ String)
  (string-join (map (lambda (value) (show (/ (round (* value 1000.0)) 1000.0))) values) " "))

(define (read (file Bytes)) (→ (Result Gltf String))
  (attempt-reading (lambda () (read-gltf file "models/x/"))))

(define (buffers (gltf Gltf)) (→ String)
  (string-join (map (lambda (buffer)
                      (string-append (source-text (● buffer source))
                                     " at "
                                     (show (● buffer start))
                                     " for "
                                     (show (● buffer length))))
                    (● gltf buffers))
               ", "))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (match (read (string->utf8 scene))
  ((Ok gltf)
   (write-line out (string-append "buffers: " (buffers gltf) " size " (show (● gltf size))))
   (write-line out (string-append "images: " (sources (● gltf images))))
   (for-each (lambda (placed)
               (let ((primitive (● placed primitive)))
                 (write-line out (string-append "positions: " (attribute-text (● primitive positions))))
                 (match (● primitive uvs)
                   ((Some uvs) (write-line out (string-append "uvs: " (attribute-text uvs))))
                   ((None) (write-line out "uvs: none")))
                 (match (● primitive indices)
                   ((Some indices)
                    (write-line out (string-append "indices: " (attribute-text indices))))
                   ((None) (write-line out "indices: none")))
                 (write-line out (string-append "matrix: " (numbers (● placed matrix))))))
             (● gltf placed))
   (for-each (lambda (material)
               (write-line out (string-append "material: " (numbers (● material base-color))
                                          " texture " (show (● material base-texture))
                                          " metallic " (show (● material metallic))
                                          " alpha " (show (● material alpha))
                                          " cutoff " (show (● material alpha-cutoff))
                                          " emissive " (numbers (● material emissive)))))
             (● gltf materials))
   (let ((bounds (gltf-bounds gltf)))
     (write-line out
      (string-append "bounds: " (numbers (● bounds first)) " to " (numbers (● bounds second))))))
  ((Err reason) (write-line out reason)))
  (match (read two-buffers)
  ((Ok gltf) (write-line out (string-append "glb buffers: " (buffers gltf))))
  ((Err reason) (write-line out reason)))
  (for-each (lambda (file)
            (match (read file)
              ((Ok _) (write-line out "read"))
              ((Err reason) (write-line out reason))))
          (list (string->utf8 "glTF, but not JSON")
                (subarray two-buffers 0 40)
                (string->utf8
                 "{\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":3}}]}]}")
                (string->utf8 "{\"scene\":2,\"scenes\":[{\"nodes\":[0]}]}")
                (string->utf8 "{\"scenes\":[{\"nodes\":[5]}],\"nodes\":[{}]}")
                (string->utf8
                 "{\"scenes\":[{\"nodes\":[0]}],\"nodes\":[{\"children\":[1]},{\"children\":[0]}]}")
                (string->utf8
                 (string-append
                  "{\"buffers\":[{\"uri\":\"a.bin\",\"byteLength\":30}],"
                  "\"bufferViews\":[{\"buffer\":0,\"byteLength\":30}],"
                  "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}]}"))
                (string->utf8 "{\"images\":[{\"bufferView\":0}]}")
                (string->utf8 "{\"images\":[{\"mimeType\":\"image/png\"}]}")
                (string->utf8 "{\"extensionsRequired\":[\"KHR_draco_mesh_compression\"]}")))
  (unit))

(define two-buffers
  (→ Bytes)
  (glb
   "{\"buffers\":[{\"byteLength\":4},{\"uri\":\"data:application/octet-stream;base64,AQI=\",\"byteLength\":2}]}"
   (list->array (map i32->u8 (list 9 8 7 6)))))


;; Each scene that cannot be read, and why.
