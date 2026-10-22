;; A compiler that keeps running between builds, as a development server's
;; does, and compiles each library to its own module. A session is a value:
;; each build returns the session the next one starts from. A build expands
;; only the libraries whose declarations, or whose imports' interfaces,
;; changed since the build before, and replays the others. It checks,
;; specializes and emits only the libraries whose expansion changed, and
;; keeps every other library's checked items and module text from the build
;; that made them, all in memory.
(define-library (lofi compiler session)
  (export
   Session
   make-session
   Built
   Built-name
   Built-text
   Built-interface
   Built-compiled?
   build-session)
  (import
   (lofi base)
   (lofi table)
   (lofi io)
   (lofi compiler read)
   (lofi compiler core)
   (lofi compiler expand)
   (lofi compiler check)
   (lofi compiler mono)
   (lofi compiler wasm))
  (begin

    ;; ---- Sessions ----

    ;; What one library's expansion became: its checked items, the schemes
    ;; of its own definitions, and its module's text, empty until it is
    ;; emitted. `version` names the expansion it was made from.
    (struct Compiled
      ((version String)
       (items (List Item))
       (schemes (Table Scheme))
       (text String)))

    ;; Where libraries are found, how generated ones are made, the last
    ;; build's expansion, and each library as last compiled.
    (struct Session
      ((directories (List String))
       (generate (-> (List Syntax) Bytes ! mut fs))
       (expansion (Option ExpandedProgram))
       (compiled (Table Compiled))))

    ;; One library's module after a build: whether this build compiled it,
    ;; and the interface the modules that import it were compiled against.
    (struct Built
      ((name String)
       (text String)
       (interface String)
       (compiled? Bool)))

    (: make-session (-> (List String) (-> (List Syntax) Bytes ! mut fs) Session))
    (define (make-session directories generate)
      (Session directories generate (None) empty-table))

    ;; ---- Builds ----

    ;; The modules of the program at `source`, in program order, and the
    ;; session after the build.
    (: build-session (-> Session String (Pair (List Built) Session) ! mut fs))
    (define (build-session session source)
      (let* ((expansion (expand-program (Session-directories session) (Session-generate session) source (Session-expansion session)))
             (program (ExpandedProgram-program expansion)) (libraries (library-items program (program-items program)))
             (checked (check-libraries (Session-compiled session) expansion libraries))
             (built (emit-libraries (Pair-second checked) expansion (Pair-first checked) libraries)))
        (Pair (Pair-first built) (Session (Session-directories session) (Session-generate session) (Some expansion) (Pair-second built)))))

    ;; Checks each library whose expansion changed, after the schemes of the
    ;; libraries before it, and returns the whole program checked, with each
    ;; library as compiled now.
    (: check-libraries (-> (Table Compiled) ExpandedProgram (List (Pair String (List Item))) (Pair Typed (Table Compiled)) ! mut))
    (define (check-libraries compiled expansion libraries)
      (let loop ((libraries libraries) (compiled compiled) (items (Nil)) (schemes empty-table))
        (match libraries
          ((Cons library rest)
           (let ((checked (checked-library compiled expansion schemes library)))
             (loop rest (table-set compiled (Pair-first library) checked) (append items (Compiled-items checked))
                   (table-union schemes (Compiled-schemes checked)))))
          ((Nil) (Pair (Typed (ExpandedProgram-program expansion) items schemes) compiled)))))

    ;; A library as compiled before, if made from its current expansion, or
    ;; checked again.
    (: checked-library (-> (Table Compiled) ExpandedProgram (Table Scheme) (Pair String (List Item)) Compiled ! mut))
    (define (checked-library compiled expansion schemes library)
      (let ((version (library-version expansion (Pair-first library))))
        (match (table-ref compiled (Pair-first library))
          ((Some before) (if (string=? (Compiled-version before) version) before (check-anew expansion schemes library version)))
          ((None) (check-anew expansion schemes library version)))))

    (: check-anew (-> ExpandedProgram (Table Scheme) (Pair String (List Item)) String Compiled ! mut))
    (define (check-anew expansion schemes library version)
      (let ((typed (check-library (ExpandedProgram-program expansion) schemes (Pair-second library))))
        (Compiled version (Typed-items typed) (own-schemes (Typed-schemes typed) (Typed-items typed)) "")))

    ;; Each library's module: the one emitted before, or, for a library just
    ;; checked, a new one.
    (: emit-libraries (-> (Table Compiled) ExpandedProgram Typed (List (Pair String (List Item))) (Pair (List Built) (Table Compiled)) ! mut))
    (define (emit-libraries compiled expansion typed libraries)
      (let loop ((libraries libraries) (compiled compiled) (built (Nil)))
        (match libraries
          ((Cons (Pair name _) rest)
           (let* ((before (compiled-of compiled name)) (fresh? (string=? (Compiled-text before) ""))
                  (text (if fresh? (wat->string (emit-library (monomorphize-library typed name (Compiled-items before)) name)) (Compiled-text before))))
             (loop rest (table-set compiled name (Compiled-text-set before text))
                   (Cons (Built name text (library-interface expansion name) fresh?) built))))
          ((Nil) (Pair (reverse built) compiled)))))

    ;; ---- Records ----

    (: compiled-of (-> (Table Compiled) String Compiled))
    (define (compiled-of compiled name)
      (match (table-ref compiled name)
        ((Some found) found)
        ((None) (panic (string-append "internal error: nothing compiled for " name)))))

    ;; The schemes of the definitions among `items`.
    (: own-schemes (-> (Table Scheme) (List Item) (Table Scheme)))
    (define (own-schemes schemes items)
      (fold-left (lambda (own item)
                   (match item
                     ((Define name _) (match (table-ref schemes name)
                                        ((Some scheme) (table-set own name scheme))
                                        ((None) own)))
                     (_ own)))
                 empty-table items))

    (: table-union (All (V) (-> (Table V) (Table V) (Table V))))
    (define (table-union table additions)
      (fold-left (lambda (result key)
                   (match (table-ref additions key)
                     ((Some value) (table-set result key value))
                     ((None) result)))
                 table (table-keys additions)))

    ))
