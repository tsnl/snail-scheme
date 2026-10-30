(import
 (snail core base)
 (snail core io)
 (snail shell project files))

;; The project file service on a scratch project: what it lists, reads and
;; refuses, a save that names the revision it replaces and one that does
;; not, a save that keeps the file's mode, and nothing left in the build
;; output after. Each line is a request and what the service answered.
(define root "build/tests/project-files")

(: at (-> String String))
(define (at name)
  (string-append root "/" name))

(: report (-> String String Unit ! console))
(define (report label text)
  (write-line (string-append label " -> " text)))

(: refusal->string (-> FileRefusal String))
(define (refusal->string refusal)
  (match refusal
    ((ChangedOnDisk) "changed on disk")
    ((NotServed message) (string-append "not served: " message))
    ((DiskFailed error) (string-append "disk failed: " (show error)))))

(: text-report (-> String (Result ProjectText FileRefusal) Unit ! console))
(define (text-report label result)
  (report label (match result
                  ((Ok text)
                   (string-append (ProjectText-text text)
                                  " at "
                                  (substring (ProjectText-revision text) 0 12)))
                  ((Err refusal) (refusal->string refusal)))))

(: read-report (-> String Unit ! console fs))
(define (read-report path)
  (text-report (string-append "read " path) (read-project-text root path)))

;; The revision of the file at `path` now, which a save names.
(: revision-of (-> String String ! fs))
(define (revision-of path)
  (match (read-project-text root path)
    ((Ok text) (ProjectText-revision text))
    ((Err _) "")))

(: mode-report (-> String Unit ! console modes))
(define (mode-report path)
  (report (string-append "mode of " path) (match (file-mode (at path))
                                            ((Some mode) (number->octal mode))
                                            ((None) "none"))))

(: number->octal (-> I32 String))
(define (number->octal number)
  (if (< number 8)
      (show number)
      (string-append (number->octal (quotient number 8)) (show (remainder number 8)))))

(remove-tree root)
(make-directories (at "lib"))
(make-directories (at ".git"))
(make-directories (at "build"))
(write-file (at "main.sld") "(main)")
(write-file (at "lib/util.sld") "(util)")
(write-file (at "README.MD") "readme")
(write-file (at "notes.bin") "bytes")
(write-file (at ".git/config") "git")
(write-file (at "build/out.sld") "built")
(write-file (at "tool.mjs") "tool")
(make-symbolic-link "lib" (at "linked"))
(set-file-mode (at "tool.mjs") 493)

(report "list"
        (match (project-text-paths root
                                   (map at
                                        (list "tool.mjs" "main.sld" "lib/util.sld" "README.MD"
                                              "notes.bin" ".git/config" "build/out.sld"
                                              "linked/util.sld")))
          ((Ok paths) (string-join paths " "))
          ((Err refusal) (refusal->string refusal))))
(report "list another project's paths"
        (match (project-text-paths root
                                   (list "elsewhere/main.sld" (string-append root "x/main.sld")))
          ((Ok paths) (string-append "(" (string-join paths " ") ")"))
          ((Err refusal) (refusal->string refusal))))

(read-report "main.sld")
(read-report "lib/util.sld")
(read-report "README.MD")
(read-report "notes.bin")
(read-report "../project-files/main.sld")
(read-report "./main.sld")
(read-report "lib//util.sld")
(read-report "/main.sld")
(read-report "build/out.sld")
(read-report ".git/config")
(read-report "lib\\util.sld")
(read-report "linked/util.sld")
(read-report "missing.sld")

(let ((before (revision-of "main.sld")))
  (text-report "save main.sld" (save-project-text root "main.sld" before "(main 2)"))
  (read-report "main.sld")
  (text-report "save main.sld again from the old revision"
               (save-project-text root "main.sld" before "(main 3)"))
  (read-report "main.sld"))
(text-report "save a NUL"
             (save-project-text root "main.sld" (revision-of "main.sld") (make-string 1 #\null)))
(text-report "save a path not served" (save-project-text root "notes.bin" "" "text"))
(text-report "save a file not there" (save-project-text root "missing.sld" "" "text"))

(mode-report "tool.mjs")
(text-report "save tool.mjs" (save-project-text root "tool.mjs" (revision-of "tool.mjs") "tool 2"))
(mode-report "tool.mjs")
(set-file-mode (at "tool.mjs") 384)
(text-report "save tool.mjs again"
             (save-project-text root "tool.mjs" (revision-of "tool.mjs") "tool 3"))
(mode-report "tool.mjs")

(report "build output after" (match (list-directory (at "build"))
                               ((Ok names) (string-join names " "))
                               ((Err error) (show error))))
(remove-tree root)
