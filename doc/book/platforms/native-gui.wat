;; Native GUI -- proposed application interface, not implemented. The native
;; runtime owns event dispatch and calls ordinary Scheme handlers. The shared
;; callback shape follows winit ApplicationHandler, with hyphenated Scheme
;; names. Rendering and GPU resource APIs are separate from window events. See
;; https://docs.rs/winit/latest/winit/application/trait.ApplicationHandler.html
;;
;; Each call borrows an instance-local argument-vector root and returns an
;; owned result root. Brackets describe the Scheme values inside the vector. A
;; surface reference is an owned runtime resource, not a raw root/pointer sent
;; to actors. The host initializes runtime/library globals before callbacks.
;; Bodies are stubs.
;;
;; Run callbacks on the owning event thread; queue callbacks arriving during a
;; foreign call until it returns. Keep handlers short; use subordinate actors
;; for long work. Future suspended calls must allow other calls to progress.
;; This does not specify an actor-wide waiting lock or suspension across Rust/C
;; frames.
;;
;; Event types/units, window options, recoverable errors, and GPU capabilities
;; still need concrete schemas. Raw device events, new-events, about-to-wait,
;; and memory warnings are optional native capabilities, not portable browser
;; guarantees. The game must exercise real events, temporary frame heaps, and
;; hot reload.
(module

  ;; ---- Operations provided by the platform ----

  ;; [options] -> surface-ref. Create a native window after resumed; options
  ;; describe title and initial logical size. The runtime owns the window and
  ;; checks its instance/resource identity on every use. A rendering library
  ;; separately creates presentation resources; this operation does not create a
  ;; GPU device or widget tree.
  (import "snail.gui" "create-surface"
    (func (param $arguments i32) (result i32)))

  ;; [surface] -> unspecified. Close that window, invalidate its reference, and
  ;; cancel queued surface events. Retire presentation resources only after
  ;; outstanding GPU work permits it. Destruction of an already retired owned
  ;; surface is harmless; a foreign-domain reference is an error.
  (import "snail.gui" "destroy-surface"
    (func (param $arguments i32) (result i32)))

  ;; [surface] -> unspecified. Schedule a future redraw-requested window-event.
  ;; Requests can coalesce. This does not draw, present, promise a frame rate, or
  ;; call Scheme recursively.
  (import "snail.gui" "request-redraw"
    (func (param $arguments i32) (result i32)))

  ;; ---- Handlers required from the application ----

  ;; [] -> unspecified. The runtime is ready to create/use surfaces. Initialize
  ;; or recreate presentation resources as needed; repeated lifecycle
  ;; notifications must not duplicate ownership.
  (func (export "snail:resumed") (param $arguments i32) (result i32) unreachable)

  ;; [] -> unspecified. Pause presentation and release platform-invalid surface
  ;; bindings before returning. Retained application state is separate from
  ;; presentation resources; platform requirements govern which resources can
  ;; survive.
  (func (export "snail:suspended") (param $arguments i32) (result i32) unreachable)

  ;; [surface, event] -> unspecified. Receive an owned data snapshot of input,
  ;; focus, resize, scale changes, redraw-requested, or close-requested. The
  ;; handler decides how close-requested affects application lifetime. Render on
  ;; redraw-requested; a per-frame child can compute commands and retire its
  ;; temporary heap while the parent retains the window/GPU resources.
  (func (export "snail:window-event") (param $arguments i32) (result i32) unreachable)

  ;; [message] -> unspecified. Deliver queued application messages or completion
  ;; notifications on the event thread. The host retains the data until dispatch
  ;; and releases its roots afterward. Messages from another actor are decoded
  ;; S-expression values, not shared pointers.
  (func (export "snail:user-event") (param $arguments i32) (result i32) unreachable)

  ;; [] -> unspecified. Final best-effort notification when this application is
  ;; exiting. It cannot veto shutdown. The supervisor/runtime must close
  ;; connections and release resources even if this callback fails or cannot run.
  (func (export "snail:exiting") (param $arguments i32) (result i32) unreachable)

)
