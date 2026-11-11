;; Supply, what the build supplies `bind` for one expanded library: each
;; file the library links, as the integrator found it, and the files of
;; each target the library asks for.
;;
;;   Supply      ::= Supply FoundLink* TargetFiles*                  no Loc
;;   FoundLink   ::= FoundLink name* digest file
;;   TargetFiles ::= TargetFiles target TargetFile*                  no Loc
;;   TargetFile  ::= TargetFile path bytes                           no Loc
;;
;; A Supply guarantees that it holds a FoundLink for each path the
;; library's links name, as (snail compiler expand links) answers them,
;; once for each path, in the order the library first names it and at
;; that place, and nothing else: `name*` is the path, `file` the file the
;; build read, and `digest` the SHA-256 of its bytes in lowercase hex. It
;; holds the files of each target (snail compiler expand targets) answers,
;; once each, as the build supplied them: relative paths with their bytes,
;; in path order.
(define-library (snail compiler bind supply)
  (export
   Supply
   FoundLink
   TargetFiles
   TargetFile)
  (import
   (snail core base)
   (snail compiler source))
  (begin

    (struct Supply
      ((links (List FoundLink))
       (targets (List TargetFiles))))

    (struct FoundLink
      ((path (List String))
       (digest String)
       (file String)
       (loc Loc)))

    (struct TargetFiles
      ((target String)
       (files (List TargetFile))))

    (struct TargetFile
      ((path String)
       (bytes Bytes)))

    ))
