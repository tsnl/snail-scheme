(import
 (snail core base)
 (snail core io)
 (snail shell gitignore)
 (snail shell process)
 (snail shell task)
 (snail shell utf8))

;; Build an independent worktree so this repository's own excludes and index
;; cannot decide the answers. No commits or user identity are needed.
(: git (impl (Fn String (List String) -> String ! process)))
(define (git directory arguments)
  (match (run (Command "git" arguments directory) #u8())
    ((Ok result)
     (match (::exit result)
       ((Exited 0)
        (match (utf8->string (::stdout result))
          ((Ok text) text)
          ((Err _) (panic "Git output is not UTF-8"))))
       (_ (panic "Git fixture setup failed"))))
    ((Err error) (panic (::code error)))))

(: repository String)
(define repository (git "." (list "rev-parse" "--show-toplevel")))
(: root String)
(define root (string-append (substring repository 0 (- (string-length repository) 1))
                            "/build/tests/gitignore"))
(: at (impl (Fn String -> String)))
(define (at path) (string-append root "/" path))

(: snapshot (impl (Fn String -> IgnoreSnapshot ! mut tasks process)))
(define (snapshot directory)
  (match (read-gitignore directory)
    ((Ok (Some value)) value)
    ((Ok (None)) (panic "Git fixture unavailable"))
    ((Err message) (panic message))))

(: report (impl (Fn IgnoreSnapshot String -> Unit ! console)))
(define (report rules path)
  (write-line (string-append path ": " (if (ignored? rules path) "ignored" "visible"))))

(remove-tree root)
(make-directories (at "hidden/deep"))
(make-directories (at "project[n]/deep"))
(make-directories (at "lib/cache"))
(git root (list "init" "-q"))
(git root (list "config" "core.excludesFile" (at ".git/global-ignore")))
(write-file (at ".git/global-ignore") "global.txt\n")
(write-file (at ".git/info/exclude") "local.txt\n")
(write-file (at ".gitignore")
            "*.tmp\n!keep.tmp\nhidden/\n!hidden/untracked.txt\n/project[n]/\n/project\\[n\\]/\nlib/cache/\n")
(write-file (at "lib/.gitignore") "!keep.tmp\n**/generated?.txt\n")
(for-each (lambda (path) (write-file (at path) "content"))
          (list "main.sld" "drop.tmp" "keep.tmp" "global.txt" "local.txt"
                "hidden/tracked.txt" "hidden/untracked.txt" "hidden/deep/lost.txt"
                "project[n]/deep/file.txt" "lib/keep.tmp" "lib/drop.tmp" "lib/generated1.txt"
                "lib/cache/file.txt" "line\nbreak.tmp" "élan.tmp"))
(git root (list "add" "-f" "hidden/tracked.txt"))

(let ((rules (snapshot root)))
  (for-each (lambda (path) (report rules path))
            (list "main.sld" "drop.tmp" "keep.tmp" "global.txt" "local.txt" "hidden"
                  "hidden/tracked.txt" "hidden/untracked.txt" "hidden/deep" "hidden/deep/lost.txt"
                  "lib/keep.tmp" "lib/drop.tmp" "lib/generated1.txt" "lib/cache" "élan.tmp"))
  (write-line
   (if (ignored? rules "line\nbreak.tmp") "newline path: ignored" "newline path: visible")))
(report (snapshot (at "project[n]/deep")) "file.txt")
(match (make-symbolic-link "project[n]/deep" (at "alias"))
  ((Ok _) (unit))
  ((Err error) (panic (show error))))
(report (snapshot (at "alias")) "file.txt")
(report (snapshot (at "lib")) "keep.tmp")

;; A changed rule affects the next snapshot; one already returned stays a value.
(let ((before (snapshot root)))
  (write-file (at ".gitignore") "")
  (report before "drop.tmp")
  (report (snapshot root) "drop.tmp"))

;; Ordinary directories remain usable. The absence is explicit to consumers.
(match (read-gitignore "/")
  ((Ok (None)) (write-line "outside a repository: unavailable"))
  (_ (panic "expected no repository at /")))
(remove-tree root)
(unit)
