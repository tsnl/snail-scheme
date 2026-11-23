;; Zip archives on the web, pinned, read a member at a time and kept in the
;; machine's cache: what a generated library's recipe fetches, as a
;; dataset's does ((datasets mipnerf360)).
;;
;; A `WebZip` names an archive by its URL and pins it by the SHA-256 of
;; its end: its directory and the records after it, which give every
;; member's name, length, CRC-32 and place. The pin is what makes caching
;; correct, whatever the server does later: an archive whose end has
;; another digest fails, naming the one it has, and each member's bytes
;; are checked against the pinned directory's CRC-32 before they are kept.
;; So what the cache holds was read from the archive the recipe names, and
;; a build that finds it there needs no network. The machine's cache is
;; shared by every workspace on it:
;;
;;   CACHE/zip/PIN.end    the archive's end, as pinned
;;   CACHE/zip/PIN/NAME   each member read, by its name in the archive
;;
;; CACHE is snail-scheme in $XDG_CACHE_HOME, or ~/.cache/snail-scheme. A
;; file is written in a folder beside its place that this process alone
;; made, then renamed into it, so a reader sees all of it or none, and two
;; builds that fetch one member at once each rename the same bytes. A
;; fetch that fails stops the build, and the members it kept stay kept,
;; so the next build fetches only the rest. Members are read eight at a
;; time, which takes stump's 125 MB in 16 seconds where one at a time
;; takes 38. Nothing reclaims the cache: deleting any of it costs only
;; fetching it again.
(define-library (snail shell web zip)
  (export
   WebZip
   machine-cache
   zip-members)
  (import
   (snail core base)
   (snail core io)
   (snail shell web)
   (snail shell zip)
   (only (snail shell compiler sha256) sha256 bytes->hex))
  (begin

    ;; ---- Archives ----

    ;; An archive's URL, and the SHA-256 of its end, in lowercase hex.
    (record WebZip
      ((url String)
       (end String)))

    (define (parsed (result (Result T String))) (→ T) (∀ (T))
      (match result
        ((Ok value) value)
        ((Err why) (panic why))))

    ;; ---- The cache ----

    (define (machine-cache (environment ProcessEnvironment)) (→ String)
      (match ((● environment variable) "XDG_CACHE_HOME")
        ((Some home)
         (if (string=? home "") (home-cache environment) (string-append home "/snail-scheme")))
        ((None) (home-cache environment))))

    (define (home-cache (environment ProcessEnvironment)) (→ String)
      (match ((● environment variable) "HOME")
        ((Some home) (string-append home "/.cache/snail-scheme"))
        ((None) (panic "there is no HOME to keep the machine's cache in"))))

    ;; Bytes written in a folder made beside their place, then renamed into
    ;; it. Making a folder fails when one is there, so no two writers share
    ;; one; a writer that stopped midway leaves its folder, and the next
    ;; takes the next name.

    (define (keep! (fs Fs) (path String) (bytes Bytes)) (→ Unit)
      (expect-done (make-directories fs (parent path))
                   (string-append "cannot make the folder of " path))
      (let* ((folder (fresh-folder fs (string-append path ".writing-") 0))
             (writing (string-append folder "/bytes")))
        (write-bytes fs writing bytes)
        (expect-done (rename-file fs writing path) (string-append "cannot keep " path))
        (expect-done (remove-directory fs folder) (string-append "cannot remove " folder))))

    (define (fresh-folder (fs Fs) (stem String) (n I64)) (→ String)
      (let ((folder (string-append stem (show n))))
        (match (make-directory fs folder)
          ((Ok _) folder)
          ((Err (AlreadyExists)) (fresh-folder fs stem (+ n 1)))
          ((Err error) (panic (string-append "cannot make " folder ": " (show error)))))))

    (define (expect-done (result (Result Unit FileError)) (why String)) (→ Unit)
      (match result
        ((Ok _) (unit))
        ((Err error) (panic (string-append why ": " (show error))))))

    (define (parent (path String)) (→ String)
      (let loop ((index (- (string-length path) 1)))
        (cond ((<= index 0) "/")
              ((char=? (string-ref path index) #\/) (substring path 0 index))
              (else (loop (- index 1))))))

    ;; ---- The end ----

    ;; The archive's end, the cache's while it has the pinned digest, or
    ;; else the web's, which must.

    (define (archive-end (fs Fs) (web Web) (archive WebZip) (path String)) (→ Bytes)
      (match (if (file-exists? fs path) (pinned archive (read-bytes fs path)) (None))
        ((Some end) end)
        ((None)
         (let ((end (fetched-end web archive)))
           (match (pinned archive end)
             ((Some end) (keep! fs path end) end)
             ((None)
              (panic (string-append "the end of "
                                    (● archive url)
                                    " has the SHA-256 "
                                    (bytes->hex (sha256 end))
                                    ", not the pinned "
                                    (● archive end)))))))))

    (define (pinned (archive WebZip) (end Bytes)) (→ (Option Bytes))
      (if (string=? (bytes->hex (sha256 end)) (● archive end)) (Some end) (None)))

    ;; The archive's last bytes say where its directory starts, and its
    ;; end runs from there.

    (define (fetched-end (web Web) (archive WebZip)) (→ Bytes)
      (let* ((url (● archive url))
             (size (parsed ((● web size) url)))
             (tail (one-part web url (max 0 (- size end-bytes)) (min size end-bytes)))
             (start (● (parsed (zip-directory tail)) start)))
        (one-part web url start (- size start))))

    (define (one-part (web Web) (url String) (start I64) (count I64)) (→ Bytes)
      (parsed (list-ref ((● web parts) url (list (new Span (start start) (count count)))) 0)))

    ;; The members the end's directory holds.

    (define (archive-entries (end Bytes)) (→ (List ZipEntry))
      (let ((directory (parsed (zip-directory end))))
        (parsed (zip-entries (subarray end 0 (● directory size)) (● directory start)))))

    ;; ---- Members ----

    ;; The members of `archive` whose names `wanted` takes, but not its
    ;; folders, each with the path of its file in the cache `cache`: kept
    ;; there already, or read from the web now, eight at a time.

    (define (zip-members (fs Fs) (web Web)
                         (cache String)
                         (archive WebZip)
                         (wanted (Fn String → Bool)))
      (→ (List (Pair String String)))
      (let* ((root (string-append cache "/zip/" (● archive end)))
             (entries (filter (lambda (entry) (and (not (folder? entry)) (wanted (● entry name))))
                              (archive-entries
                               (archive-end fs web archive (string-append root ".end"))))))
        (keep-members! fs
                       web
                       archive
                       root
                       (filter (lambda (entry) (not (kept? fs root entry))) entries))
        (map (lambda (entry) (new Pair (first (● entry name)) (second (member-path root entry))))
             entries)))

    (define (folder? (entry ZipEntry)) (→ Bool)
      (let ((name (● entry name)))
        (and (> (string-length name) 0) (char=? (string-ref name (- (string-length name) 1)) #\/))))

    ;; A member's file is at its name under the archive's folder, so its
    ;; name must stay there: no empty part, no `.` or `..`, and not
    ;; absolute.

    (define (member-path (root String) (entry ZipEntry)) (→ String)
      (let ((name (● entry name)))
        (when (any? (lambda (part) (member? part (list "" "." "..")))
                    (split-name name))
          (panic (string-append "the archive's member " name " would leave its folder")))
        (string-append root "/" name)))

    (define (split-name (name String)) (→ (List String))
      (match (string-index name #\/)
        ((Some at)
         (Cons (substring name 0 at) (split-name (substring name (+ at 1) (string-length name)))))
        ((None) (list name))))

    ;; A member is kept once its file has the member's length: it is
    ;; written whole or not at all.

    (define (kept? (fs Fs) (root String) (entry ZipEntry)) (→ Bool)
      (match (file-status fs (member-path root entry))
        ((Ok status) (= (● status size) (● entry size)))
        ((Err _) #f)))

    (define (keep-members! (fs Fs) (web Web)
                           (archive WebZip)
                           (root String)
                           (entries (List ZipEntry)))
      (→ Unit)
      (unless (null? entries)
        (let ((batch (take entries 8)))
          (for-each (lambda (read)
                      (let ((entry (● read first)))
                        (keep! fs (member-path root entry)
                               (parsed (entry-contents entry (parsed (● read second)))))))
                    (zip batch
                         ((● web parts) (● archive url)
                          (map (lambda (entry)
                                 (new Span
                                   (start (● entry start))
                                   (count (- (● entry end) (● entry start)))))
                               batch))))
          (keep-members! fs web archive root (list-drop entries 8)))))

    ))
