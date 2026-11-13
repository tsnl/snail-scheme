;; A compiler running as Wasm supplies immutable artifact inputs. Its
;; output exercises both static linking and fresh per-library emission,
;; each module assembled in-process, as the toolchain's runtime it links
;; with allows.
(import
 (snail core base)
 (snail core io)
 (snail core table)
 (snail shell assembler)
 (snail shell compiler)
 (snail shell compiler inputs)
 (prefix (snail shell compiler read) reader:)
 (prefix (snail shell syntax) generated:))

(define (inputs (client Bytes)) (→ Inputs)
  (supply-artifact (supply-artifact (no-inputs) "client" (list (Pair "client.dat" client)))
                   "admin" (list (Pair "admin.dat" #u8(99)))))

(define (generate (loading (List String)) (forms (List reader:Syntax))) (→ Bytes)
  (generated:syntax->bytes
   (generated:library-syntax
    (list "generated" "assets")
    (list "generated-bundle")
    (list (list "snail" "core" "base") (list "snail" "shell" "artifact"))
    (list (generated:form "define"
                          (list (generated:form "generated-bundle" (Nil))
                                (generated:form "→"
                                                (list (generated:SymbolSyntax "ArtifactBundle")))
                                (generated:form "artifact-bundle"
                                                (list (generated:StringSyntax "client")))))))))

(define (write-module (path String) (text String)) (→ Unit) (! fs)
  (match (assemble text)
    ((Ok bytes) (write-bytes path bytes))
    ((Err message) (panic (string-append "could not assemble " path ": " message)))))

(define (write-build (output String) (built (List Built))) (→ Unit) (! fs)
  (for-each (lambda (module)
              (write-module (string-append output "/" (● module name) ".wasm")
                            (● module text)))
            built)
  (write-file (string-append output "/modules")
              (string-join (map (lambda (record) (● record name)) built) "\n"))
  )

;; Every input is supplied, so the compiles ask for none, and the source
;; has no errors.
(define (compile-all (source String) (output String) (directories (List String)))
  (→ Unit)
  (! mut fs reader:compile)
  (write-module (string-append output "/program.wasm")
                (● (source->wat directories source generate (inputs #u8(65 0 255))) text))
  (write-build (string-append output "/first")
               (source->modules directories source generate (inputs #u8(65 0 255))))
  (write-build (string-append output "/unchanged")
               (source->modules directories source generate (inputs #u8(65 0 255))))
  (write-build (string-append output "/changed")
               (source->modules directories source generate (inputs #u8(90 0 255)))))

(define (main) (→ Unit) (! mut fs)

  (match (command-line)
    ((Cons _ (Cons source (Cons output directories)))
     (match (reader:compiling (lambda () (compile-all source output directories)))
       ((Ok _) (unit))
       ((Err (reader:Failed diagnostics)) (panic (reader:diagnostics->string diagnostics)))
       ((Err (reader:Requested _)) (panic "the compiles asked for an input they were supplied"))))
    (_ (panic "usage: compiler SOURCE OUTPUT LIBRARY ...")))
  (unit))
