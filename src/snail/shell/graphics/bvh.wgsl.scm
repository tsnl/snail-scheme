;; Bounding volume hierarchies built on the device, top down by the
;; surface area heuristic, as a CPU builder splits a node: bin its
;; primitives' centroids along each axis, price every boundary between
;; bins by the boxes and counts on its two sides, and split at the
;; cheapest, or keep the node as a leaf when no split pays for the step a
;; walk takes into it (Wald, "On fast Construction of SAH-based Bounding
;; Volume Hierarchies", 2007).
;;
;; A tree is built a level at a time. The nodes a level splits are its
;; tasks. A task's primitives are a contiguous span of `refs`, which the
;; task bins, chooses from, and partitions stably into its children's two
;; spans for the next level, so the tree is the same however the device
;; schedules the work. A task takes one workgroup. A wide task, of more
;; than WIDE primitives, would leave the rest of the device idle near the
;; root, so every workgroup takes blocks of it: each bins its blocks into
;; the task's bins in memory, one workgroup chooses, and the blocks count
;; their left primitives, scan the counts and scatter, as one workgroup's
;; partition does. Workgroups take every `num_workgroups`-th task or
;; block, so a dispatch's size does not depend on counts only the device
;; knows, and no dispatch is indirect.
;;
;;   measure  each primitive's box: a triangle's, or for the top level a
;;            bottom level's root slot
;;   split    one level's tasks, each a leaf or a node of two children
;;            that are the next level's tasks
;;   wide_…   the same for a level's wide tasks, a kernel a step
;;   fill     each leaf triangle's corner and edges, from the vertices
;;   clear    the boxes of moving trees' slots, emptied
;;   climb    each moving triangle's box merged into every slot above it
;;   convert  the merged boxes written back as floats
;;
;; A slot is a child as a walk reads it (rays.wgsl.scm): a box, a pointer
;; and a count. A count of 0 points at a node, the two slots at `pointer`
;; and `pointer + 1`; a count above 0 is a leaf of that many triangles
;; from `pointer` in `triangles`. A top level's leaf is a copy of a
;; bottom level's root slot, so a walk goes from the top level into a
;; bottom level as into any node.
;;
;; `BvhBuild`, `BvhRefit` and `BvhTask` come from Pod.

(struct BvhSlot
        (low vec3f)
        (pointer u32)
        (high vec3f)
        (count u32))

(struct BvhTriangle
        (a vec3f)
        (id u32)
        (e1 vec3f)
        (pad u32)
        (e2 vec3f)
        (slot u32))

(struct Box
        (low vec3f)
        (pad0 u32)
        (high vec3f)
        (pad1 u32))

((var uniform) (@group 0) (@binding 0) (build BvhBuild))

((var storage read_write) (@group 0) (@binding 1) (boxes (array Box)))

((var storage read_write) (@group 0) (@binding 2) (refs (array u32)))

((var storage read_write) (@group 0) (@binding 3) (tasks (array BvhTask)))

((var storage read_write) (@group 0) (@binding 4) (counts (array (atomic u32))))

((var storage read_write) (@group 0) (@binding 5) (slots (array BvhSlot)))

((var storage read_write) (@group 0) (@binding 6) (triangles (array BvhTriangle)))

((var storage read_write) (@group 0) (@binding 7) (parents (array u32)))

((var storage read) (@group 0) (@binding 8) (positions (array f32)))

((var storage read) (@group 0) (@binding 9) (indices (array u32)))

((var storage read_write) (@group 0) (@binding 10) (merged (array (atomic u32))))

((var uniform) (@group 0) (@binding 11) (refit BvhRefit))

;; A level's wide tasks, by the level's parity; each wide task's bins,
;; children's centroid bounds and (for a root) its own, merged by every
;; workgroup; its choice and node; and each of its blocks' left count.
((var storage read_write) (@group 0) (@binding 12) (widened (array u32)))

((var storage read_write) (@group 0) (@binding 13) (wide (array (atomic u32))))

((var storage read_write) (@group 0) (@binding 14) (decided (array Decided)))

((var storage read_write) (@group 0) (@binding 15) (lefts (array u32)))

;; ---- Numbers ----

(const BINS 16u)

(const GROUP 256u)

;; A step into a node costs what testing one triangle does.
(const STEP 1.0)

(const FAR 1e30)

;; A float as a u32 that sorts as the float does, so atomicMin and
;; atomicMax merge boxes: flip a negative's bits, set a positive's sign.
(fn ordered ((f f32)) (-> u32)
    (let b ((bitcast u32) f))
    (return (select (bit-or b 2147483648u) (bit-not b) (!= (bit-and b 2147483648u) 0u))))

(fn unordered ((u u32)) (-> f32)
    (return ((bitcast f32)
             (select (bit-not u) (bit-and u 2147483647u) (!= (bit-and u 2147483648u) 0u)))))

;; Half a box's surface area, what the heuristic prices a box by.
(fn area ((low vec3f) (high vec3f)) (-> f32)
    (let d (max (- high low) (vec3f 0.0)))
    (return (+ (* (get d x) (get d y)) (* (get d y) (get d z)) (* (get d z) (get d x)))))

(fn center ((b Box)) (-> vec3f)
    (return (* 0.5 (+ (get b low) (get b high)))))

(fn item ((id vec3u)) (-> u32)
    (return (+ (get id x) (* (get id y) 16776960u))))

;; ---- Primitives ----

(fn corner ((triangle u32) (k u32)) (-> vec3f)
    (let at_word (+
                  (* (at indices (+ (* triangle 3u) k)) (u32 (get build stride)))
                  (u32 (get build offset))))
    (return
     (vec3f (at positions at_word) (at positions (+ at_word 1u)) (at positions (+ at_word 2u)))))

;; Primitive i's box, and the first level's span of every primitive, in
;; order.
(fn (@compute) (@workgroup_size 256) measure (((@builtin global_invocation_id) id vec3u))
    (let i (item id))
    (if ((>= i (u32 (get build primitives))) (return)))
    (= (at refs i) i)
    (if ((!= (get build instances) 0)
         (let s (at slots (+ (u32 (get build root_base)) i)))
         (= (at boxes i) (Box (get s low) 0u (get s high) 0u))
         (return)))
    (let triangle (+ (u32 (get build first_triangle)) i))
    (let a (corner triangle 0u))
    (let b (corner triangle 1u))
    (let c (corner triangle 2u))
    (= (at boxes i) (Box (min a (min b c)) 0u (max a (max b c)) 0u)))

;; ---- Tasks ----

;; A task in the build's own terms: the span of `refs` it splits, the
;; slot its node fills, its depth, and its centroids' bounds, unknown (low
;; above high) for a tree's root.
(struct Work
        (first u32)
        (count u32)
        (slot u32)
        (depth u32)
        (low vec3f)
        (high vec3f))

