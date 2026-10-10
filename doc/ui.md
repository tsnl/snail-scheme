# Reducers, documents, and an HTML host

This experimental API runs under Chibi. It uses ordinary procedures and immutable
application values: `update(message, model)` returns the next model, and
`view(model)` describes a tree. The tree can be rendered once as a document or
again after messages as an application. There is no `use-state` or hook lifecycle.

The first renderer produces HTML for the browser's DOM. The first interactive
host runs Scheme on the server and uses native form submissions. Browser WASM,
DOM patching, hydration, effects, and a custom graphics backend remain future work.

## Try the workbook

```sh
chibi-scheme -I src examples/ui.scm
# Open http://127.0.0.1:8765/

chibi-scheme -I src examples/ui.scm 9000
chibi-scheme -I src examples/ui.scm --html > /tmp/workbook.html
```

The same view supplies prose, a counter, and a collapsible explanation. The
snapshot includes the initial content and disabled controls. The live page uses
real HTML buttons, posts messages to Chibi, and redirects to a newly rendered
page. No Scheme interpreter or JavaScript UI runtime runs in this browser demo.

## Walk through the running example

Start the server from the repository worktree containing this prototype, then
open its loopback URL. Keep that terminal running while using the page.

1. The initial page shows a count of **0** and a **Show explanation** button.
   Its prose and controls come from the same `view` procedure.
2. Press **Increase** twice. Each press submits a form and the next page shows
   **1**, then **2**. **Decrease** sends the corresponding negative adjustment.
3. Press **Show explanation**. A paragraph appears beneath the counter, without
   changing its value. **Hide explanation** removes that part of the tree.
4. Press **Reset**. The model returns to count **0** with the explanation hidden.
5. Open the URL in a second tab. Both tabs address the same application. After
   one tab changes it, submitting an old page in the other produces a conflict
   page with a reload link. Reload to obtain the current controls.

The source path for an Increase click is short:

```text
(button (make-adjust-count 1) "Increase")
  -> HTML form with a versioned action URL
  -> POST resolves that URL to the adjustment record
  -> update(message, model) returns a new model record
  -> view(model) composes the next tree
  -> render-html prepares HTML and the matching action table
  -> the host publishes both, then sends a 303 redirect to /
```

Read [examples/ui.scm](../examples/ui.scm) for the model, `update`, the `counter`
and `notes` components, and the document shell. The small
[ui.sld](../src/snail-scheme/ui.sld) stores model/update/view and implements
`dispatch`. The [HTML renderer](../src/snail-scheme/html.sld) turns the tree into
markup and actions; [ui-server.sld](../src/snail-scheme/ui-server.sld) owns the
current page and HTTP dispatch.

The `--html` command evaluates the same initial application once. Open the output
file to see the same document with disabled buttons. It has no host to receive
messages. Stopping and restarting the live Chibi server also returns the workbook
to its initial model; no model is saved to disk.

The [platform design](why-snail-scheme.md)
proposes isolated actors with their own heap, globals, and resource lifetime.
Spawning and connecting are separate; connections can carry calls returning
values, futures, or streams, with S-expression serialization at every actor
boundary. The [chat tutorial specification](tutorials/02-chat/README.md)
extends this experiment toward browser WASM, distributed services, and reload.
This example uses an ordinary
long-lived Chibi process and an in-memory application instead. It demonstrates
composition and message dispatch before those runtime facilities exist.

## A small application value

```scheme
(import (scheme base) (snail-scheme react) (snail-scheme ui)
        (snail-scheme html) (snail-scheme ui-server))

(define (update message model) (+ model message))
(define (view model)
  (element 'main '()
           (element 'output '() model)
           (button 1 "Increase")))

(define app (application 0 update view))
(application-model (dispatch app 1)) ; => 1; app still holds 0
(run-ui app 8765)
```

