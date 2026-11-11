;; Supply, what the build found for `bind` to bind one expanded library
;; with: the digest of each file it read, by the file's path, and the
;; files of every target its caller supplied, by target, whichever the
;; library asks for. When the library is a producer program's printed
;; copy, the Supply also names the copy and the recipe it stands for.
;;
;;   Supply      ::= Supply PrintedCopy? digest-by-file TargetFile*-by-target   no Loc
;;   PrintedCopy ::= PrintedCopy copy recipe                          no Loc
;;   TargetFile  ::= TargetFile path bytes                            no Loc
;;
;; Nothing in a Supply is promised complete. A file a library links has no
;; digest when the build found no file there, and a target a library asks
;; for may not be supplied: what a miss means is `bind`'s to decide. A
;; digest is the SHA-256 of the file's bytes in lowercase hex, and a
;; target's files are relative paths with their bytes, in path order.
(define-library (snail compiler bind supply)
  (export
   Supply
   PrintedCopy
   TargetFile)
  (import
   (snail core base)
   (snail core table))
  (begin

    (struct Supply
      ((printed (Option PrintedCopy))
       (digests (Table String))
       (targets (Table (List TargetFile)))))

    ;; The file a producer program is printed to, and the recipe it was
    ;; printed from.
    (struct PrintedCopy
      ((copy String)
       (recipe String)))

    (struct TargetFile
      ((path String)
       (bytes Bytes)))

    ))
