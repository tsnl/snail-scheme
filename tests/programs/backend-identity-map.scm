(import (scheme base) (scheme write) (snail-scheme identity-map))

(define (check condition message) (unless condition (error message)))
(define (integers count procedure)
  (let loop ((index 0)) (unless (= index count) (procedure index) (loop (+ index 1)))))

;; Keep older versions alive across allocations and key mutation. Equal-shaped
;; keys have distinct identities; persistence preserves mappings, not key copies.
(define keys (make-vector 1024))
(integers 1024 (lambda (index) (vector-set! keys index (cons 1 2))))
(define versions '())
(define original
  (let loop ((index 0) (root empty-identity-map))
    (if (= index 1024) root
        (let ((next (identity-map-set root (vector-ref keys index) index)))
          (when (= (modulo index 64) 0) (set! versions (cons (cons next index) versions)))
          (loop (+ index 1) next)))))

(define updated
  (let loop ((index 0) (root original))
    (if (= index 1024) root
        (let ((key (vector-ref keys index)))
          (set-car! key index)
          (loop (+ index 1) (identity-map-set root key (if (= (modulo index 2) 0) #f '())))))))

(integers 1024
          (lambda (index)
            (let ((key (vector-ref keys index)))
              (check (= (identity-map-ref original key 'missing) index) "original version")
              (check (equal? (identity-map-ref updated key 'missing)
                             (if (= (modulo index 2) 0) #f '())) "replacement"))))
(for-each
 (lambda (version)
   (integers 1024
             (lambda (index)
               (check (equal? (identity-map-ref (car version) (vector-ref keys index) 'missing)
                              (if (<= index (cdr version)) index 'missing)) "saved version"))))
 versions)
(check (eq? (identity-map-ref updated (cons 1 2) 'missing) 'missing) "identity equality")
(check (not (identity-map-ref empty-identity-map (car versions) #f)) "false default")
(check (null? (identity-map-ref empty-identity-map (car versions) '())) "null default")
(display "persistent identity map checks passed") (newline)
