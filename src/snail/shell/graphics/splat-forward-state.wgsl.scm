;; What training's forward pass keeps of each pixel for the backward
;; pass to start from: its final transmittance, and how many of its tile's
;; entries it went through. splat-forward.wgsl.scm follows this file.
((var storage read_write) (@group 0) (@binding 4) (finals (array f32)))

((var storage read_write) (@group 0) (@binding 5) (contributed (array u32)))

(fn keep ((p u32) (transmittance f32) (last u32))
    (= (at finals p) transmittance)
    (= (at contributed p) last))
