(import
 (lofi serialization))
(data Callback ()
  (callback
   (run (-> I32 I32)))
  (deriving derive-serialize))
(ann 42 I32)
