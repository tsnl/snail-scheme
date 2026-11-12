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
   wasm
   Compiled
   compile-bytes
   ImportKind
   FunctionImport
   TableImport
   MemoryImport
   GlobalImport
   Import
   module-imports
   Provider
   ExportOf
   HostProvided
   HostIfProvided
   ConstantOf
   Unprovided
   link-module
   loading-program
   name-instance
   replace-instances
   run-export
   run-export-with)
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
    ;; program's own. Names cross a character at a time, and so do the
    ;; names the host holds of an import, `held-length` and `held-char`
    ;; giving the import's module (0) and field (1) after `import-at`.
    ;;
    ;; A loader that chooses a module's providers itself lists the imports
    ;; with `import-count` and `import-at`, prepares a link, gives one
    ;; provider per import in import order, an instance's export under the
    ;; staged name, the host's own function of the import's names, a
    ;; function answering a constant, or a function that fails if called,
    ;; and links; the host initializes what it linked when it exports
    ;; `_initialize`. Instance 0 is the program that loads, whose exports a
    ;; loaded module may import. `name-instance` puts an instance in the
    ;; program's namespace under the staged name, where `instantiate` and
    ;; later loads see it; `call-export` calls an export of no argument or
    ;; one I64, such as `main` or `tasks:turn`, for its result, and
    ;; `call-with-function` one of a Funcref, such as `tasks:start-main`.
    (effect wasm
      ((argument-character (Fn Char → Unit))
       (argument-end (Fn → Unit))
       (compile (Fn Bytes → I32))
       (namespace (Fn → I32))
       (instantiate (Fn I32 I32 → I32))
       (exports-function? (Fn I32 → Bool))
       (export-function (Fn I32 → Funcref))
       (import-count (Fn I32 → I32))
       (import-at (Fn I32 I32 → I32))
       (held-length (Fn I32 → I32))
       (held-char (Fn I32 I32 → Char))
       (prepare-link (Fn I32 → Unit))
       (provide-export (Fn I32 → Bool))
       (provide-host (Fn → Bool))
       (provide-missing (Fn → Unit))
       (link-prepared (Fn → I32))
       (provide-constant (Fn I32 → Unit))
       (register-instance (Fn I32 → Bool))
       (prepare-names (Fn → Unit))
       (provide-instance (Fn I32 → Bool))
       (replace-names (Fn → Bool))
       (call-export (Fn I32 I64 → I64))
       (call-with-function (Fn I32 Funcref → I64)))
      (default ((argument-character host-argument-character)
                (argument-end host-argument-end)
                (compile host-compile)
                (namespace host-namespace)
                (instantiate host-instantiate)
                (exports-function? host-has-export)
                (export-function host-export-function)
                (import-count host-import-count)
                (import-at host-import-at)
                (held-length host-held-length)
                (held-char host-held-char)
                (prepare-link host-prepare-link)
                (provide-export host-provide-export)
                (provide-host host-provide-host)
                (provide-missing host-provide-missing)
                (link-prepared host-link-prepared)
                (provide-constant host-provide-constant)
                (register-instance host-name-instance)
                (prepare-names host-prepare-names)
                (provide-instance host-provide-instance)
                (replace-names host-replace-names)
                (call-export host-call-export)
                (call-with-function host-call-with-function))))

    (define (send-argument (text String)) (→ Unit) (! wasm)
      (let loop ((index 0))
        (when (< index (string-length text))
          (argument-character (string-ref text index))
          (loop (+ index 1))))
      (argument-end))

    ;; What `instantiate` answers when its namespace has a module of that
    ;; name, and when an import has no provider of its type.

    (define name-taken (→ I32) -1)

    (define program-namespace (→ I32) 0)

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

    (define (load-error-message (error LoadError)) (→ String)
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

    (define (load-module (name String) (file String)) (→ (Result Module LoadError)) (! wasm fs)
      (match (compile-file file)
        ((Ok compiled) (instantiate-module program-namespace compiled name))
        ((Err error) (Err error))))

    (define (compile-file (file String)) (→ (Result I32 LoadError)) (! wasm fs)
      (if (file-exists? file)
          (let ((compiled (compile (read-bytes file))))
            (if (< compiled 0) (Err (InvalidModule file)) (Ok compiled)))
          (Err (Unreadable file))))

    ;; The module, linked against those in the namespace, then the runtime
    ;; and the host, with its main run.

    (define (instantiate-module (namespace I32) (compiled I32) (name String))
      (→ (Result Module LoadError))
      (! wasm)
      (send-argument name)
      (let ((handle (instantiate namespace compiled)))
        (cond ((= handle name-taken) (Err (NameTaken name)))
              ((< handle 0) (Err (LinkFailed name)))
              (else (Ok (Module handle))))))

    ;; The function the module exports as `name`.

    (define (module-export (module Module) (name String)) (→ (Result Funcref LoadError)) (! wasm)
      (send-argument name)
      (if (exports-function? (● module handle))
          (begin (send-argument name) (Ok (export-function (● module handle))))
          (Err (MissingExport name))))

    ;; ---- Plugins ----

    ;; A plugin is a program compiled one library at a time, named by its
    ;; modules.json: {"store": STORE, "runtime": OBJECT, "modules":
    ;; [{"name": LIBRARY, "digest": DIGEST, ...}, ...], ...}, the modules in
    ;; program order, each an object at STORE/sha256/DIGEST, the store
    ;; relative to the manifest and store/ beside it unless it says. Its
    ;; program's own module comes last, and the functions a plugin offers
    ;; are that module's.
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

    (define (load-plugin (file String)) (→ (Result Plugin LoadError)) (! wasm fs)
      (match (read-manifest file)
        ((Ok manifest) (link-plugin (namespace) (directory-of file) manifest))
        ((Err error) (Err error))))

    (define (link-plugin (namespace I32) (directory String) (manifest Manifest))
      (→ (Result Plugin LoadError))
      (! wasm fs)
      (match (link-libraries namespace directory (● manifest libraries))
        ((Some error) (Err error))
        ((None)
         (match (link-plugin-module namespace directory (● manifest program))
           ((Ok program) (Ok (Plugin program)))
           ((Err error) (Err error))))))

    ;; Why the first library that does not link failed, if one does not.

    (define (link-libraries (namespace I32) (directory String) (libraries (List PluginModule)))
      (→ (Option LoadError))
      (! wasm fs)
      (match libraries
        ((Nil) (None))
        ((Cons library rest)
         (match (link-plugin-module namespace directory library)
           ((Ok _) (link-libraries namespace directory rest))
           ((Err error) (Some error))))))

    (define (link-plugin-module (namespace I32) (directory String) (module PluginModule))
      (→ (Result Module LoadError))
      (! wasm fs)
      (match (compile-file (relative-to directory (● module file)))
        ((Ok compiled) (instantiate-module namespace compiled (● module name)))
        ((Err error) (Err error))))

    ;; ---- Manifests ----

    (define (read-manifest (file String)) (→ (Result Manifest LoadError)) (! fs)
      (if (file-exists? file)
          (match (parse-manifest (read-file file))
            ((Some manifest) (Ok manifest))
            ((None) (Err (InvalidManifest file))))
          (Err (Unreadable file))))

    (define (parse-manifest (text String)) (→ (Option Manifest))
      (match (string->json text)
        ((Some json)
         (match (json-member json "modules")
           ((Some (JsonArray entries))
            (manifest-of (map (lambda (entry) (manifest-module (manifest-store json) entry))
                              entries)))
           (_ (None))))
        ((None) (None))))

    ;; The store a manifest's objects are in, relative to the manifest.

    (define (manifest-store (json Json)) (→ String)
      (match (json-member json "store")
        ((Some (JsonString store)) store)
        (_ "store/")))

    ;; A manifest whose every entry names a module, with at least the
    ;; program's own.

    (define (manifest-of (entries (List (Option PluginModule)))) (→ (Option Manifest))
      (match (reverse entries)
        ((Cons (Some program) libraries)
         (fold-left (lambda (manifest entry)
                      (match (Pair manifest entry)
                        ((Pair (Some (Manifest modules program)) (Some module))
                         (Some (Manifest (Cons module modules) program)))
                        (_ (None))))
                    (Some (Manifest (Nil) program)) libraries))
        (_ (None))))

    ;; A module's library, and the object holding it, relative to the
    ;; manifest.

    (define (manifest-module (store String) (entry Json)) (→ (Option PluginModule))
      (match (Pair (json-member entry "name") (json-member entry "digest"))
        ((Pair (Some (JsonString name)) (Some (JsonString digest)))
         (Some (PluginModule name (string-append store "sha256/" digest))))
        (_ (None))))

    ;; A path's directory with its final slash, or "" for a bare name.

    (define (directory-of (path String)) (→ String)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) "")
              ((char=? (string-ref path index) #\/) (substring path 0 (+ index 1)))
              (else (loop (- index 1))))))

    (define (relative-to (directory String) (file String)) (→ String)
      (if (and (> (string-length file) 0) (char=? (string-ref file 0) #\/))
          file
          (string-append directory file)))

    ;; ---- Linking by hand ----

    ;; What a loader written in Snail-Core, such as an engine linking a
    ;; program's modules, needs: a compiled module, its imports, and a link
    ;; against providers it chooses, one per import.
    (struct Compiled
      ((handle I32)))

    ;; The module `bytes` hold, or none when they are not one.

    (define (compile-bytes (bytes Bytes)) (→ (Option Compiled)) (! wasm)
      (let ((handle (compile bytes)))
        (if (< handle 0) (None) (Some (Compiled handle)))))

    (enum ImportKind
      (FunctionImport)
      (TableImport)
      (MemoryImport)
      (GlobalImport))

    ;; An import: the module and field it names, and what it must be.
    (struct Import
      ((from String)
       (name String)
       (kind ImportKind)))

    (define (module-imports (compiled Compiled)) (→ (List Import)) (! wasm)
      (map (lambda (index) (import-of (● compiled handle) (i64->i32 index)))
           (iota (i32->i64 (import-count (● compiled handle))))))

    (define (import-of (module I32) (index I32)) (→ Import) (! wasm)
      (let ((kind (import-at module index)))
        (Import (held-string 0) (held-string 1) (kind-of kind))))

    (define (kind-of (code I32)) (→ ImportKind)
      (cond ((= code 0) (FunctionImport))
            ((= code 1) (TableImport))
            ((= code 2) (MemoryImport))
            ((= code 3) (GlobalImport))
            (else (panic "the host answered an unknown kind of import"))))

    ;; A name the host holds, a character at a time.

    (define (held-string (which I32)) (→ String) (! wasm)
      (string-generate (i32->i64 (held-length which))
                       (lambda (index) (held-char which (i64->i32 index)))))

    ;; What provides an import: an export of an instance, the host's own
    ;; function of the import's module and field, that function when the
    ;; host has one and otherwise nothing, a function of no arguments
    ;; answering a constant, as a linked file's handle is imported, or
    ;; nothing, a function that fails if called, as a host import a program
    ;; never calls links. A provider that is not found, an export the
    ;; instance lacks or a function the host lacks, provides nothing, and
    ;; the link fails unless another is given for the import.
    (enum Provider
      (ExportOf
       ((instance Module)
        (export String)))
      (HostProvided)
      (HostIfProvided)
      (ConstantOf
       ((value I32)))
      (Unprovided))

    ;; The program that loads, as an instance whose exports a loaded module
    ;; may import.

    (define loading-program (→ Module) (Module 0))

    ;; Links `compiled`, called `name` in a failure, with `providers`, one
    ;; per import in import order, and initializes it when it exports
    ;; `_initialize`. The link fails when a provider names no export, the
    ;; host has no such function, an import is left without a provider, or
    ;; a provider is not of the import's type; a trap while the module
    ;; starts still ends the program.

    (define (link-module (name String) (compiled Compiled) (providers (List Provider)))
      (→ (Result Module LoadError))
      (! wasm)
      (prepare-link (● compiled handle))
      (for-each provide providers)
      (let ((handle (link-prepared)))
        (if (< handle 0) (Err (LinkFailed name)) (Ok (Module handle)))))

    (define (provide (provider Provider)) (→ Unit) (! wasm)
      (match provider
        ((ExportOf instance export)
         (send-argument export)
         (provide-export (● instance handle))
         (unit))
        ((HostProvided) (provide-host) (unit))
        ((HostIfProvided) (unless (provide-host) (provide-missing)))
        ((ConstantOf value) (provide-constant value))
        ((Unprovided) (provide-missing))))

    ;; Puts the instance in the program's namespace under `name`, where
    ;; `load-module` and the modules loaded later see it, answering whether
    ;; the name was free.

    (define (name-instance (instance Module) (name String)) (→ Bool) (! wasm)
      (send-argument name)
      (register-instance (● instance handle)))

    ;; Publish the complete library namespace in one host operation. The
    ;; candidate is staged without suspension or callbacks into loaded code.
    ;; Any invalid entry poisons the whole candidate; omitted names disappear.
    ;; Instances and existing references to them are never reinitialized.

    (define (replace-instances (instances (List (Pair String Module)))) (→ Bool) (! wasm)
      (prepare-names)
      (for-each (lambda (entry)
                  (send-argument (● entry first))
                  (provide-instance (● (● entry second) handle))
                  (unit)) instances)
      (replace-names))

    ;; Calls the function the instance exports as `name`, of no argument or
    ;; one I64, such as its `main` or a scheduler's `tasks:turn`, with
    ;; `argument`, answering its result, or 0 when it answers nothing.

    (define (run-export (instance Module) (name String) (argument I64))
      (→ (Result I64 LoadError))
      (! wasm)
      (send-argument name)
      (if (exports-function? (● instance handle))
          (begin (send-argument name) (Ok (call-export (● instance handle) argument)))
          (Err (MissingExport name))))

    ;; Calls the function the instance exports as `name` with `function`,
    ;; such as a scheduler's `tasks:start-main` with a program's body.

    (define (run-export-with (instance Module) (name String) (function Funcref))
      (→ (Result I64 LoadError))
      (! wasm)
      (send-argument name)
      (if (exports-function? (● instance handle))
          (begin (send-argument name)
                 (Ok (call-with-function (● instance handle) function)))
          (Err (MissingExport name))))

    ;; ---- Plugin functions ----

    ;; The function the plugin exposes as `name` with `dynamic`, at the type
    ;; the context expects, which must be a function of data. Its signature
    ;; is compared with that type's once, here, so a stale plugin is refused
    ;; before anything it returns is read; the call then has the plain type.
    ;; A dynamic export is pure, so the program's handlers are not passed on.

    (define (plugin-function (plugin Plugin) (name String))
      (→ (Result A LoadError))
      (! wasm)
      (∀ A)
      (⊨ (Copy A))
      (let ((program (● plugin program)))
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

    (define (descriptor (signature Funcref)) (→ (Vector I64))
      ((ann (unsafe-cast signature) (Fn → (Vector I64)))))

    (define (checked-function (name String) (function Funcref) (signature (Vector I64)))
      (→ (Result A LoadError))
      (∀ A)
      (⊨ (Copy A))
      (match (vector->list
              (dynamic-cast function (lambda (expected) (same-signature? signature expected))))
        ((Cons typed _) (Ok typed))
        ((Nil) (Err (SignatureMismatch name)))))

    ;; The policy is strict identity: a plugin's function is taken only at
    ;; exactly the types it was compiled with. A looser one, accepting a
    ;; compatible change, would be decided here.

    (define (same-signature? (offered (Vector I64)) (expected (Vector I64))) (→ Bool)
      (and (= (vector-length offered) (vector-length expected))
           (every? (lambda (index) (= (vector-ref offered index) (vector-ref expected index)))
                   (iota (vector-length offered)))))))