`application` stores a model, reducer, and view. `dispatch` returns a new
application without evaluating the view; `application-view` evaluates the view
of a particular application. `application?` and `application-model` inspect it.
The reducer receives the message first, matching
[Elm's update convention](https://guide.elm-lang.org/architecture/buttons).
Messages and models are ordinary Scheme data, including records and `#f`.

The workbook defines a record type for each operation: `<adjust-count>` carries
a `delta`, while `<toggle-notes>` and `<reset-workbook>` have no fields. Buttons
construct those records, and the reducer dispatches on their predicates and uses
the named delta accessor. The UI library passes messages through unchanged;
this representation is a choice made by the app.

The [planned actor protocol](why-snail-scheme.md#messages-cross-heaps-pointers-do-not)
derives S-expression codecs from record/variant and method types. That codec and
type-metadata API are not implemented here; this host retains message objects
and the browser sends action URLs.

Reducers and views must preserve their input model. The application record has
no setters, but it cannot prevent mutation of a contained Scheme object. The
host owns the current application; components do not implicitly own state.
Nested model records and tagged messages can compose ordinary reducers. An
asynchronous command/completion protocol has not yet been introduced.

## The HTML boundary

`render-html` resolves a description and returns two values: an HTML string and
an action alist. An optional URL prefix enables actions; without it the result is
a static snapshot. Text, characters, numbers, and attribute values are escaped.

HTML elements use symbol tag names and an attribute alist as their data. Names
must begin with a lowercase ASCII letter and contain only lowercase letters,
digits, hyphens, underscores, or colons. Duplicate attributes are errors. String
and number values are quoted, `#t` emits a boolean attribute, and `#f` omits it.
Use explicit fragments to omit or splice children; other opaque leaves supported
by the generic core are errors for HTML.

`(button message label)` describes an action with a string label. In a live
render it becomes a form containing a submit button; in a snapshot it becomes a
disabled button. Messages stay in Scheme. The form URL is a lookup key, never
Scheme source to deserialize or evaluate. Native forms cannot nest: the renderer
rejects nested forms and action buttons inside forms, including through components.

This is a small HTML serializer, not a complete HTML conformance checker.
Void tags reject children. Raw-text tags such as `script` and `style` are currently
unsupported; the example uses ordinary style attributes. SVG namespaces, text
inputs, arbitrary event handlers, raw HTML, and general form submission are not
part of this prototype.

`application->html` produces a static document string beginning with a doctype.
The application supplies its own document shell, title, and styling if needed.
Neither the generic core nor the host chooses the document's content vocabulary.

## What the Chibi host owns

`run-ui` binds to loopback and maintains one application shared by all tabs. It
prepares HTML and its matching action table together. GET observes that prepared
page without rerunning the view. POST looks up an action in the current page,
runs the reducer, resolves the next view, and finishes HTML generation before
publishing the new page and redirecting with HTTP 303.

A mutex serializes lookup through publication. Every successful update consumes
the current page's actions, including an update that leaves the model unchanged.
Stale, duplicate, and unknown actions return HTTP 409 with a reload link. A fresh
initial revision distinguishes a restarted server from the previous run.

If reduction, view evaluation, or serialization fails, the previous page and
action table remain current. This preserves model state only when reducers/views
respect the immutability convention. Publication happens before writing the
response: a lost response does not undo the update, and retrying its old action
cannot apply the message a second time. This host is a local, shared application
prototype; it has no per-user sessions or persistent state.

## Direction and precedents

Scheme supports several GUI styles rather than one portable standard toolkit.
[Racket's GUI toolkit](https://docs.racket-lang.org/gui/windowing-overview.html)
uses widgets and callbacks;
[GUI Easy](https://docs.racket-lang.org/gui-easy/index.html) adds functional view
composition around observable values. Our model/update/view experiment keeps its
state transition explicit and its host separate.

Resin's Python GUI lives on
[`archive/main-v3`](https://github.com/tsnl/resin/tree/archive/main-v3).
Its [gui.py](https://github.com/tsnl/resin/blob/aa1e3612843297e94cc98102f44f6524b4528b6c/src/resin/gui.py)
builds drawing primitives each frame through direct widget functions and
horizontal/vertical layout. Application state lives outside those primitives;
transient widget interaction state also exists inside the GUI. It is an
immediate-mode design, rather than an Elm reducer architecture. Direct functions
and explicit composition are useful precedents for this Scheme API.

A future Snail browser host can run the same reducer and view in WASM and send
output to DOM operations. The Chibi HTTP adapter need not come along. Chibi also
has an [Emscripten build](https://github.com/ashinn/chibi-scheme#readme), but this
prototype does not depend on it. A shared-source design for server, client, and
shader code is scoped in the [generated-library proposal](generate-library.md).

Shared document/application composition does not make delivery irrelevant to
search. Google executes JavaScript, while still recommending server rendering
or prerendering for users and crawlers. Keeping useful initial HTML is compatible
with moving later interaction into the browser.
[Google's JavaScript guidance](https://developers.google.com/search/docs/crawling-indexing/javascript/javascript-seo-basics)
explains the distinction.

## Checks

```sh
make test
make check
./scripts/format-scheme --check examples/react.scm examples/ui.scm
./scripts/test-ui
```

The last command requires Python 3 and Chibi. It launches temporary loopback
servers and exercises initial HTML, live actions, static controls, duplicate and
concurrent submissions, false-valued messages, failed transitions, and restarts.
These are HTTP checks, not browser automation or a Snail native/WASI validation.
