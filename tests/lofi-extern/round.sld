(import
 (lofi base))

(def worker (-> F64 F64)
     (lambda (value) (round value)))

(def round32 (-> F32 F32)
     (lambda (value) (round value)))

(def nearest64 (-> F64 F64)
     (lambda (value) (f64-round value)))

(def nearest32 (-> F32 F32)
     (lambda (value) (f32-round value)))
(def concrete64
     (ann round (-> F64 F64)))
(def concrete32
     (ann round (-> F32 F32)))

(def view64 (-> F64 F64)
     (lambda (value) (concrete64 value)))

(def view32 (-> F32 F32)
     (lambda (value) (concrete32 value)))
(unit)
