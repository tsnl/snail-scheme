(import
 (lofi serialization)
 (only (lofi io) InputPort))
(data Resource ()
  (resource
   (port InputPort))
  (deriving derive-serialize))
(ann 42 I32)
