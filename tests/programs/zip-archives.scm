;; Zip archives and the DEFLATE streams their members are kept in, read by
;; (snail shell zip) and (snail shell inflate) from data/notes.zip, a small
;; archive in Zip64's form: every member's numbers are in its Zip64
;; field, and the directory is found through Zip64's end record. Its
;; members are a folder; a file kept as it is; deflated files coded by the
;; fixed codes, by codes of their own, and in stored blocks; an empty one;
;; a run of bytes copied over itself; and one whose rarest bytes have
;; codes longer than the decoder's table, read a bit at a time. Each reads
;; back at its length and CRC-32. Damaged bytes, streams and lengths fail,
;; each saying why.
(import
 (snail core base)
 (snail core io)
 (snail shell resource)
 (snail shell zip)
 (snail shell inflate)
 (only (snail shell utf8) utf8->string string->utf8)
 (only (snail shell compiler sha256) sha256 bytes->hex))

(define (archive) (→ Resource) (link-file "data/notes.zip"))

(define (ok (result (Result T String))) (→ T) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err why) (panic why))))

(define (told (result (Result Bytes String))) (→ String)
  (match result
    ((Ok bytes) (string-append "read " (show (array-length bytes)) " bytes"))
    ((Err why) why)))

;; A member's text, quoted, when it is short and UTF-8, or else its
;; digest's start.
(define (contents (bytes Bytes)) (→ String)
  (match (utf8->string bytes)
    ((Ok text) (if (< (string-length text) 48) (quoted text) (digest bytes)))
    ((Err _) (digest bytes))))

(define (quoted (text String)) (→ String)
  (string-append "\""
                 (string-concatenate
                  (map (lambda (char) (if (char=? char #\newline) "\\n" (list->string (list char))))
                       (string->list text)))
                 "\""))

(define (digest (bytes Bytes)) (→ String)
  (string-append "sha256 " (substring (bytes->hex (sha256 bytes)) 0 16)))

(define (span (bytes Bytes) (entry ZipEntry)) (→ Bytes)
  (subarray bytes (● entry start) (● entry end)))

(define (describe (entry ZipEntry) (read (Result Bytes String))) (→ String)
  (string-append (● entry name)
                 ", method "
                 (show (● entry method))
                 ", "
                 (show (● entry compressed))
                 " kept, "
                 (show (● entry size))
                 " held, CRC "
                 (show (● entry crc))
                 ": "
                 (match read
                   ((Ok bytes) (contents bytes))
                   ((Err why) why))))

(define (main (resources Resources) (out OutputPort)) (→ Unit)
  (let* ((bytes (read-resource resources (archive)))
         (size (array-length bytes))
         (directory (ok (zip-directory (subarray bytes (max 0 (- size end-bytes)) size))))
         (start (● directory start))
         (entries (ok (zip-entries (subarray bytes start (+ start (● directory size))) start)))
         (named (lambda (name)
                  (match (find (lambda (entry) (string=? (● entry name) name)) entries)
                    ((Some entry) entry)
                    ((None) (panic name))))))
    (write-line out
                (string-append "the directory is at "
                               (show start)
                               ", "
                               (show (● directory size))
                               " bytes, of "
                               (show (length entries))
                               " members"))
    (for-each
     (lambda (entry) (write-line out (describe entry (entry-contents entry (span bytes entry)))))
     entries)
    (write-line out
                (string-append "CRC-32 of 123456789: " (show (crc32 (string->utf8 "123456789")))))
    (let* ((stored (named "notes/stored.txt"))
           (damaged (array-copy (span bytes stored))))
      (array-set! damaged 50 (i32->u8 88))
      (write-line out (string-append "a damaged byte: " (told (entry-contents stored damaged)))))
    (let ((dynamic (named "notes/dynamic.txt")))
      (write-line out
                  (string-append "half a stream: "
                                 (told (inflate (subarray (span bytes dynamic) 0 120)
                                                47
                                                (● dynamic size)))))
      (write-line out
                  (string-append "a byte too few: "
                                 (told (inflate (span bytes dynamic) 47 (- (● dynamic size) 1)))))
      (write-line out
                  (string-append "a byte too many: "
                                 (told (inflate (span bytes dynamic) 47 (+ (● dynamic size) 1))))))
    (write-line out (string-append "a block of type 3: " (told (inflate #u8(7) 0 0))))
    (write-line out
                (string-append "no archive: "
                               (match (zip-directory (make-array 100 (i32->u8 0)))
                                 ((Ok _) "a directory")
                                 ((Err why) why))))))
