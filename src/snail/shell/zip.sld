;; Zip archives, read a member at a time. An archive ends with its
;; directory, a header for each member that says where the member's own
;; header and bytes are, so a reader that can ask for any range of an
;; archive, as HTTP's ranges ask a server, asks for the end, then for the
;; directory, then for each member it wants, and never for the rest:
;;
;;   [local header, bytes] ... directory [Zip64 end, locator] end
;;
;; An archive past 4 GiB, or of more than 65,535 members, keeps the
;; numbers too wide for their fields in Zip64's records: the directory's
;; in a record before the end, which a locator points to, and a member's
;; in an extra field of its header. Each function here reads bytes it is
;; given and asks for none: `zip-directory` reads the archive's last
;; `end-bytes`, `zip-entries` the directory, and `entry-contents` the
;; bytes of the member's span, checked against the directory's length and
;; CRC-32. A member's bytes are kept as they are or deflated
;; ((snail shell inflate)); encrypted members, and other methods, are
;; refused, as are names that are not UTF-8.
(define-library (snail shell zip)
  (export
   ZipDirectory
   ZipEntry
   end-bytes
   zip-directory
   zip-entries
   entry-contents
   crc32)
  (import
   (snail core base)
   (only (snail shell utf8) utf8->string)
   (snail shell inflate))
  (begin

    ;; ---- Records ----

    ;; Where the directory is in the archive, and how many bytes it has.
    (record ZipDirectory
      ((start I64)
       (size I64)))

    ;; A member as the directory gives it: its name, a folder's ending in
    ;; `/`; how its bytes are kept, 0 as they are and 8 deflated; their
    ;; CRC-32; how many bytes it keeps and how many it holds; and its span
    ;; of the archive, from its local header to the next member's, or to
    ;; the directory.
    (record ZipEntry
      ((name String)
       (method I64)
       (crc I64)
       (compressed I64)
       (size I64)
       (start I64)
       (end I64)))

    ;; ---- Failures ----

    ;; Bytes that are not an archive's stop the reading. Nothing resumes a
    ;; failure, so failing saves no frames; each entry point turns it into
    ;; its Result.
    (define malformed (→ (Prompt String Never)) (make-prompt))

    (define (fail (why String)) (→ A) (∀ (A))
      (absurd (suspend malformed why)))

    (define (reading (work (Fn → T))) (→ (Result T String)) (∀ (T))
      (with-prompt malformed (lambda () (Ok (work))) (lambda (why resume) (Err why))))

    ;; ---- Numbers ----

    ;; Each number is little-endian.

    (define (byte-at (bytes Bytes) (at I64)) (→ I64)
      (if (and (>= at 0) (< at (array-length bytes)))
          (i32->i64 (u8->i32 (array-ref bytes at)))
          (fail "the archive's records run past the bytes read")))

    (define (u16 (bytes Bytes) (at I64)) (→ I64)
      (i64-or (byte-at bytes at) (i64-shift-left (byte-at bytes (+ at 1)) 8)))

    (define (u32 (bytes Bytes) (at I64)) (→ I64)
      (i64-or (u16 bytes at) (i64-shift-left (u16 bytes (+ at 2)) 16)))

    (define (u64 (bytes Bytes) (at I64)) (→ I64)
      (i64-or (u32 bytes at) (i64-shift-left (u32 bytes (+ at 4)) 32)))

    ;; A field whose number is too wide holds all ones.
    (define wide (→ I64) 4294967295)

    ;; ---- The end ----

    ;; The most bytes the end's records take: the end record, 22 bytes,
    ;; with a comment of up to 65,535, and Zip64's locator, 20, and end
    ;; record, 56, before it.
    (define end-bytes (→ I64) 65633)

    ;; The directory, from the archive's last bytes, `tail`: at most
    ;; `end-bytes` of them, and enough to hold its end records. The end
    ;; record is the last that its comment's length carries to the end, as
    ;; a comment may hold its signature too.

    (define (zip-directory (tail Bytes)) (→ (Result ZipDirectory String))
      (reading (lambda ()
                 (let* ((end (end-record tail))
                        (size (u32 tail (+ end 12)))
                        (start (u32 tail (+ end 16))))
                   (if (or (= size wide) (= start wide) (= (u16 tail (+ end 10)) 65535))
                       (zip64-directory tail end)
                       (new ZipDirectory (start start) (size size)))))))

    (define (end-record (tail Bytes)) (→ I64)
      (let loop ((at (- (array-length tail) 22)))
        (cond ((< at 0) (fail "the bytes read hold no archive's end record"))
              ((and (= (u32 tail at) 101010256)
                    (= (+ at (+ 22 (u16 tail (+ at 20)))) (array-length tail)))
               at)
              (else (loop (- at 1))))))

    ;; Zip64's locator is just before the end record, and its end record,
    ;; 56 bytes when it carries nothing more, just before the locator, as
    ;; archivers write them; the locator's own pointer to it is not needed.

    (define (zip64-directory (tail Bytes) (end I64)) (→ ZipDirectory)
      (let* ((locator (- end 20)) (record (- locator 56)))
        (unless (and (>= locator 0) (= (u32 tail locator) 117853008))
          (fail "the archive's end record has numbers too wide for it, and no Zip64 locator"))
        (unless (and (>= record 0) (= (u32 tail record) 101075792) (= (u64 tail (+ record 4)) 44))
          (fail "the archive's Zip64 end record is not just before its locator"))
        (new ZipDirectory (start (u64 tail (+ record 48))) (size (u64 tail (+ record 40))))))

    ;; ---- The directory ----

    ;; The members the directory at `start` of the archive holds, in the
    ;; archive's order, each with its span.

    (define (zip-entries (directory Bytes) (start I64)) (→ (Result (List ZipEntry) String))
      (reading (lambda ()
                 (spanned (list-sort (lambda (a b) (< (● a start) (● b start)))
                                     (directory-headers directory))
                          start))))

    ;; A header is 46 bytes, then the name, the extra fields and the
    ;; comment, whose lengths it gives.

    (define (directory-headers (directory Bytes)) (→ (List ZipEntry))
      (let loop ((at 0) (found (Nil)))
        (if (>= at (array-length directory))
            (reverse found)
            (loop (+ at
                     (+ 46 (+ (u16 directory (+ at 28))
                              (+ (u16 directory (+ at 30)) (u16 directory (+ at 32))))))
                  (Cons (directory-header directory at) found)))))

    ;; A member's header. Its length held and kept, and where its local
    ;; header is, are each read from Zip64's field when the header's own
    ;; is all ones.

    (define (directory-header (directory Bytes) (at I64)) (→ ZipEntry)
      (unless (= (u32 directory at) 33639248) (fail "the directory holds something not a header"))
      (let* ((name-length (u16 directory (+ at 28)))
             (extra (+ at (+ 46 name-length)))
             (numbers (widened directory
                               (zip64-field directory extra (+ extra (u16 directory (+ at 30))))
                               (list (u32 directory (+ at 24))
                                     (u32 directory (+ at 20))
                                     (u32 directory (+ at 42))))))
        (new ZipEntry
          (name (entry-name (subarray directory (+ at 46) extra)))
          (method (u16 directory (+ at 10)))
          (crc (u32 directory (+ at 16)))
          (compressed (list-ref numbers 1))
          (size (list-ref numbers 0))
          (start (list-ref numbers 2))
          (end 0))))

    ;; Where the data of the extra field with id 1, Zip64's, begins.

    (define (zip64-field (bytes Bytes) (at I64) (end I64)) (→ (Option I64))
      (cond ((> (+ at 4) end) (None))
            ((= (u16 bytes at) 1) (Some (+ at 4)))
            (else (zip64-field bytes (+ at (+ 4 (u16 bytes (+ at 2)))) end))))

    ;; Zip64's field holds, in order, eight bytes for each number that was
    ;; too wide, and nothing for the others.

    (define (widened (bytes Bytes) (field (Option I64)) (numbers (List I64))) (→ (List I64))
      (match numbers
        ((Nil) (Nil))
        ((Cons number rest)
         (cond ((not (= number wide)) (Cons number (widened bytes field rest)))
               (else
                (match field
                  ((Some at) (Cons (u64 bytes at) (widened bytes (Some (+ at 8)) rest)))
                  ((None)
                   (fail "a member's header has numbers too wide for it, and no Zip64 field"))))))))

    (define (entry-name (bytes Bytes)) (→ String)
      (match (utf8->string bytes)
        ((Ok name) name)
        ((Err _) (fail "a member's name is not UTF-8"))))

    ;; Each member's span ends where the next one's begins, and the last's
    ;; where the directory does. An archive may hold many thousands of
    ;; members, so this loops rather than recursing on each.

    (define (spanned (entries (List ZipEntry)) (directory I64)) (→ (List ZipEntry))
      (let loop ((entries entries) (done (Nil)))
        (match entries
          ((Nil) (reverse done))
          ((Cons entry rest)
           (loop rest
                 (Cons (ZipEntry-end-set entry
                                         (match rest
                                           ((Cons next _) (● next start))
                                           ((Nil) directory)))
                       done))))))

    ;; ---- Members ----

    ;; A member's bytes, from the archive's bytes over its span: a local
    ;; header of 30 bytes, then the name and extra fields again, which may
    ;; differ from the directory's, then the bytes as kept.

    (define (entry-contents (entry ZipEntry) (span Bytes)) (→ (Result Bytes String))
      (reading (lambda ()
                 (unless (= (u32 span 0) 67324752)
                   (fail (string-append (● entry name) " has no local header where it should")))
                 (when (= (i64-and (u16 span 6) 1) 1)
                   (fail (string-append (● entry name) " is encrypted")))
                 (let ((contents (held entry span (+ 30 (+ (u16 span 26) (u16 span 28))))))
                   (unless (= (crc32 contents) (● entry crc))
                     (fail (string-append (● entry name) " does not match its CRC-32")))
                   contents))))

    (define (held (entry ZipEntry) (span Bytes) (data I64)) (→ Bytes)
      (when (> (+ data (● entry compressed)) (array-length span))
        (fail (string-append (● entry name) " runs past its span")))
      (cond ((= (● entry method) 0)
             (unless (= (● entry compressed) (● entry size))
               (fail (string-append (● entry name) " is kept as it is, at another length")))
             (subarray span data (+ data (● entry size))))
            ((= (● entry method) 8)
             (match (inflate span data (● entry size))
               ((Ok contents) contents)
               ((Err why) (fail (string-append (● entry name) ": " why)))))
            (else
             (fail (string-append (● entry name)
                                  " is kept by method "
                                  (show (● entry method))
                                  ", which this reader does not decode")))))

    ;; ---- Checks ----

    ;; CRC-32, which an archive checks each member's bytes with: the
    ;; remainder of their bits, lowest first, divided by the polynomial
    ;; 0xEDB88320, a byte at a time through the table of what each byte's
    ;; eight steps make.

    (define crc-table (→ (Array I64))
      (array-generate 256
                      (lambda (byte)
                        (let loop ((c byte) (k 0))
                          (if (= k 8)
                              c
                              (loop (if (= (i64-and c 1) 1)
                                        (i64-xor 3988292384 (i64-shift-right/logical c 1))
                                        (i64-shift-right/logical c 1))
                                    (+ k 1)))))))

    (define (crc32 (bytes Bytes)) (→ I64)
      (let ((table crc-table))
        (let loop ((k 0) (c wide))
          (if (= k (array-length bytes))
              (i64-xor c wide)
              (loop (+ k 1)
                    (i64-xor (array-ref table
                                        (i64-and
                                         (i64-xor c (i32->i64 (u8->i32 (array-ref bytes k))))
                                         255))
                             (i64-shift-right/logical c 8)))))))

    ))
