# Generated libraries and dependency artifacts

Build evaluation can produce both Scheme declarations and files needed by the
resulting program. `generate-library` runs that evaluation in a separate native
process. Dependency artifacts carry the completed files into the executable's
installation; they are not embedded into Scheme literals.

A generated library uses the ordinary import path and library name:

```scheme
(generate-library (demo message)
  (export message-path)
  (import (scheme base) (scheme file) (scheme write)
          (snail-scheme generation) (snail-scheme artifacts))
  (begin
    (define output (generation-output-path "message.txt"))
    (call-with-output-file output
      (lambda (port) (display "Hello from build evaluation!\n" port)))
    (generated-library
      '((import (scheme base) (snail artifacts))
        (begin (define (message-path) (artifact-path "message.txt"))))
      (list (make-artifact "message.txt" output '())))))
```

The wrapper contains exactly one `begin`. Its imports apply to generator code;
returned declarations supply the generated library's own imports. Its name and
exports remain authoritative, and returned declarations may contain only
`import` and `begin`. The result is a `generated-library` value carrying declarations and artifact
roots; use an empty root list when the library needs no companions.

`generation-source-path` resolves relative to the source library's directory.
`generation-output-path` resolves inside that generator's private workspace.
The latter owns temporary outputs, which are copied before the workspace can
be removed or another generator can rebuild a shared Cargo output. Ordinary
subprocess output is separate from the generator's result protocol. Located
syntax can retain source locations; ordinary datums inherit the wrapper's
location for diagnostics.

Generators run once per imported source file in one build, including path aliases.
Nested generation shares the build's cache, but each compilation collects its
own dependencies. A recursive generator dependency fails with a cycle error.
The cache is not persistent across builds and does not promise hermeticity:
Scheme build code can inspect the environment and execute external tools.

The portable `(snail-scheme compiler)` library has no process dependencies. Its
`library-generator` parameter defaults to an error when a generated library is
requested. `(snail-scheme compile-build)` installs the build resolver and returns
`compilation-wasm` together with `compilation-artifacts`. The ordinary `build-wasm`
and `build-native` operations use this path and propagate generated dependencies
automatically. Scripts own the surrounding Chromium trace file scope.

## Artifact descriptions and publication

`(make-artifact name source dependencies)` describes one completed file:

- `name` is a nonempty filename, with no separators, NUL, `.` or `..`.
- `source` names the completed regular file and is resolved to an absolute path.
- `dependencies` is a list of other artifact descriptions.

An artifact is a file declaration, not a deferred build action. Ordinary Scheme
code creates the file before returning the description. Shared description
identity supports diamond dependencies; two distinct descriptions with the same
installed name fail, even if their source paths happen to match. The entire
transitive closure shares one flat namespace. Dependencies are staged before
consumers, and input paths are protected from output aliasing.

`call-with-build-output` accepts an optional dependency list. Its callback gets
a private directory and a candidate output path; it writes the candidate and
may return an artifact describing that same candidate with additional
dependencies. Builds without dependencies retain ordinary single-file publication.
Builds with dependencies publish this layout:

```text
app -> .snail-artifacts-PID-N/program
.snail-artifacts-PID-N/
  program
  manifest.scm
  artifacts/
    message.txt
```

The versioned S-expression manifest records the entry, roots, files, and named
dependency edges. Files and permissions are copied into a complete generation
before one atomic rename switches the public relative symlink. Failed publication
preserves the previous executable. Successful publication retains older
generations so programs already running can continue using their companions.
Automatic generation garbage collection is not implemented.

Move the public symlink and its target generation together when relocating an
installation, or move the complete generation directory and invoke its `program`
file. Copying only the executable omits its declared dependencies.

## Runtime lookup

`(snail artifacts)` exports `find-artifact`, which returns a path or `#f`, and
`artifact-path`, which reports a missing required file. Native lookup uses the
physical executable's directory, independent of the working directory and
`argv[0]`. This pins a running program to the generation it started from.
`SNAIL_ARTIFACT_ROOT` explicitly overrides lookup; Chibi uses this override for
bootstrap workflows. The Node/WASI launcher resolves the selected payload once
and preopens its artifact directory as `/snail-artifacts`.

`scripts/test-generation` exercises isolation, nested/cache-hit dependencies,
cycles, rollback, relocation, live generation pinning, and linked Wasm companion
lookup.
