;; Filesystem and process boundaries for the contributor tools. No program
;; compiled by Snail imports this host library.
(library (snail stage0 system)
  (export create-directory create-directory* delete-file-hierarchy path-directory path-normalize
          make-path file-link-status modification-nanoseconds file-size symbolic-link-file
          file-lock lock/exclusive lock/unlock string-contains string-suffix? string-split
          write-string read-string read-bytevector write-bytevector
          open-binary-input-file open-binary-output-file port->string error-text
          pinned-channel
          command-text
          run-command-status
          open-replacing-output-file
          call-with-replacing-output-file)
  (import
   (chezscheme))

  ;; ---- Paths and files ----

  (define (path-directory path)
    (let ([parent (path-parent path)]) (if (string=? parent "") "." parent)))
  (define (make-path . parts)
    (fold-left (lambda (path part) (if (string=? path "") part (string-append path "/" part)))
               ""
               parts))
  (define (path-normalize path)
    (let ([absolute? (path-absolute? path)])
      (let loop ([parts (string-split path #\/)] [kept '()])
        (cond [(null? parts)
               (let ([joined (apply make-path (reverse kept))])
                 (cond [absolute? (string-append "/" joined)]
                       [(string=? joined "") "."]
                       [else joined]))]
              [(member (car parts) '("" ".")) (loop (cdr parts) kept)]
              [(and (string=? (car parts) "..") (pair? kept) (not (string=? (car kept) "..")))
               (loop (cdr parts) (cdr kept))]
              [(and absolute? (string=? (car parts) "..")) (loop (cdr parts) kept)]
              [else (loop (cdr parts) (cons (car parts) kept))]))))

  (define (create-directory path . mode)
    (guard (condition [else #f])
      (mkdir path (if (null? mode) #o755 (car mode))) #t))
  (define (create-directory* path)
    (or (file-directory? path)
        (and (create-directory* (path-directory path))
             (or (create-directory path) (file-directory? path)))))
  (define (file-link-status path) (or (file-exists? path) (file-symbolic-link? path)))
  (define (delete-file-hierarchy path)
    (when (file-link-status path)
      (if (and (file-directory? path) (not (file-symbolic-link? path)))
          (begin (for-each (lambda (name) (delete-file-hierarchy (make-path path name)))
                           (directory-list path))
                 (delete-directory path))
          (delete-file path))))
  (define (modification-nanoseconds path)
    (let ([time (file-modification-time path)])
      (+ (* (time-second time) 1000000000) (time-nanosecond time))))
  (define (file-size path) (call-with-port (open-file-input-port path) file-length))

  ;; Chez loads libc through the current process. flock owns the descriptor
  ;; only while its port remains open; the caller closes it after unlocking.
  ;; A blocked waiter must let the lock holder collect and continue. Only
  ;; scalar descriptors cross this collect-safe call; no Scheme heap pointer.
  (define loaded-libc (load-shared-object #f))
  (define c-flock (foreign-procedure __collect_safe "flock" (int int) int))
  (define c-symlink (foreign-procedure "symlink" (string string) int))
  (define lock/exclusive 2)
  (define lock/unlock 8)
  (define (file-lock port operation)
    (unless (zero? (c-flock (port-file-descriptor port) operation))
      (error 'file-lock "cannot lock build directory")))
  (define (symbolic-link-file target path)
    (unless (zero? (c-symlink target path)) (error 'symlink "cannot create link" target path)))

  (define (pinned-channel root)
    (let* ((path (make-path root "rust-toolchain.toml"))
           (channel (quoted-value (call-with-input-file path port->string) "channel")))
      (or channel (error 'snail "rust-toolchain.toml must name a channel" path))))

  (define (quoted-value text key)
    (let* ((at (string-contains text key))
           (rest (and at (substring text at (string-length text))))
           (open (and rest (string-contains rest "\"")))
           (tail (and open
                      (substring rest
                                 (+ open 1)
                                 (string-length rest))))
           (close (and tail (string-contains tail "\""))))
      (and close (substring tail 0 close))))

  ;; ---- Text and ports ----

  (define (string-contains text part)
    (let ([length (string-length part)] [limit (- (string-length text) (string-length part))])
      (let loop ([index 0])
        (cond [(> index limit) #f]
              [(string=? (substring text index (+ index length)) part) index]
              [else (loop (+ index 1))]))))
  (define (string-suffix? suffix text)
    (let ([start (- (string-length text) (string-length suffix))])
      (and (>= start 0) (string=? (substring text start (string-length text)) suffix))))
  (define (string-split text delimiter)
    (let loop ([start 0] [index 0] [parts '()])
      (cond [(= index (string-length text)) (reverse (cons (substring text start index) parts))]
            [(char=? (string-ref text index) delimiter)
             (loop (+ index 1) (+ index 1) (cons (substring text start index) parts))]
            [else (loop start (+ index 1) parts)])))
  (define (open-replacing-output-file path)
    (open-file-output-port path (file-options no-fail) (buffer-mode block) (native-transcoder)))
  (define (call-with-replacing-output-file path use)
    (call-with-port (open-replacing-output-file path) use))
  (define (write-string text . ports)
    (put-string (if (null? ports) (current-output-port) (car ports)) text))
  (define (read-string count port) (get-string-n port count))
  (define (read-bytevector count port) (get-bytevector-n port count))
  (define (write-bytevector bytes port) (put-bytevector port bytes))
  (define (open-binary-input-file path) (open-file-input-port path))
  (define (open-binary-output-file path) (open-file-output-port path (file-options no-fail)))
  (define (port->string port) (let ([text (get-string-all port)]) (if (eof-object? text) "" text)))
  (define (error-text condition)
    (cond [(syntax-violation? condition)
           (call-with-string-output-port (lambda (port) (display-condition condition port)))]
          [(message-condition? condition)
           (if (format-condition? condition)
               (apply format (condition-message condition) (condition-irritants condition))
               (string-append (condition-message condition)
                              (apply string-append (map (lambda (value) (format " ~s" value))
                                                        (if (irritants-condition? condition)
                                                            (condition-irritants condition)
                                                            '())))))]
          [else (format "~s" condition)]))

  ;; ---- Commands ----

  ;; Shell words are quoted individually, including empty strings and quotes.
  ;; No command argument can become a substitution or a redirection.

  (define (shell-word text)
    (unless (and (string? text) (not (string-contains text (string #\nul))))
      (error 'command "expected an argument without NUL" text))
    (string-append "'"
                   (apply string-append
                          (map (lambda (char) (if (char=? char #\') "'\"'\"'" (string char)))
                               (string->list text)))
                   "'"))
  (define (command-text arguments)
    (unless (and (pair? arguments) (not (string=? (car arguments) ""))
                 (not (char=? (string-ref (car arguments) 0) #\-)))
      (error 'command "expected a tool name" arguments))
    (fold-left (lambda (text arg) (string-append text " " (shell-word arg)))
               (shell-word (car arguments)) (cdr arguments)))
  (define (run-command-status arguments)
    ;; The tool protocol uses POSIX wait statuses, including signal deaths.
    (let ([status (system (command-text arguments))]) (if (< status 0) (- status) (* status 256))))
  )
