;; A compiler that keeps running between builds, as a development server's
;; does, and compiles each library to its own module. A build expands only
;; the libraries whose declarations, or whose imports' interfaces, changed
;; since the last; the expander replays the others. It checks, specializes
;; and emits only the libraries whose expansion changed, and keeps every
;; other library's checked items and module text from the build that made
;; them, all in memory.
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
    ;; of its own definitions, and its module's text. `version` names the
    ;; expansion it was made from.
    (struct Compiled
      ((version String)
       (items (List Item))
       (schemes (Table Scheme))
       (text String)))

    (struct Session
      ((context Context)
       (compiled (Ref (Table Compiled)))))

    ;; One library's module after a build: whether this build compiled it,
    ;; and the interface the modules that import it were compiled against.
    (struct Built
      ((name String)
       (text String)
       (interface String)
       (compiled? Bool)))

    (: make-session (-> (List String) (-> (List Syntax) String String ! mut fs) Session ! mut))
    (define (make-session directories generate)
      (Session (make-caching-context directories generate) (ref empty-table)))

    ;; ---- Builds ----

    ;; The modules of the program at `source`, in program order.
    (: build-session (-> Session String (List Built) ! mut fs))
    (define (build-session session source)
      (let ((cx (Session-context session)))
        (start-build! cx)
        (let* ((program (expand-program cx source)) (units (unit-items program (program-items program)))
               (stale (filter (lambda (name) (not (current? session name))) (map Pair-first units)))
               (typed (check-units session program units)))
          (map (lambda (unit) (built-unit session typed unit (member? (Pair-first unit) stale))) units))))

    ;; Whether a library's compiled form was made from its current expansion.
    (: current? (-> Session String Bool ! mut))
    (define (current? session name)
      (match (table-ref (ref-get (Session-compiled session)) name)
        ((Some compiled) (string=? (Compiled-version compiled) (library-version (Session-context session) name)))
        ((None) #f)))

    ;; Checks each library whose expansion changed, after the schemes of the
    ;; libraries before it, and returns the whole program checked.
    (: check-units (-> Session Program (List (Pair String (List Item))) Typed ! mut))
    (define (check-units session program units)
      (let loop ((units units) (items (Nil)) (schemes empty-table))
        (match units
          ((Cons unit rest)
           (let ((compiled (checked-unit session program schemes unit)))
             (loop rest (append items (Compiled-items compiled)) (table-union schemes (Compiled-schemes compiled)))))
          ((Nil) (Typed program items schemes)))))

    (: checked-unit (-> Session Program (Table Scheme) (Pair String (List Item)) Compiled ! mut))
    (define (checked-unit session program schemes unit)
      (let ((name (Pair-first unit)))
        (if (current? session name)
            (compiled-of session name)
            (let* ((typed (check-unit program schemes (Pair-second unit)))
                   (compiled (Compiled (library-version (Session-context session) name) (Typed-items typed)
                                       (own-schemes (Typed-schemes typed) (Typed-items typed)) "")))
              (remember! session name compiled)
              compiled))))

    ;; A library's module: the one a previous build emitted, or a new one.
    (: built-unit (-> Session Typed (Pair String (List Item)) Bool Built ! mut))
    (define (built-unit session typed unit stale?)
      (let* ((name (Pair-first unit)) (compiled (compiled-of session name))
             (text (if stale? (wat->string (emit-unit (monomorphize-unit typed name (Compiled-items compiled)) name)) (Compiled-text compiled))))
        (when stale? (remember! session name (Compiled-text-set compiled text)))
        (Built name text (library-interface (Session-context session) name) stale?)))

    ;; ---- Records ----

    (: compiled-of (-> Session String Compiled ! mut))
    (define (compiled-of session name)
      (match (table-ref (ref-get (Session-compiled session)) name)
        ((Some compiled) compiled)
        ((None) (panic (string-append "internal error: nothing compiled for " name)))))

    (: remember! (-> Session String Compiled Unit ! mut))
    (define (remember! session name compiled)
      (ref-set! (Session-compiled session) (table-set (ref-get (Session-compiled session)) name compiled)))

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
