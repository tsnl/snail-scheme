# Dependency artifacts

Builds can declare completed files needed by an executable. Files and their
dependencies are published together; they are not embedded into Scheme literals.

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

