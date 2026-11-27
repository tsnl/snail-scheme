;; The disk representation of a SHA-256 object. Writers stage on the store's
;; filesystem and publish only after verifying the complete input. A second
;; build can fill a missing part without replacing parts other builds share.
(define-library (snail shell blob-store)
  (export
   blob-part-size
   blob-directory
   BlobPart
   blob-parts
   store-file!
   put-blob!
   read-blob)
  (import
   (snail core base)
   (snail core io)
   (snail shell compiler blob)
   (snail shell compiler sha256))
  (begin

    ;; ---- Publishing ----

    (define (stored-part? (fs Fs) (root String) (part BlobPart)) (→ Bool)
      (match (file-status fs (string-append root "/" (● part path)))
        ((Ok status) (match (● status kind)
                       ((RegularFile) (= (● status size) (● part size))) (_ #f)))
        ((Err _) #f)))

    (define (scratch-directory (fs Fs) (root String) (n I64)) (→ (Result String String))
      (let ((path (string-append root "/.writing-" (show n))))
        (match (make-directory fs path)
          ((Ok _) (Ok path))
          ((Err (AlreadyExists)) (scratch-directory fs root (+ n 1)))
          ((Err why) (Err (string-append "cannot make " path ": " (show why)))))))

    (define (with-scratch (fs Fs) (root String) (write (Fn String → (Result String String))))
      (→ (Result String String))
      (match (make-directories fs root)
        ((Err why) (Err (string-append root ": " (show why))))
        ((Ok _) (match (scratch-directory fs root 0)
                  ((Err why) (Err why))
                  ((Ok scratch)
                   (let ((result (write scratch)))
                     (match (remove-tree fs scratch)
                       ((Ok _) result)
                       ((Err why)
                        (Err (string-append "cannot clean " scratch ": " (show why)))))))))))

    (define (publish-parts! (fs Fs) (root String) (scratch String) (parts (List BlobPart)))
      (→ (Result Unit String))
      (match parts
        ((Nil) (Ok (unit)))
        ((Cons part rest)
         (let ((from (string-append scratch "/" (show (● part offset))))
               (to (string-append root "/" (● part path))))
           (match (rename-file fs from to)
             ((Ok _) (publish-parts! fs root scratch rest))
             ((Err why) (Err (string-append "cannot place " to ": " (show why)))))))))

    (define (publish! (fs Fs) (root String) (scratch String)
                      (digest String) (size I64) (replace? Bool))
      (→ (Result String String))
      (let* ((folder (string-append root "/" (blob-parent digest size)))
             (parts (blob-parts digest size))
             (needed
              (if replace? parts (filter (lambda (p) (not (stored-part? fs root p))) parts))))
        (match (make-directories fs folder)
          ((Err why) (Err (string-append folder ": " (show why))))
          ((Ok _) (match (publish-parts! fs root scratch needed)
                    ((Ok _) (Ok digest)) ((Err why) (Err why)))))))

    ;; ---- Files and in-memory bytes ----

    (define (stage! (fs Fs) (scratch String) (offset I64) (bytes Bytes)) (→ Unit)
      (write-bytes fs (string-append scratch "/" (show offset)) bytes))

    ;; Offsets identify each staged piece even before its full digest is known.
    (define (ingest-file! (fs Fs) (root String) (scratch String) (path String)
                          (size I64) (expected (Option String)))
      (→ (Result String String))
      (let* ((step (lambda (state bytes)
                     (stage! fs scratch (● state size) bytes)
                     (sha256-update state bytes)))
             (hash (fold-file-chunks fs path (max 1 (min size blob-part-size)) (sha256-start) step))
             (digest (bytes->hex (sha256-finish hash))))
        (if (or (not (= size (● hash size)))
                (match expected ((Some d) (not (string=? d digest))) ((None) #f)))
            (Err "contents changed during the build")
            (begin
              (when (= size 0) (stage! fs scratch 0 (make-array 0 (i32->u8 0))))
              (publish! fs root scratch digest size (match expected ((None) #t) ((Some _) #f)))))))

    (define (store-source! (fs Fs)
                           (root String)
                           (path String)
                           (size I64)
                           (expected (Option String)))
      (→ (Result String String))
      (match (followed-status fs path)
        ((Err why) (Err (string-append path ": " (show why))))
        ((Ok status)
         (match (● status kind)
           ((RegularFile)
            (with-scratch fs root (lambda (s) (ingest-file! fs root s path size expected))))
           (_ (Err (string-append "expected a regular file at " path)))))))

    ;; Supplying an observed digest lets a complete store hit skip the source.
    (define (store-file! (fs Fs) (root String) (path String) (size I64) (expected (Option String)))
      (→ (Result String String))
      (if (< size 0) (Err "invalid blob length")
          (match expected
            ((None) (store-source! fs root path size expected))
            ((Some digest)
             (cond ((not (blob-digest? digest)) (Err "invalid blob digest"))
                   ((every? (lambda (p) (stored-part? fs root p)) (blob-parts digest size))
                    (Ok digest))
                   (else (store-source! fs root path size expected)))))))

    (define (stage-bytes! (fs Fs) (scratch String) (bytes Bytes) (part BlobPart)) (→ Unit)
      (let ((offset (● part offset)) (n (● part size)))
        (stage! fs
                scratch
                offset
                (if (= n (array-length bytes)) bytes (subarray bytes offset (+ offset n))))))

    (define (put-blob! (fs Fs) (root String) (bytes Bytes)) (→ (Result String String))
      (let ((size (array-length bytes)) (digest (bytes->hex (sha256 bytes))))
        (with-scratch fs root
                      (lambda (scratch)
                        (for-each (lambda (part) (stage-bytes! fs scratch bytes part))
                                  (blob-parts digest size))
                        (publish! fs root scratch digest size #t)))))

    ;; Reading into a single Bytes obeys the runtime's array length limit.
    (define (read-blob (fs Fs) (root String) (digest String) (size I64)) (→ (Option Bytes))
      (if (or (< size 0) (> size 2147483647) (not (blob-digest? digest))) (None)
          (let ((parts (blob-parts digest size)))
            (if (every? (lambda (p) (stored-part? fs root p)) parts)
                (let ((bytes (array-concatenate
                              (map (lambda (p) (read-bytes fs (string-append root "/" (● p path))))
                                   parts))))
                  (if (string=? digest (bytes->hex (sha256 bytes))) (Some bytes) (None)))
                (None)))))))