;; What a task becomes: a leaf (0), a split at a bin's far side on an axis
;; (1), or a split of the span in half (2); the left child's count; and
;; the task's box.
(struct Choice
        (kind u32)
        (axis u32)
        (bin u32)
        (left u32)
        (low vec3f)
        (high vec3f))

(const LEAF 0u)

(const BINNED 1u)

(const HALVED 2u)

(fn level () (-> u32)
    (return (u32 (get build level))))

;; Where this level reads its spans and tasks, and where it writes the
;; next level's: the two halves of `refs` and `tasks` take turns.
(fn reading () (-> u32)
    (return (* (% (level) 2u) (u32 (get build capacity)))))

(fn writing () (-> u32)
    (return (* (% (+ (level) 1u) 2u) (u32 (get build capacity)))))

(fn task_at ((k u32)) (-> Work)
    (let t (at tasks (+ (reading) k)))
    (return (Work (u32 (get t first))
                  (u32 (get t count))
                  (u32 (get t slot))
                  (u32 (get t depth))
                  (get t low xyz)
                  (get t high xyz))))

(fn task_of ((w Work) (low vec3f) (high vec3f)) (-> BvhTask)
    (return (BvhTask (i32 (get w first))
                     (i32 (get w count))
                     (i32 (get w slot))
                     (i32 (get w depth))
                     (vec4f low 0.0)
                     (vec4f high 0.0))))

;; ---- Splitting a level ----

;; Each bin of each axis: its count, then its boxes' low and high corners
;; as ordered words.
((var workgroup) (bins (array (atomic u32) 336)))

;; Each boundary's price, five and ten of every axis's sixteen bins.
((var workgroup) (prices (array f32 45)))

;; The children's centroid bounds, as ordered words, the left's then the
;; right's; a root's own first.
((var workgroup) (sides (array (atomic u32) 12)))

((var workgroup) (scan (array u32 256)))

((var workgroup) (work Work))

((var workgroup) (choice Choice))

((var workgroup) (tasks_here u32))

((var workgroup) (lefts_before u32))

