# Review

- I don't like that `(lofi base)` doesn't have an actual file. 
  I'd rather explicitly export aliases to builtin `%`-prefixed symbols. 
  Same for `(lofi io)`.
- The nomenclature `compile->*` doesn't match Scheme conventions, this should 
  instead be named `lofi->*` or `source->*` or something like that.
- I would prefer if our formatting solution imposed stricter limits on line 
  length. Not sure what a clean formatting solution could look like here, but 
  explicitly recognizing `let` or `define` forms and treating them differently 
  vs. usual application seems like a smart idea.
- The way `compile->wat` is written is very terse. Maybe too terse.
  Can we use a `let*` or something like it to break each step up?
  Otherwise, I really love how these are structured.
  Ideally, we'd have something like F#'s `|>` operator.
  Wouldn't mind adding such a construct to Lofi, now that I think about it...

- `replay!` stands out as a red flag to me. Rather than a stateful, mutable 
  procedure, I'd prefer each new "generation" of incremental builds to take the
  previous generation as an argument (or `null` if none exists), and to reuse
  work by aliasing previous output in the new output rather than mutating.

  Is this possible?
