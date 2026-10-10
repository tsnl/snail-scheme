# A chat application in two places

**Planned integration tutorial.** A vendorable application library builds a native
server and browser Wasm. Two browsers run their own Scheme reducer and functional
view; the server connects to a native history service. Static document rendering
and the live DOM share the same ordinary tree-composition API.

Aim for `build.scm`, `protocol.sld`, and `chat.sld`, with separate browser and
server roots in the application source. Top-level typed message declarations
derive S-expression codecs. Reducers consume records; there are no `use-state`
slots or separately maintained JSON schemas. HTML/DOM is the first UI backend.

## Observable checkpoints

- **C01 — Message types:** one type source drives local and WebSocket codecs for
  arguments, results, failures, and stream items. Reject malformed/unknown data
  and excessive depth or size before dispatch. Decode, never evaluate.
- **C02 — Views:** Chibi static rendering and browser rendering agree on content.
  Generic elements, fragments, and components compose trees; DOM updates retain
  focus and selection. Application code and library code remain separately readable.
- **C03 — Multiple targets:** two actual browsers execute Scheme handlers, retain
  local drafts while offline, and receive the same committed post. The native
  server's credentials and database implementation never enter browser artifacts.
- **C04 — Composition and discovery:** a separate consumer imports the application,
  selects targets, and builds artifacts plus service requirements. Runtime binds
  real instances and credentials. Connecting to an existing database does not
  confer supervision; spawning a client and connecting are distinct operations.
- **C05 — Streams:** room ordering, operation-ID deduplication, replay, and bounded
  subscriber queues are explicit protocol guarantees. A slow browser cannot block
  another. Pub/sub is a service, not the definition of every connection.
- **C06 — Failure and reload:** connection endpoints settle their own outstanding
  exchanges. History survives worker/session failure. Reload validates compatibility,
  pins old artifacts as needed, and requires migration/reconnection when necessary.
- **C07 — Documents:** a later `generate-library` reads explicit foreign paths,
  with generator imports separate from generated imports. Its one generator
  `begin` preserves locations, hygiene, and dependencies. Embedded runtime Scheme
  does not run during generation. Publish static and interactive guides through
  the same view API, eventually replacing this mdBook frontend.

Use a host profile for reducers/codecs, then a native server plus two real browser
clients, and a deployment profile with a remote service. Authentication, store,
discovery, protocol versions, and reconnect policy must be chosen and documented
before the distributed integration test is considered complete.
