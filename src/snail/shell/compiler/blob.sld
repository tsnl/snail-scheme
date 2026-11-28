;; The physical representation of one SHA-256 object. The compiler encodes
;; this layout in links; builders, producers and hosts use the same contract.
(define-library (snail shell compiler blob)
  (export
   blob-part-size
   blob-parts-prefix
   blob-raw-path
   blob-directory
   blob-link-symbol
   blob-parent
   blob-digest?
   BlobPart
   blob-parts)
  (import
   (snail core base))
  (begin
    (define blob-part-size (→ I64) (* 25 1048576))

    ;; The width is part of the address. An immutable part URL always names
    ;; the same bytes, including alongside older generations in one store.
    (define blob-parts-prefix (→ String)
      (string-append "chunks/" (i64->string blob-part-size)))

    (define (blob-key (digest String)) (→ String)
      (string-append (substring digest 0 2) "/" digest))

    (define (blob-raw-path (digest String)) (→ String)
      (string-append "sha256/" (blob-key digest)))

    (define (blob-directory (digest String)) (→ String)
      (string-append blob-parts-prefix "/" (blob-key digest)))

    (define (blob-parent (digest String) (size I64)) (→ String)
      (if (> size blob-part-size) (blob-directory digest)
          (string-append "sha256/" (substring digest 0 2))))

    (define (blob-digest? (digest String)) (→ Bool)
      (and (= (string-length digest) 64)
           (every? (lambda (c) (or (and (>= c #\0) (<= c #\9))
                                   (and (>= c #\a) (<= c #\f)))) (string->list digest))))

    (define (blob-link-symbol (digest String) (size I64)) (→ String)
      (if (<= size blob-part-size) digest
          (string-append digest ":" (i64->string size) ":" (i64->string blob-part-size))))

    (record BlobPart
      ((path String)
       (offset I64)
       (size I64)))

    (define (blob-parts (digest String) (size I64)) (→ (List BlobPart))
      (if (<= size blob-part-size)
          (list (new BlobPart (path (blob-raw-path digest)) (offset 0) (size size)))
          (let ((directory (blob-directory digest)))
            (map (lambda (i)
                   (let ((offset (* i blob-part-size)))
                     (new BlobPart (path (string-append directory "/" (i64->string i)))
                          (offset offset) (size (min blob-part-size (- size offset))))))
                 (iota (+ 1 (quotient (- size 1) blob-part-size)))))))))
