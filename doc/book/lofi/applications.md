# Application model

{{#include ../../language.md:applications}}

## Live reload

`lofi serve APP-DIRECTORY` builds an application one library at a time,
serves it at `http://127.0.0.1:8000/`, and builds it again whenever the
application's directory, the standard library or the browser host
changes, compiling only the libraries the change reaches. Each page it
serves relinks the modules that changed, and those after them, without
reloading. Their globals start over; the application's state crosses to
the new program:

- as it is, when `type-test` finds its type unchanged;
- through `save` and `restore` when its layout changed. That is the
  contract a page reload already relies on, so an application whose save
  is a journal, as Siegework's is, replays the journal under the new code;
- not at all when the save cannot be restored either: the old program
  keeps running, and the page offers to start the new one over.

A failed build is shown over the page, and the old program keeps running.
A program that traps keeps the last state whose whole event succeeded,
including presentation. The next good build resumes from that checkpoint
without repeating the failing event; unread actions wait for it. A cold
first-frame failure also stays available for a source fix. Reload waits for
the old JSPI entry to save and settle before relinking, and accepts a new
entry only after its first frame succeeds. A changed style
sheet is fetched again; a changed page or host script reloads the page
after saving. Each event carries the manifest of the build being served,
so a page that missed events, even across a restart of the server,
catches up from the next one.

Neither `lofi serve` nor the IDE builds a `generate-library` recipe yet, so
an application with one, such as Hearsay, is built with `make site`.

`lofi watch SOURCE` is the same loop for a program: it builds and runs the
program again whenever its sources change, stopping a run still in
progress once a new build succeeds. [The development
toolchain](toolchain.md) describes how builds stay this fast, and the
browser IDE that runs the same loop without a server.
