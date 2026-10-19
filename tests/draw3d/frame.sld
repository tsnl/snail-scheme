(define-library (tests draw3d frame)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (draw3d)
   (siegework model)
   (siegework view)
   (only (lofi core) ann -> I32))
  (begin
    (define answer
      (ann (lambda ()
             (let* ((world (initial-world))
                    (camera (colony-camera (* (world-hub-x world) 1000) (* (world-hub-y world) 1000) 960 640)))
               (present-scene! (colony-scene world world camera 12 20 3))
               1))
           (-> I32)))))
