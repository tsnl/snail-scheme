(import
 (lofi base))
;; Former macro expansion introduced two independent local nominal types.
;; Each explicit lexical block keeps its constructor and accessor identities.
(def Box (datatype ()
           (box
            (item Bool unbox))))
(if (unbox (box #t))
    (+ (begin
         (begin
           (def Box (datatype ()
                      (box
                       (item I64 unbox))))
           (unbox (box 8))))
       (begin
         (begin
           (def Box (datatype ()
                      (box
                       (item I64 unbox))))
           (unbox (box 9)))))
    0)
