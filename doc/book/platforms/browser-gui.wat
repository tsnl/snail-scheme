;; Browser GUI -- proposed application interface, not implemented. A browser
;; binding owns DOM access on the document thread. The shared handlers follow
;; the native GUI lifecycle/input/redraw shape. A surface is an owned DOM
;; subtree; elements within it are not windows. Winit's web backend uses
;; canvas; this proposal adds DOM composition beside the common callback layer.
;; See https://docs.rs/winit/latest/winit/platform/web/index.html
;;
;; Each call borrows an instance-local argument-vector root and returns an
;; owned result root. Brackets describe its Scheme values. The host initializes
;; globals before callbacks. Resource references belong to this
;; instance/surface. Bodies are stubs; OS-dependent runtime services need
;; browser adapters or exclusion.
;;
;; Scheme components/reducers compose trees; a Scheme renderer compares them
;; and issues DOM edits. The browser owns layout, painting, and native text
;; editing. Keep heavy work off the document thread. Queue callbacks raised
;; during edits until the current call returns. Worker actors must serialize
;; commands/events to the DOM owner; raw AWI roots cannot cross that boundary.
;;
;; Batching, hydration, focus/selection/layout APIs, CSS, custom elements,
;; shadow roots, and the recoverable DOM-error boundary remain open design
;; choices. Fullscreen/clipboard require an explicit browser-timed
;; user-activation path; an arbitrary deferred actor callback cannot promise
;; activation eligibility. See
;; https://html.spec.whatwg.org/multipage/interaction.html#tracking-user-activation
(module

  ;; ---- Shared surface operations ----

  ;; [options] -> surface-ref. Select a mount binding supplied by the embedding
  ;; page and create an application-owned DOM root beneath it. The host element
  ;; remains owned by the page. This does not open a new browser window. Surface
  ;; references have an instance/domain and lifetime; each DOM element is not a
  ;; surface.
  (import "snail.gui" "create-surface"
    (func (param $arguments i32) (result i32)))

  ;; [surface] -> unspecified. Remove the owned subtree, unregister its
  ;; listeners/observers, cancel redraw requests, and invalidate its resource
  ;; references. Do not remove the embedding page's host element. Repeated
  ;; destruction of an owned retired surface is harmless.
  (import "snail.gui" "destroy-surface"
    (func (param $arguments i32) (result i32)))

  ;; [surface] -> unspecified. Coalesce requests through requestAnimationFrame
  ;; and later dispatch redraw-requested. This is useful for animation and
  ;; scheduled view work; ordinary DOM updates do not require a perpetual redraw
  ;; loop. Hidden pages may delay frames; do not use this as a dependable clock
  ;; or completion signal.
  (import "snail.gui" "request-redraw"
    (func (param $arguments i32) (result i32)))

  ;; ---- DOM operations ----

  ;; [surface] -> node-ref. Obtain the owned DOM root for this surface.
  ;; References identify entries in the runtime's DOM table; neither DOM objects
  ;; nor AWI root integers become actor message payloads. Destroy the surface to
  ;; retire its root.
  (import "snail.dom" "root"
    (func (param $arguments i32) (result i32)))

  ;; [surface, namespace, tag] -> node-ref. Create a detached element owned by
  ;; this surface. Retain normal HTML controls and semantics, including
  ;; accessibility and native text editing. Allowed namespaces/tags and
  ;; custom-element support need a concrete first-profile decision.
  (import "snail.dom" "make-element"
    (func (param $arguments i32) (result i32)))

  ;; [surface, text] -> node-ref. Create a detached text node from string data.
  ;; Text is not parsed as HTML or executed.
  (import "snail.dom" "make-text"
    (func (param $arguments i32) (result i32)))

  ;; [parent, child, optional before] -> unspecified. Insert or move an owned
  ;; node within the same surface; false for before means append. Reject cycles,
  ;; stale references, and cross-surface moves. Moving a keyed node preserves its
  ;; identity; the renderer must also preserve focus/selection where DOM moves
  ;; affect them.
  (import "snail.dom" "insert-before"
    (func (param $arguments i32) (result i32)))

  ;; [node] -> unspecified. Retire an owned non-root subtree, including its
  ;; listeners and references, whether attached or detached. Queued events for
  ;; retired subscriptions are ignored. To move a node, use insert-before rather
  ;; than retiring it. GC alone does not remove live UI.
  (import "snail.dom" "remove"
    (func (param $arguments i32) (result i32)))

  ;; [text-node, text] -> unspecified. Replace a text node's characters without
  ;; reparsing markup or replacing surrounding controls.
  (import "snail.dom" "set-text"
    (func (param $arguments i32) (result i32)))

  ;; [element, name, string-or-false] -> unspecified. Set or remove an ordinary
  ;; attribute, including class and ARIA data. Event-handler source attributes
  ;; are outside this interface; use listen. Form values are live properties and
  ;; use set-property.
  (import "snail.dom" "set-attribute"
    (func (param $arguments i32) (result i32)))

  ;; [element, property, value] -> unspecified. Update a declared, typed
  ;; form-control property, initially value, checked, or selected-index. Do not
  ;; overwrite an in-progress IME composition or reset selection merely because a
  ;; view rerenders. This is not arbitrary JavaScript property access; the
  ;; permitted property schema remains to be finalized.
  (import "snail.dom" "set-property"
    (func (param $arguments i32) (result i32)))

  ;; [node, event-kind, handler-key, options] -> subscription-ref. Subscribe to a
  ;; semantic DOM event such as activate, input, change, submit, or composition.
  ;; Copy only declared data into a dom-event snapshot; retain handler-key data
  ;; until unlisten/retirement. Capture/passive/default-action policy is
  ;; registered up front. A requested preventDefault must run synchronously in a
  ;; cancellable, non-passive browser listener before returning, not after an
  ;; async Scheme reply.
  (import "snail.dom" "listen"
    (func (param $arguments i32) (result i32)))

  ;; [subscription] -> unspecified. Remove the browser listener and retire its
  ;; handler binding. Late queued events for that subscription cannot dispatch
  ;; into retired Scheme code.
  (import "snail.dom" "unlisten"
    (func (param $arguments i32) (result i32)))

  ;; ---- Application handlers ----

  ;; [] -> unspecified. Called once after initialization and again on supported
  ;; restoration from page suspension. Create or restore the surface and
  ;; rendering bindings. Keep initialization idempotent; an ordinary visibility
  ;; change is not necessarily a resource-losing suspension.
  (func (export "snail:resumed") (param $arguments i32) (result i32) unreachable)

  ;; [] -> unspecified. Notify a supported page suspension, such as entry into
  ;; the back/forward cache. Pause presentation work. Browser freezing/discard is
  ;; not guaranteed to deliver this callback; durable state cannot depend on it.
  (func (export "snail:suspended") (param $arguments i32) (result i32) unreachable)

  ;; [surface, event] -> unspecified. Deliver surface resize/scale, focus,
  ;; visibility, pointer/key input, or redraw-requested snapshots. A surface
  ;; follows its DOM container's layout, not necessarily the browser viewport.
  ;; Text editing/IME uses semantic DOM events rather than synthesizing text from
  ;; key codes. The input-routing schema must avoid treating a control activation
  ;; as a second game command.
  (func (export "snail:window-event") (param $arguments i32) (result i32) unreachable)

  ;; [message] -> unspecified. Deliver queued connection or worker completions on
  ;; the DOM-owning event thread. Worker actors exchange serialized
  ;; S-expressions; the main-thread binding constructs roots in this instance
  ;; after decoding.
  (func (export "snail:user-event") (param $arguments i32) (result i32) unreachable)

  ;; [] -> unspecified. Best-effort application teardown on explicit stop.
  ;; Browser tab closure, process death, and navigation do not promise a final
  ;; callback. Retire listeners/handles in the owning host and persist important
  ;; state before this point.
  (func (export "snail:exiting") (param $arguments i32) (result i32) unreachable)

  ;; [surface, handler-key, event] -> unspecified. Consume an immutable snapshot
  ;; of a declared semantic event: target identity, value/checked state,
  ;; selection, composition state, and modifiers only where that event type
  ;; defines them. Do not expose a live DOM Event object. A reducer computes the
  ;; next model; a Scheme tree renderer issues DOM operations. Returning later
  ;; cannot retroactively cancel the browser's default action.
  (func (export "snail:dom-event") (param $arguments i32) (result i32) unreachable)

)
