;; Loading WebAssembly while a program runs, as C loads a shared library
;; with dlopen and finds a function in it with dlsym, and plugins: programs
;; built apart from the one that loads them.
;;
;; `load-module` links a module into the program's own namespace, against
;; the runtime, the program's modules and the modules loaded before it, by
;; name. Its exported functions come out as Funcref values, untyped, and
;; `unsafe-cast` makes one a function of the type the program expects;
;; nothing checks that type but the engine, which traps if the function's
;; WebAssembly type differs. A program compiled one library at a time
;; exports each function under its library's name and its own, as in
;; `cell:run`.
;;
;; `load-plugin` links a plugin's modules into a namespace of their own,
;; and `plugin-function` gives a function the plugin exposes with
;; `(expose name "symbol" dynamic)`, after comparing its signature with the
;; type the program expects. The plugin and the program share the types
;; they pass by importing one declaration of them; a plugin built from
;; another declaration is refused before anything is called.
(define-library (snail shell wasm)
  (export
   Funcref
   Module
   Plugin
   LoadError
   Unreadable
   InvalidManifest
   InvalidModule
   NameTaken
   LinkFailed
   MissingExport
   NotDynamic
   SignatureMismatch
   load-error-message
   load-module
   module-export
   load-plugin
   plugin-function
   unsafe-cast
   wasm)
  (import
   (snail core base)
   (prefix (snail runtime wasm) host-)
   (snail core io)
   (snail shell json)
   (snail shell json read)
   (only (snail core forms) Funcref)
   (only (snail core primitive) unsafe-cast dynamic-cast))
  (begin

    ;; ---- Host operations ----

    ;; The host does what only it can: it compiles bytes into a module,
    ;; makes an empty namespace, instantiates a module in a namespace under
    ;; a library name and runs its main, and finds the functions an instance
    ;; exports. A failure is a negative code, never the end of the program;
    ;; a trap in a loaded module's main still ends it. Namespace 0 is the
    ;; program's own. Names cross a character at a time.
    (effect wasm
      ((argument-character (-> Char Unit))
       (argument-end (-> Unit))
       (compile (-> Bytes I32))
       (namespace (-> I32))
       (instantiate (-> I32 I32 I32))
       (exports-function? (-> I32 Bool))
       (export-function (-> I32 Funcref)))
      (default ((argument-character host-argument-character)
                (argument-end host-argument-end)
                (compile host-compile)
                (namespace host-namespace)
                (instantiate host-instantiate)
                (exports-function? host-has-export)
                (export-function host-export-function))))

    (: send-argument (-> String Unit ! wasm))
    (define (send-argument text)
      (let loop ((index 0))
        (when (< index (string-length text))
          (argument-character (string-ref text index))
          (loop (+ index 1))))
      (argument-end))

    ;; What `instantiate` answers when its namespace has a module of that
    ;; name, and when an import has no provider of its type.
    (: name-taken I32)
    (define name-taken -1)

    (: program-namespace I32)
    (define program-namespace 0)

    ;; ---- Errors ----

    (enum LoadError
      (Unreadable
       ((file String)))
      (InvalidManifest
       ((file String)))
      (InvalidModule
       ((file String)))
      (NameTaken
       ((name String)))
      (LinkFailed
       ((name String)))
      (MissingExport
       ((name String)))
      (NotDynamic
       ((name String)))
      (SignatureMismatch
       ((name String))))

    (: load-error-message (-> LoadError String))
    (define (load-error-message error)
      (match error
        ((Unreadable file) (string-append "cannot read " file))
        ((InvalidManifest file) (string-append file " is not the modules.json of a program"))
        ((InvalidModule file) (string-append file " is not a WebAssembly module"))
        ((NameTaken name) (string-append "a module named " name " is linked already"))
        ((LinkFailed name)
         (string-append "the module " name " imports what nothing provides at its type"))
        ((MissingExport name) (string-append "nothing is exported as " name))
        ((NotDynamic name) (string-append name " is not exposed with dynamic"))
        ((SignatureMismatch name)
         (string-append name " was compiled with other types than this program's"))))

    ;; ---- Modules ----

    ;; An instance, in whichever namespace.
    (struct Module
      ((handle I32)))

    ;; Loads the module in `file` under the library name `name`, into the
    ;; program's namespace.
    (: load-module (-> String String (Result Module LoadError) ! wasm fs))
    (define (load-module name file)
      (match (compile-file file)
        ((Ok compiled) (instantiate-module program-namespace compiled name))
        ((Err error) (Err error))))

    (: compile-file (-> String (Result I32 LoadError) ! wasm fs))
    (define (compile-file file)
      (if (file-exists? file)
          (let ((compiled (compile (read-bytes file))))
            (if (< compiled 0) (Err (InvalidModule file)) (Ok compiled)))
          (Err (Unreadable file))))

    ;; The module, linked against those in the namespace, then the runtime
    ;; and the host, with its main run.
    (: instantiate-module (-> I32 I32 String (Result Module LoadError) ! wasm))
    (define (instantiate-module namespace compiled name)
      (send-argument name)
      (let ((handle (instantiate namespace compiled)))
        (cond ((= handle name-taken) (Err (NameTaken name)))
              ((< handle 0) (Err (LinkFailed name)))
              (else (Ok (Module handle))))))

    ;; The function the module exports as `name`.
    (: module-export (-> Module String (Result Funcref LoadError) ! wasm))
    (define (module-export module name)
      (send-argument name)
      (if (exports-function? (Module-handle module))
          (begin (send-argument name) (Ok (export-function (Module-handle module))))
          (Err (MissingExport name))))

    ;; ---- Plugins ----

    ;; A plugin is a program compiled one library at a time, named by its
    ;; modules.json: {"runtime": FILE, "modules": [{"name": LIBRARY, "file":
    ;; FILE}, ...]}, the modules in program order, each file relative to the
    ;; manifest. Its program's own module comes last, and the functions a
    ;; plugin offers are that module's.
    (struct Plugin
      ((program Module)))

    (struct PluginModule
      ((name String)
       (file String)))

    (struct Manifest
      ((libraries (List PluginModule))
       (program PluginModule)))

    ;; The plugin's modules are linked in a namespace of their own, each
    ;; against those before it, then the runtime the program shares with it
    ;; and the host, as a child-first class loader resolves. A library's
    ;; module text depends on the program it was compiled for, so a plugin
    ;; has instances of its own, and its globals, even of a library the
    ;; program imports too. The runtime its manifest names is not loaded.
    (: load-plugin (-> String (Result Plugin LoadError) ! wasm fs))
    (define (load-plugin file)
      (match (read-manifest file)
        ((Ok manifest) (link-plugin (namespace) (directory-of file) manifest))
        ((Err error) (Err error))))

    (: link-plugin (-> I32 String Manifest (Result Plugin LoadError) ! wasm fs))
    (define (link-plugin namespace directory manifest)
      (match (link-libraries namespace directory (Manifest-libraries manifest))
        ((Some error) (Err error))
        ((None)
         (match (link-plugin-module namespace directory (Manifest-program manifest))
           ((Ok program) (Ok (Plugin program)))
           ((Err error) (Err error))))))

    ;; Why the first library that does not link failed, if one does not.
    (: link-libraries (-> I32 String (List PluginModule) (Option LoadError) ! wasm fs))
    (define (link-libraries namespace directory libraries)
      (match libraries
        ((Nil) (None))
        ((Cons library rest)
         (match (link-plugin-module namespace directory library)
           ((Ok _) (link-libraries namespace directory rest))
           ((Err error) (Some error))))))

    (: link-plugin-module (-> I32 String PluginModule (Result Module LoadError) ! wasm fs))
    (define (link-plugin-module namespace directory module)
      (match (compile-file (relative-to directory (PluginModule-file module)))
        ((Ok compiled) (instantiate-module namespace compiled (PluginModule-name module)))
        ((Err error) (Err error))))

    ;; ---- Manifests ----

    (: read-manifest (-> String (Result Manifest LoadError) ! fs))
    (define (read-manifest file)
      (if (file-exists? file)
          (match (parse-manifest (read-file file))
            ((Some manifest) (Ok manifest))
            ((None) (Err (InvalidManifest file))))
          (Err (Unreadable file))))

    (: parse-manifest (-> String (Option Manifest)))
    (define (parse-manifest text)
      (match (match (string->json text) ((Some json) (json-member json "modules")) ((None) (None)))
        ((Some (JsonArray entries)) (manifest-of (map manifest-module entries)))
        (_ (None))))

    ;; A manifest whose every entry names a module, with at least the
    ;; program's own.
    (: manifest-of (-> (List (Option PluginModule)) (Option Manifest)))
    (define (manifest-of entries)
      (match (reverse entries)
        ((Cons (Some program) libraries)
         (fold-left (lambda (manifest entry)
                      (match (Pair manifest entry)
                        ((Pair (Some (Manifest modules program)) (Some module))
                         (Some (Manifest (Cons module modules) program)))
                        (_ (None))))
                    (Some (Manifest (Nil) program)) libraries))
        (_ (None))))

    (: manifest-module (-> Json (Option PluginModule)))
    (define (manifest-module entry)
      (match (Pair (json-member entry "name") (json-member entry "file"))
        ((Pair (Some (JsonString name)) (Some (JsonString file))) (Some (PluginModule name file)))
        (_ (None))))

    ;; A path's directory with its final slash, or "" for a bare name.
    (: directory-of (-> String String))
    (define (directory-of path)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) "")
              ((char=? (string-ref path index) #\/) (substring path 0 (+ index 1)))
              (else (loop (- index 1))))))

    (: relative-to (-> String String String))
    (define (relative-to directory file)
      (if (and (> (string-length file) 0) (char=? (string-ref file 0) #\/))
          file
          (string-append directory file)))

    ;; ---- Plugin functions ----

    ;; The function the plugin exposes as `name` with `dynamic`, at the type
    ;; the context expects, which must be a function of data. Its signature
    ;; is compared with that type's once, here, so a stale plugin is refused
    ;; before anything it returns is read; the call then has the plain type.
    ;; A dynamic export is pure, so the program's handlers are not passed on.
    (: plugin-function (All (A) (requires (Copy A)) (-> Plugin String (Result A LoadError) ! wasm)))
    (define (plugin-function plugin name)
      (let ((program (Plugin-program plugin)))
        (match (Pair (module-export program name)
                     (module-export program (string-append name ":signature")))
          ((Pair (Ok function) (Ok signature))
           (checked-function name function (descriptor signature)))
          ((Pair (Ok _) (Err _)) (Err (NotDynamic name)))
          ((Pair (Err error) _) (Err error)))))

    ;; `expose … dynamic` exports NAME:signature beside NAME, a function of
    ;; no arguments that returns NAME's signature. That a plugin's export so
    ;; named is one is this boundary's unsafe assumption; the engine traps if
    ;; its WebAssembly type is not that function's.
    (: descriptor (-> Funcref (Vector I64)))
    (define (descriptor signature)
      ((ann (unsafe-cast signature) (-> (Vector I64)))))

    (: checked-function
       (All (A) (requires (Copy A)) (-> String Funcref (Vector I64) (Result A LoadError))))
    (define (checked-function name function signature)
      (match (vector->list
              (dynamic-cast function (lambda (expected) (same-signature? signature expected))))
        ((Cons typed _) (Ok typed))
        ((Nil) (Err (SignatureMismatch name)))))

    ;; The policy is strict identity: a plugin's function is taken only at
    ;; exactly the types it was compiled with. A looser one, accepting a
    ;; compatible change, would be decided here.
    (: same-signature? (-> (Vector I64) (Vector I64) Bool))
    (define (same-signature? offered expected)
      (and (= (vector-length offered) (vector-length expected))
           (every? (lambda (index) (= (vector-ref offered index) (vector-ref expected index)))
                   (iota (vector-length offered)))))))
