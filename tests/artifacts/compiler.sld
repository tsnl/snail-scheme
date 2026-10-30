;; A compiler running as Wasm supplies immutable artifact inputs. Its
;; output exercises both static linking and cached per-library emission,
;; each module assembled in-process, as the toolchain's runtime it links
;; with allows.
(import
 (snail core base)
 (snail core io)
 (snail core table)
 (snail shell assembler)
 (snail shell compiler)
 (snail shell compiler inputs)
 (snail shell compiler session)
 (prefix (snail shell compiler read) reader:)
 (prefix (snail shell syntax) generated:))

(: inputs (-> Bytes Inputs))
(define (inputs client)
  (supply-artifact (supply-artifact no-inputs "client" (list (Pair "client.dat" client)))
                   "admin" (list (Pair "admin.dat" #u8(99)))))

(: generate (-> (List String) (List reader:Syntax) Bytes))
(define (generate loading forms)
  (generated:syntax->bytes
   (generated:library-syntax
    (list "generated" "assets")
    (list "generated-bundle")
    (list (list "snail" "core" "base") (list "snail" "shell" "artifact"))
    (list (generated:form ":"
                          (list (generated:SymbolSyntax "generated-bundle")
                                (generated:SymbolSyntax "ArtifactBundle")))
          (generated:form "define" (list (generated:SymbolSyntax "generated-bundle")
                                         (generated:form "artifact-bundle"
                                                         (list
                                                          (generated:StringSyntax "client")))))))))

(: write-module (-> String String Unit ! fs))
(define (write-module path text)
  (match (assemble text)
    ((Ok bytes) (write-bytes path bytes))
    ((Err message) (panic (string-append "could not assemble " path ": " message)))))

(: write-build (-> String (List Built) Unit ! fs))
(define (write-build output built)
  (for-each (lambda (module)
              (write-module (string-append output "/" (Built-name module) ".wasm")
                            (Built-text module)))
            built)
  (write-file (string-append output "/modules") (string-join (map Built-name built) "\n"))
  (write-file (string-append output "/compiled")
              (string-join (map Built-name (filter Built-compiled? built)) "\n")))

;; Every input is supplied, so the compiles ask for none, and the source
;; has no errors.
(: compile-all (-> String String (List String) Unit ! mut fs reader:compile))
(define (compile-all source output directories)
  (write-module (string-append output "/program.wasm")
                (WholeProgram-text
                 (source->wat directories source generate (inputs #u8(65 0 255)))))
  (let* ((first (build-session (make-session directories) source generate (inputs #u8(65 0 255))))
         (unchanged (build-session (Pair-second first) source generate (inputs #u8(65 0 255)))))
    (write-build (string-append output "/first") (Pair-first first))
    (write-build (string-append output "/unchanged") (Pair-first unchanged))
    (write-build (string-append output "/changed")
                 (Pair-first (build-session (Pair-second unchanged)
                                            source
                                            generate
                                            (inputs #u8(90 0 255)))))))

(match (command-line)
  ((Cons _ (Cons source (Cons output directories)))
   (match (reader:compiling (lambda () (compile-all source output directories)))
     ((Ok _) (unit))
     ((Err (reader:Failed diagnostic)) (panic (reader:diagnostic->string diagnostic)))
     ((Err (reader:Requested _)) (panic "the compiles asked for an input they were supplied"))))
  (_ (panic "usage: compiler SOURCE OUTPUT LIBRARY ...")))
