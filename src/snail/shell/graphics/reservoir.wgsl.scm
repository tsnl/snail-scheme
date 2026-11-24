;; A stream represents M proposals, including the ones with zero weight.
;; With probability w / sum(w) a new sample replaces the selected one.
;; The caller supplies a uniform draw in [0, 1).
(const RESERVOIR_F32_MAX 3.402823466e38)

(fn reservoir_update ((r (ptr function Reservoir)) (sample LightSample) (weight f32)
                      (count i32) (u f32))
    (+= (get (deref r) count) count)
    (let total (+ (get (deref r) weight_sum) weight))
    (if ((not (and (> weight 0.0) (<= total RESERVOIR_F32_MAX))) (return)))
    (= (get (deref r) weight_sum) total)
    (if ((< (* u total) weight) (= (get (deref r) selected) sample))))

(fn reservoir_draw ((r (ptr function Reservoir)) (sample LightSample) (pdf f32) (u f32))
    (var weight 0.0)
    (if ((> pdf 0.0) (= weight (/ (get sample target_value) pdf))))
    (reservoir_update r sample weight 1 u))

;; W = sum(w) / (M * target(selected)). Only an actual selection has W.
(fn reservoir_weight ((r Reservoir)) (-> f32)
    (if ((== (get r selected target_value) 0.0) (return 0.0)))
    (let w (/ (/ (get r weight_sum) (f32 (get r count))) (get r selected target_value)))
    (return (select 0.0 w (<= w RESERVOIR_F32_MAX))))

;; The donor represents m of its original proposals. Its normalization uses
;; the original count; the receiver evaluates the target at its own surface.
(fn reservoir_merge ((r (ptr function Reservoir)) (donor Reservoir) (target_value f32)
                     (m i32) (u f32))
    (let sample (LightSample (get donor selected direction) target_value))
    (reservoir_update r sample (* target_value (reservoir_weight donor) (f32 m)) m u))
