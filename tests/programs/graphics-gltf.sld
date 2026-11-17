;; A small glTF scene read: two buffers laid end to end, an interleaved
;; view and a packed one, a node turned a quarter about y and moved above
;; its parent, which scales by 2, and a masked, emissive material.
(import
 (snail core base)
 (snail core io)
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
   "\"textures\":[{\"source\":1}],\"images\":[{\"uri\":\"a.png\"},{\"uri\":\"b.jpg\"}],"
   "\"buffers\":[{\"uri\":\"one.bin\",\"byteLength\":61},{\"uri\":\"two.bin\",\"byteLength\":6}],"
   "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":60,\"byteStride\":20},"
   "{\"buffer\":1,\"byteOffset\":0,\"byteLength\":6}],"
   "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\","
   "\"min\":[-1,0,0],\"max\":[1,1,0]},"
   "{\"bufferView\":0,\"byteOffset\":12,\"componentType\":5126,\"count\":3,\"type\":\"VEC2\"},"
   "{\"bufferView\":1,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}]}"))

(define (attribute-text (attribute Attribute)) (→ String)
  (string-join (map show
                    (list (● attribute offset)
                          (● attribute stride)
                          (● attribute component)
                          (● attribute count)))
               " "))

(define (numbers (values (List F64))) (→ String)
  (string-join (map (lambda (value) (show (/ (round (* value 1000.0)) 1000.0))) values) " "))

(match (read-gltf scene "models/x/")
  ((Ok gltf)
   (write-line
    (string-append "buffers: " (string-join (● gltf buffers) " ") " size " (show (● gltf size))))
   (write-line (string-append "images: " (string-join (● gltf images) " ")))
   (for-each (lambda (placed)
               (let ((primitive (● placed primitive)))
                 (write-line (string-append "positions: " (attribute-text (● primitive positions))))
                 (match (● primitive uvs)
                   ((Some uvs) (write-line (string-append "uvs: " (attribute-text uvs))))
                   ((None) (write-line "uvs: none")))
                 (match (● primitive indices)
                   ((Some indices)
                    (write-line (string-append "indices: " (attribute-text indices))))
                   ((None) (write-line "indices: none")))
                 (write-line (string-append "matrix: " (numbers (● placed matrix))))))
             (● gltf placed))
   (for-each (lambda (material)
               (write-line (string-append "material: " (numbers (● material base-color))
                                          " texture " (show (● material base-texture))
                                          " metallic " (show (● material metallic))
                                          " alpha " (show (● material alpha))
                                          " cutoff " (show (● material alpha-cutoff))
                                          " emissive " (numbers (● material emissive)))))
             (● gltf materials))
   (let ((bounds (gltf-bounds gltf)))
     (write-line
      (string-append "bounds: " (numbers (● bounds first)) " to " (numbers (● bounds second))))))
  ((Err reason) (write-line reason)))
