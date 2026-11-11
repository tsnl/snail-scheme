;; The integrator's SHA-256 beside the old compiler's, over messages of
;; every length from empty to past two blocks, whose bytes take every
;; value, and one of high bytes alone. tests/compiler.scm runs it on
;; Chibi and tests/compare-compiler.sld compiled, so the two agree on
;; both hosts.
(define-library (snail compiler adapter sha256)
  (export
   digest-difference)
  (import
   (snail core base)
   (snail compiler integrate sha256)
   (prefix (only (snail shell compiler sha256) sha256 bytes->hex) old:))
  (begin

    ;; The first message whose digests differ, by its length, if one does.
    (: digest-difference (impl (Fn -> (Option String))))
    (define (digest-difference)
      (match (find (lambda (message)
                     (not (string=? (bytes->hex (sha256 message))
                                    (old:bytes->hex (old:sha256 message)))))
                   messages)
        ((Some message)
         (Some (string-append "the digests of a message of "
                              (i64->string (vector-length message))
                              " bytes differ")))
        ((None) (None))))

    ;; Byte `index` of the message of `length` bytes is a value of its own
    ;; for each index and length, under 256.
    (: messages (List Bytes))
    (define messages
      (Cons (vector-generate 200 (lambda (index) (i32->u8 255)))
            (map (lambda (length)
                   (vector-generate length
                                    (lambda (index)
                                      (i32->u8
                                       (i64->i32 (remainder (+ (* index 37) length) 256))))))
                 (iota 131))))

    ))