(fn (@compute) (@workgroup_size 256) split
    (((@builtin local_invocation_index) t u32)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (if ((== t 0u) (= tasks_here (atomicLoad (address-of (at counts (+ 1u (level))))))))
    (let here (workgroupUniformLoad (address-of tasks_here)))
    (for ((var k (get group x)) (< k here) (+= k (get groups x)))
         (take k t)))

(fn take ((k u32) (t u32))
    (if ((== t 0u) (= work (task_at k))))
    (var task (workgroupUniformLoad (address-of work)))
    (if ((is_wide task) (return)))
    (if ((== (get task count) 1u)
         (if ((== t 0u) (lone_leaf task)))
         (return)))
    (if ((> (get task low x) (get task high x))
         (bound_centroids task t)
         (= task (workgroupUniformLoad (address-of work)))))
    (let end (+ (get task first) (get task count)))
    (fill_bins task (get task first) end t)
    (price t task)
    (workgroupBarrier)
    (if ((== t 0u) (= choice (chosen task))))
    (let c (workgroupUniformLoad (address-of choice)))
    (if ((== (get c kind) LEAF)
         (leaf task c t)
         (return)))
    (divide task c (get task first) end 0u t)
    (if ((== t 0u)
         (branch task c (side_corner 0u) (side_corner 3u) (side_corner 6u) (side_corner 9u)))))

;; A span of one is a leaf: its triangle's, or the bottom level the top
;; level's primitive names, whose root it becomes.
(fn lone_leaf ((task Work))
    (let prim (at refs (+ (reading) (get task first))))
    (if ((!= (get build instances) 0)
         (= (at slots (get task slot)) (at slots (+ (u32 (get build root_base)) prim)))
         (return)))
    (let b (at boxes prim))
    (leaf_triangle task (get task first) prim)
    (= (at slots (get task slot))
       (BvhSlot (get b low) (+ (u32 (get build leaf_base)) (get task first)) (get b high) 1u)))

(fn leaf_triangle ((task Work) (i u32) (prim u32))
    (= (at triangles (+ (u32 (get build leaf_base)) i))
       (BvhTriangle (vec3f 0.0)
                    (+ (u32 (get build first_triangle)) prim)
                    (vec3f 0.0)
                    0u
                    (vec3f 0.0)
                    (get task slot))))

;; Word w of an empty box's corners: a low corner's starts far above
;; anything it merges, a high corner's far below.
(fn emptied ((w u32)) (-> u32)
    (return (select (ordered FAR) (ordered (- FAR)) (>= (% w 6u) 3u))))

;; A root's centroid bounds, which no parent measured.
(fn bound_centroids ((task Work) (t u32))
    (if ((< t 6u) (atomicStore (address-of (at sides t)) (emptied t))))
    (workgroupBarrier)
    (for ((var i (+ (get task first) t)) (< i (+ (get task first) (get task count))) (+= i GROUP))
         (merge_side 0u (center (at boxes (at refs (+ (reading) i))))))
    (workgroupBarrier)
    (if ((== t 0u)
         (= (get work low) (side_corner 0u))
         (= (get work high) (side_corner 3u)))))

(fn merge_side ((at_word u32) (p vec3f))
    (for ((var axis 0u) (< axis 3u) (+= axis 1u))
         (atomicMin (address-of (at sides (+ at_word axis))) (ordered (at p axis)))
         (atomicMax (address-of (at sides (+ at_word 3u axis))) (ordered (at p axis)))))

(fn side_corner ((at_word u32)) (-> vec3f)
    (return (vec3f (unordered (atomicLoad (address-of (at sides at_word))))
                   (unordered (atomicLoad (address-of (at sides (+ at_word 1u)))))
                   (unordered (atomicLoad (address-of (at sides (+ at_word 2u))))))))

;; Bins a unit of an axis, or 0 where the centroids do not spread along it.
(fn scale ((task Work) (axis u32)) (-> f32)
    (let extent (- (at (get task high) axis) (at (get task low) axis)))
    (return (select 0.0 (/ (f32 BINS) extent) (> extent 0.0))))

(fn bin_of ((task Work) (axis u32) (c vec3f)) (-> u32)
    (let x (* (- (at c axis) (at (get task low) axis)) (scale task axis)))
    (return (min (u32 (max x 0.0)) (- BINS 1u))))

(fn bin_word ((axis u32) (bin u32) (field u32)) (-> u32)
    (return (+ (* (+ (* axis BINS) bin) 7u) field)))

;; Word w of empty bins: a count of 0, then a box's emptied corners.
(fn unbinned ((w u32)) (-> u32)
    (let field (% w 7u))
    (if ((== field 0u) (return 0u)))
    (return (emptied (- field 1u))))

;; The bins of `task`'s primitives from `start` to `stop`.
(fn fill_bins ((task Work) (start u32) (stop u32) (t u32))
    (for ((var w t) (< w 336u) (+= w GROUP))
         (atomicStore (address-of (at bins w)) (unbinned w)))
    (workgroupBarrier)
    (for ((var i (+ start t)) (< i stop) (+= i GROUP))
         (let b (at boxes (at refs (+ (reading) i))))
         (let c (center b))
         (for ((var axis 0u) (< axis 3u) (+= axis 1u))
              (let w (bin_word axis (bin_of task axis c) 0u))
              (atomicAdd (address-of (at bins w)) 1u)
              (for ((var k 0u) (< k 3u) (+= k 1u))
                   (atomicMin (address-of (at bins (+ w 1u k))) (ordered (at (get b low) k)))
                   (atomicMax (address-of (at bins (+ w 4u k))) (ordered (at (get b high) k))))))
    (workgroupBarrier))

(fn bin_count ((axis u32) (bin u32)) (-> u32)
    (return (atomicLoad (address-of (at bins (bin_word axis bin 0u))))))

(fn bin_corner ((axis u32) (bin u32) (field u32)) (-> vec3f)
    (let w (bin_word axis bin field))
    (return (vec3f (unordered (atomicLoad (address-of (at bins w))))
                   (unordered (atomicLoad (address-of (at bins (+ w 1u)))))
                   (unordered (atomicLoad (address-of (at bins (+ w 2u))))))))

;; Some bins merged: how many primitives they hold, and their box.
(struct Side
        (count u32)
        (low vec3f)
        (high vec3f))

(fn nothing () (-> Side)
    (return (Side 0u (vec3f FAR) (vec3f (- FAR)))))

(fn grown ((side Side) (axis u32) (bin u32)) (-> Side)
    (let n (bin_count axis bin))
    (if ((== n 0u) (return side)))
    (return (Side (+ (get side count) n)
                  (min (get side low) (bin_corner axis bin 1u))
                  (max (get side high) (bin_corner axis bin 4u)))))

(fn priced ((side Side)) (-> f32)
    (return (* (area (get side low) (get side high)) (f32 (get side count)))))

;; The price of the boundary after `bin` on `axis`: each side's box's area
;; times its count, or FAR where a side is empty.
(fn boundary ((axis u32) (bin u32)) (-> f32)
    (var left (nothing))
    (var right (nothing))
    (for ((var b 0u) (< b BINS) (+= b 1u))
         (if ((<= b bin) (= left (grown left axis b)))
             (else (= right (grown right axis b)))))
    (if ((or (== (get left count) 0u) (== (get right count) 0u)) (return FAR)))
    (return (+ (priced left) (priced right))))

(fn price ((t u32) (task Work))
    (if ((< t 45u)
         (let axis (/ t 15u))
         (= (at prices t)
            (select FAR (boundary axis (% t 15u)) (> (scale task axis) 0.0))))))

;; How many halvings bring `count` down to leaves of the most a leaf holds.
(fn halvings ((count u32)) (-> u32)
    (let most (u32 (get build most_leaf)))
    (let leaves (/ (+ count (- most 1u)) most))
    (return (- 32u (countLeadingZeros (- leaves 1u)))))

;; A leaf where the leaf may hold the span and the heuristic prefers it
;; or no level is left below; halved where no boundary separates the
;; span, or where only halving still reaches leaves within the levels
;; left; else split at the cheapest boundary. A span halves down to
;; leaves in `halvings` levels, and the root has that many below it, so
;; every span reaches a leaf.
(fn chosen ((task Work)) (-> Choice)
    (var whole (nothing))
    (for ((var b 0u) (< b BINS) (+= b 1u))
         (= whole (grown whole 0u b)))
    (var best 0u)
    (for ((var i 1u) (< i 45u) (+= i 1u))
         (if ((< (at prices i) (at prices best)) (= best i))))
    (let room (- (u32 (get build levels)) (+ (get task depth) 1u)))
    (let none (>= (at prices best) FAR))
    (let a (area (get whole low) (get whole high)))
    (let fits (<= (get task count) (u32 (get build most_leaf))))
    (let cheaper (<= (* a (f32 (get task count))) (+ (* STEP a) (at prices best))))
    (let half (Choice HALVED 0u 0u (/ (get task count) 2u) (get whole low) (get whole high)))
    (if ((and fits (or none cheaper (== room 0u)))
         (return (Choice LEAF 0u 0u 0u (get whole low) (get whole high)))))
    (if ((or none (> (+ (halvings (get task count)) 1u) room)) (return half)))
    (let axis (/ best 15u))
    (let bin (% best 15u))
    (var left (nothing))
    (for ((var b 0u) (<= b bin) (+= b 1u))
         (= left (grown left axis b)))
    (return (Choice BINNED axis bin (get left count) (get whole low) (get whole high))))

;; A leaf of the span's triangles, in the order the span holds them.
(fn leaf ((task Work) (c Choice) (t u32))
    (for ((var i (+ (get task first) t)) (< i (+ (get task first) (get task count))) (+= i GROUP))
         (leaf_triangle task i (at refs (+ (reading) i))))
    (if ((== t 0u)
         (= (at slots (get task slot))
            (BvhSlot (get c low)
                     (+ (u32 (get build leaf_base)) (get task first))
                     (get c high)
                     (get task count))))))

(fn goes_left ((task Work) (c Choice) (i u32) (p vec3f)) (-> bool)
    (if ((== (get c kind) HALVED) (return (< (- i (get task first)) (get c left)))))
    (return (<= (bin_of task (get c axis) p) (get c bin))))

;; The span from `start` to `end` rewritten, a block of the workgroup at a
;; time, its left primitives first, each side in the order it had: each
;; primitive's place is how many of its side come before it in the span,
;; `base` of them before `start`, counted by a scan of the block that
;; takes as many rounds as the block is wide. The children's centroid
;; bounds are left in `sides`.
(fn divide ((task Work) (c Choice) (start u32) (end u32) (base u32) (t u32))
    (if ((< t 12u) (atomicStore (address-of (at sides t)) (emptied t))))
    (if ((== t 0u) (= lefts_before base)))
    (workgroupBarrier)
    (for ((var block start) (< block end) (+= block GROUP))
         (let i (+ block t))
         (let inside (< i end))
         (var prim 0u)
         (var p (vec3f 0.0))
         (var left false)
         (if (inside
              (= prim (at refs (+ (reading) i)))
              (= p (center (at boxes prim)))
              (= left (goes_left task c i p))))
         (= (at scan t) (select 0u 1u (and inside left)))
         (workgroupBarrier)
         (let width (min GROUP (- end block)))
         (for ((var reach 1u) (< reach width) (*= reach 2u))
              (var add 0u)
              (if ((>= t reach) (= add (at scan (- t reach)))))
              (workgroupBarrier)
              (+= (at scan t) add)
              (workgroupBarrier))
         (let before lefts_before)
         (if (inside
              (var place (- (+ (get task first) before (at scan t)) 1u))
              (if ((not left)
                   (= place
                      (+ (get task first)
                         (get c left)
                         (- (- i (get task first)) (+ before (at scan t)))))))
              (= (at refs (+ (writing) place)) prim)
              (merge_side (select 6u 0u left) p)))
         (workgroupBarrier)
         (if ((== t 0u) (+= lefts_before (at scan (- width 1u)))))
         (workgroupBarrier)))

;; The task's node: its slot pointing at a new pair of slots.
(fn new_node ((task Work) (c Choice)) (-> u32)
    (let node (+ (u32 (get build node_base)) (* 2u (atomicAdd (address-of (at counts 0)) 1u))))
    (= (at slots (get task slot)) (BvhSlot (get c low) node (get c high) 0u))
    (= (at parents (/ node 2u)) (get task slot))
    (return node))

;; The node's two children, the next level's tasks, each with its
;; centroids' bounds; a wide child is also on the next level's wide list.
(fn branch ((task Work) (c Choice) (left_low vec3f) (left_high vec3f) (right_low vec3f)
            (right_high vec3f))
    (children task c (new_node task c) left_low left_high right_low right_high))

(fn children ((task Work) (c Choice) (node u32) (left_low vec3f) (left_high vec3f)
              (right_low vec3f) (right_high vec3f))
    (let n (atomicAdd (address-of (at counts (+ 2u (level)))) 2u))
    (let deeper (+ (get task depth) 1u))
    (let left (Work (get task first) (get c left) node deeper left_low left_high))
    (let right (Work (+ (get task first) (get c left))
                     (- (get task count) (get c left))
                     (+ node 1u)
                     deeper
                     right_low
                     right_high))
    (= (at tasks (+ (writing) n)) (task_of left left_low left_high))
    (= (at tasks (+ (writing) n 1u)) (task_of right right_low right_high))
    (widen left n)
    (widen right (+ n 1u)))

;; ---- Leaves ----

;; Each leaf triangle's first corner and its two edges from it, which the
;; walk tests a ray against, read from the vertices as they are now.
(fn (@compute) (@workgroup_size 256) fill (((@builtin global_invocation_id) id vec3u))
    (let i (item id))
    (if ((>= i (u32 (get build primitives))) (return)))
    (let r (+ (u32 (get build leaf_base)) i))
    (let old (at triangles r))
    (let a (corner (get old id) 0u))
    (= (at triangles r)
       (BvhTriangle a
                    (get old id)
                    (- (corner (get old id) 1u) a)
                    0u
                    (- (corner (get old id) 2u) a)
                    (get old slot))))

;; ---- Refitting moving trees ----

;; Slot i of the moving trees': their roots, then their nodes.
(fn moving_slot ((i u32)) (-> u32)
    (let roots (u32 (get refit roots)))
    (if ((< i roots) (return (+ (u32 (get refit first_root)) i))))
    (return (+ (u32 (get refit first_node)) (- i roots))))

(fn moving_slots () (-> u32)
    (return (+ (u32 (get refit roots)) (u32 (get refit nodes)))))

(fn (@compute) (@workgroup_size 256) clear (((@builtin global_invocation_id) id vec3u))
    (let i (item id))
    (if ((>= i (moving_slots)) (return)))
    (let s (* 6u (moving_slot i)))
    (for ((var k 0u) (< k 3u) (+= k 1u))
         (atomicStore (address-of (at merged (+ s k))) (ordered FAR))
         (atomicStore (address-of (at merged (+ s 3u k))) (ordered (- FAR)))))

;; A moving triangle's box merged into its leaf's slot and every slot
;; above it, up to its tree's root: each slot ends as the box of every
;; triangle beneath it, in whatever order the merges land.
(fn (@compute) (@workgroup_size 256) climb (((@builtin global_invocation_id) id vec3u))
    (let i (item id))
    (if ((>= i (u32 (get refit records))) (return)))
    (let tri (at triangles (+ (u32 (get refit first_record)) i)))
    (let b (+ (get tri a) (get tri e1)))
    (let c (+ (get tri a) (get tri e2)))
    (let low (min (get tri a) (min b c)))
    (let high (max (get tri a) (max b c)))
    (var s (get tri slot))
    (loop
     (for ((var k 0u) (< k 3u) (+= k 1u))
          (atomicMin (address-of (at merged (+ (* 6u s) k))) (ordered (at low k)))
          (atomicMax (address-of (at merged (+ (* 6u s) 3u k))) (ordered (at high k))))
     (if ((< s (u32 (get refit root_limit))) (break)))
     (= s (at parents (/ s 2u)))))

(fn (@compute) (@workgroup_size 256) convert (((@builtin global_invocation_id) id vec3u))
    (let i (item id))
    (if ((>= i (moving_slots)) (return)))
    (let s (moving_slot i))
    (let w (* 6u s))
    (= (get (at slots s) low)
       (vec3f (unordered (atomicLoad (address-of (at merged w))))
              (unordered (atomicLoad (address-of (at merged (+ w 1u)))))
              (unordered (atomicLoad (address-of (at merged (+ w 2u)))))))
    (= (get (at slots s) high)
       (vec3f (unordered (atomicLoad (address-of (at merged (+ w 3u)))))
              (unordered (atomicLoad (address-of (at merged (+ w 4u)))))
              (unordered (atomicLoad (address-of (at merged (+ w 5u))))))))

;; ---- Wide tasks ----

(const WIDE 4096u)

(const BLOCK 1024u)

;; A wide task's choice and its node, as every block's workgroup reads them.
(struct Decided
        (kind u32)
        (axis u32)
        (bin u32)
        (left u32)
        (low vec3f)
        (node u32)
        (high vec3f)
        (pad u32))

;; A wide task's words of `wide`: its 336 bins, then its children's
;; centroid bounds, then, for a root, its own.
(const WIDE_WORDS 354u)

(fn is_wide ((task Work)) (-> bool)
    (return (and (< (level) (u32 (get build wide_levels))) (> (get task count) WIDE))))

;; The most wide tasks a level can have, and the most blocks one can.
(fn most_wide () (-> u32)
    (return (+ (/ (u32 (get build capacity)) WIDE) 1u)))

(fn most_blocks () (-> u32)
    (return (/ (+ (u32 (get build capacity)) (- BLOCK 1u)) BLOCK)))

;; Where a level's count of wide tasks is, after every level's count of
;; tasks.
(fn wide_count_at ((at_level u32)) (-> u32)
    (return (+ 2u (u32 (get build levels)) at_level)))

;; A child put on the next level's wide list, if it is wide there.
(fn widen ((child Work) (k u32))
    (if ((and (< (+ (level) 1u) (u32 (get build wide_levels))) (> (get child count) WIDE))
         (let j (atomicAdd (address-of (at counts (wide_count_at (+ (level) 1u)))) 1u))
         (= (at widened (+ (* (% (+ (level) 1u) 2u) (most_wide)) j)) k))))

;; Word w of a wide task's words when nothing has merged into them.
(fn wide_empty ((w u32)) (-> u32)
    (if ((< w 336u) (return (unbinned w))))
    (return (emptied (% (- w 336u) 6u))))

(fn (@compute) (@workgroup_size 256) wide_reset (((@builtin global_invocation_id) id vec3u))
    (let i (item id))
    (if ((>= i (* (most_wide) WIDE_WORDS)) (return)))
    (atomicStore (address-of (at wide i)) (wide_empty (% i WIDE_WORDS))))

((var workgroup) (wide_here u32))

;; How many wide tasks this level has, the same in every invocation.
(fn wide_tasks ((t u32)) (-> u32)
    (if ((== t 0u) (= wide_here (atomicLoad (address-of (at counts (wide_count_at (level))))))))
    (return (workgroupUniformLoad (address-of wide_here))))

(fn wide_index ((j u32)) (-> u32)
    (return (at widened (+ (* (% (level) 2u) (most_wide)) j))))

;; Wide task j, with a root's centroid bounds from its words.
(fn wide_task ((j u32) (t u32)) (-> Work)
    (if ((== t 0u)
         (= work (task_at (wide_index j)))
         (if ((> (get work low x) (get work high x))
              (= (get work low) (wide_corner j 348u))
              (= (get work high) (wide_corner j 351u))))))
    (return (workgroupUniformLoad (address-of work))))

(fn wide_corner ((j u32) (at_word u32)) (-> vec3f)
    (let w (+ (* j WIDE_WORDS) at_word))
    (return (vec3f (unordered (atomicLoad (address-of (at wide w))))
                   (unordered (atomicLoad (address-of (at wide (+ w 1u)))))
                   (unordered (atomicLoad (address-of (at wide (+ w 2u))))))))

;; Word `w` of the workgroup's merged box words, six a box, into wide task
;; j's from `at_word`.
(fn merge_wide ((j u32) (at_word u32) (w u32) (value u32))
    (let into (address-of (at wide (+ (* j WIDE_WORDS) at_word w))))
    (if ((< (% w 6u) 3u) (atomicMin into value))
        (else (atomicMax into value))))

(fn blocks_of ((task Work)) (-> u32)
    (return (/ (+ (get task count) (- BLOCK 1u)) BLOCK)))

(fn block_end ((task Work) (start u32)) (-> u32)
    (return (min (+ start BLOCK) (+ (get task first) (get task count)))))

;; A root's centroid bounds, merged from its blocks.
(fn (@compute) (@workgroup_size 256) wide_bound
    (((@builtin local_invocation_index) t u32)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let n (wide_tasks t))
    (for ((var j 0u) (< j n) (+= j 1u))
         (let task (wide_task j t))
         (if ((<= (get task low x) (get task high x)) (continue)))
         (for ((var b (get group x)) (< b (blocks_of task)) (+= b (get groups x)))
              (let start (+ (get task first) (* b BLOCK)))
              (if ((< t 6u) (atomicStore (address-of (at sides t)) (emptied t))))
              (workgroupBarrier)
              (for ((var i (+ start t)) (< i (block_end task start)) (+= i GROUP))
                   (merge_side 0u (center (at boxes (at refs (+ (reading) i))))))
              (workgroupBarrier)
              (if ((< t 6u) (merge_wide j 348u t (atomicLoad (address-of (at sides t))))))
              (workgroupBarrier))))

;; Each block's bins, merged into the task's.
(fn (@compute) (@workgroup_size 256) wide_bin
    (((@builtin local_invocation_index) t u32)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let n (wide_tasks t))
    (for ((var j 0u) (< j n) (+= j 1u))
         (let task (wide_task j t))
         (for ((var b (get group x)) (< b (blocks_of task)) (+= b (get groups x)))
              (let start (+ (get task first) (* b BLOCK)))
              (fill_bins task start (block_end task start) t)
              (for ((var w t) (< w 336u) (+= w GROUP))
                   (let value (atomicLoad (address-of (at bins w))))
                   (let into (address-of (at wide (+ (* j WIDE_WORDS) w))))
                   (let field (% w 7u))
                   (if ((== field 0u) (atomicAdd into value))
                       ((< field 4u) (atomicMin into value))
                       (else (atomicMax into value))))
              (workgroupBarrier))))

;; A workgroup a wide task: the task's bins priced as a narrow task's are,
;; and its choice and new node kept for its blocks.
(fn (@compute) (@workgroup_size 256) wide_choose
    (((@builtin local_invocation_index) t u32)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let n (wide_tasks t))
    (for ((var j (get group x)) (< j n) (+= j (get groups x)))
         (let task (wide_task j t))
         (for ((var w t) (< w 336u) (+= w GROUP))
              (atomicStore (address-of (at bins w))
                           (atomicLoad (address-of (at wide (+ (* j WIDE_WORDS) w))))))
         (workgroupBarrier)
         (price t task)
         (workgroupBarrier)
         (if ((== t 0u)
              (let c (chosen task))
              (= (at decided j)
                 (Decided (get c kind) (get c axis) (get c bin) (get c left) (get c low)
                          (new_node task c) (get c high) 0u))))
         (workgroupBarrier)))

(fn decision ((j u32)) (-> Choice)
    (let d (at decided j))
    (return (Choice (get d kind) (get d axis) (get d bin) (get d left) (get d low) (get d high))))

((var workgroup) (block_lefts (atomic u32)))

;; How many of each block's primitives go left.
(fn (@compute) (@workgroup_size 256) wide_count
    (((@builtin local_invocation_index) t u32)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let n (wide_tasks t))
    (for ((var j 0u) (< j n) (+= j 1u))
         (let task (wide_task j t))
         (let c (decision j))
         (for ((var b (get group x)) (< b (blocks_of task)) (+= b (get groups x)))
              (let start (+ (get task first) (* b BLOCK)))
              (if ((== t 0u) (atomicStore (address-of block_lefts) 0u)))
              (workgroupBarrier)
              (for ((var i (+ start t)) (< i (block_end task start)) (+= i GROUP))
                   (if ((goes_left task c i (center (at boxes (at refs (+ (reading) i)))))
                        (atomicAdd (address-of block_lefts) 1u))))
              (workgroupBarrier)
              (if ((== t 0u)
                   (= (at lefts (+ (* j (most_blocks)) b)) (atomicLoad (address-of block_lefts)))))
              (workgroupBarrier))))

;; An invocation a wide task: its blocks' left counts become how many go
;; left before each block.
(fn (@compute) (@workgroup_size 256) wide_scan (((@builtin global_invocation_id) id vec3u))
    (let j (item id))
    (if ((>= j (atomicLoad (address-of (at counts (wide_count_at (level)))))) (return)))
    (let task (task_at (wide_index j)))
    (var before 0u)
    (for ((var b 0u) (< b (blocks_of task)) (+= b 1u))
         (let at_block (+ (* j (most_blocks)) b))
         (let n (at lefts at_block))
         (= (at lefts at_block) before)
         (+= before n)))

;; Each block divided as a narrow task's span is, from its place in the
;; span, and its children's centroid bounds merged into the task's.
(fn (@compute) (@workgroup_size 256) wide_scatter
    (((@builtin local_invocation_index) t u32)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let n (wide_tasks t))
    (for ((var j 0u) (< j n) (+= j 1u))
         (let task (wide_task j t))
         (let c (decision j))
         (for ((var b (get group x)) (< b (blocks_of task)) (+= b (get groups x)))
              (let start (+ (get task first) (* b BLOCK)))
              (divide task c start (block_end task start) (at lefts (+ (* j (most_blocks)) b)) t)
              (if ((< t 12u) (merge_wide j 336u t (atomicLoad (address-of (at sides t))))))
              (workgroupBarrier))))

;; A workgroup a wide task: its children made, and its words emptied for
;; the next level's.
(fn (@compute) (@workgroup_size 256) wide_branch
    (((@builtin local_invocation_index) t u32)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let n (wide_tasks t))
    (for ((var j (get group x)) (< j n) (+= j (get groups x)))
         (let task (wide_task j t))
         (if ((== t 0u)
              (children task (decision j) (get (at decided j) node)
                        (wide_corner j 336u) (wide_corner j 339u)
                        (wide_corner j 342u) (wide_corner j 345u))))
         (workgroupBarrier)
         (for ((var w t) (< w WIDE_WORDS) (+= w GROUP))
              (atomicStore (address-of (at wide (+ (* j WIDE_WORDS) w))) (wide_empty w)))
         (workgroupBarrier)))
