;; The mean squared distance from each point to its three nearest others,
;; by brute force: a workgroup takes 256 points at a time into workgroup
;; memory and each invocation keeps its three smallest distances, as 3D
;; Gaussian Splatting's initialization does to size each gaussian. COUNT
;; comes first, from (snail shell graphics splat-fit).
((var storage read) (@group 0) (@binding 0) (points (array f32)))

((var storage read_write) (@group 0) (@binding 1) (distances (array f32)))

((var workgroup) (batch (array vec3f 256)))

(fn point ((i u32)) (-> vec3f)
    (return (vec3f (at points (* 3u i)) (at points (+ (* 3u i) 1u)) (at points (+ (* 3u i) 2u)))))

(fn (@compute)
    (@workgroup_size 256)
    nearest_three
    (((@builtin workgroup_id) wid vec3u)
     ((@builtin num_workgroups) nwg vec3u)
     ((@builtin local_invocation_index) t u32))
    (let i (+ (* (+ (* (get wid y) (get nwg x)) (get wid x)) 256u) t))
    (let p (point (min i (- COUNT 1u))))
    (var best (vec3f 3.0e38))
    (for ((var start 0u) (< start COUNT) (+= start 256u))
         (if ((< (+ start t) COUNT) (= (at batch t) (point (+ start t)))))
         (workgroupBarrier)
         (for ((var j 0u) (< j (min 256u (- COUNT start))) (+= j 1u))
              (if ((!= (+ start j) i)
                   (let d (- (at batch j) p))
                   (let squared (dot d d))
                   (if ((< squared (get best x)) (= best (vec3f squared (get best x) (get best y))))
                       ((< squared (get best y)) (= best (vec3f (get best x) squared (get best y))))
                       ((< squared (get best z)) (= (get best z) squared))))))
         (workgroupBarrier))
    (if ((< i COUNT) (= (at distances i) (/ (+ (get best x) (get best y) (get best z)) 3.0)))))
