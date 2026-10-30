# Feedback

## Book

- We need better branding. `Lofi` vs `Snail-Scheme` is a lot of naming confusion. Why isn't this just `Snail-Scheme` the language? Or `snail-base` or `snail-core` becomes the core language (replacing `lofi`), and `snail-scheme` becomes, well, Scheme. Okay, decided, `snail-core` it is.
- Hmm, is this backward?

  > Its typed forms (structs, enums, signatures, effects and typeclasses) sit on a Scheme-shaped core: erase them and what remains is an R7RS program with the same behavior.

  Scheme erases to this language, not the other way around.

- This is a poor way to phrase "everything is a library":

  > Languages are libraries: the compiler is a Lofi program, and Scheme itself is offered as libraries over the typed language.

- Weird to dive straight into imports under "Terms". We've lost the structure where we open with a brief introduction, then go into details.

- Can we add syntax highlighting to the Scheme examples? And custom syntax highlighting for Lofi?

---

## Language

- Can we make all allocations require an effect in-scope? A separate effect for 
  GC allocations? This makes it possible for no-GC libraries to work!

- Instead of build scripts allowing arbitrary code execution, what if we went 
  back to `project.sld` and relied on `generate-library` forms to run code? This
  forces all build-time artifact generation to be tied to a symbol explicitly
  exposed in the library, which I quite like.

  To ensure that not all artifacts are inlined into WASM, we may want to 
  introduce a `(link ...)` AST form (or something like `link-bytes` analogous 
  to `include-bytes`) that allows explicitly linking a nearby file. Linking here
  just means the files should be distributed together, though each file may be
  loaded independently.

---

## Review for me

What a newcomer hits:

- No code until the tutorials. Three screens describing a language without one line of it. Your own FEEDBACK note — “weird to dive straight into imports” — is this same instinct pointed the other way: the old book had structure-then-detail, this has thesis-then-nothing. One ten-line example inside ## Snail-Core anchors every abstract claim above it, and you already have examples/fibonacci.sld.
- “Most Snail libraries are written in Snail-Core directly” is true, surprising, and the sentence that tells a Scheme programmer they aren’t in Scheme. It needs the follow-up a newcomer immediately asks: so which do I write? The page never answers.
- Nothing tells the reader what to do next. No install, no first command, no link into the tutorials from the landing page. SUMMARY has them; the index should too.
- “portable, high-performance, distributed, and formally verified” — four adjectives in sentence one, two of them design. That’s the sentence most likely to produce “which of these works today?”
