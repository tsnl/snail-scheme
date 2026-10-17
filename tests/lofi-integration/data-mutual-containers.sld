(import (lofi base))
(def Node (datatype ()
                    (node (children (Ref (List Edge)) node-children) (cache (Vector Edge) node-cache))))
(def Edge (datatype () (edge (target Node edge-target))))
(def root
     (node (ref (empty-list )) (empty-vector)))
(def link
     (edge root))
(ref-set! (node-children root) (cons link (empty-list )))
(def other
     (node (ref (empty-list )) (vector link)))
(if (ref-eq? (node-children (edge-target (vector-ref (node-cache other) (ann 0 I64))))
             (node-children (edge-target (car (ref-get (node-children root))))))
    (ann 23 I64)
    (ann 0 I64))
