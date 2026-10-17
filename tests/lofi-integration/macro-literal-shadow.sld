(import
 (lofi primitive)
 (macro facade))
(i32-add (recognize marker) ((lambda (marker) (recognize marker)) 99))
