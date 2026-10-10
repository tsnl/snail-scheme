// Dirty native runtime for one-shot delimited continuations. Workers come from
// actual Wasm→LLVM, including cont.new, resume, and suspend instructions.
// Single OS thread, no asynchronous collection, fixed-size GC-managed stacks.
#define _XOPEN_SOURCE 700
#include <assert.h>
#include <gc/gc.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ucontext.h>

// ---- Contexts and consumable references ----

typedef int64_t (*Worker)(int64_t);
typedef struct Stack Stack;
typedef struct Token Token;
typedef struct {
  Token *continuation; // NULL means the computation returned normally.
  int32_t tag;
  int64_t value;
} Event;

// This is the exact layout used by the generated LLVM resume call.
_Static_assert(sizeof(Event) == 24 && offsetof(Event, tag) == 8 &&
               offsetof(Event, value) == 16, "unexpected native Event ABI");

struct Stack {
  ucontext_t context;
  void *memory;
  size_t size;
  Stack *parent;
  uint64_t handled_tags;
  unsigned foreign_barriers;
  Worker entry;
  int64_t input;
  Event event;
};
struct Token {
  Stack *leaf;
  Stack *root;
};

static Stack initial;
static Stack *active = &initial;
static struct GC_stack_base initial_bottom;
static void *initial_live;
static unsigned suspended;
static unsigned returned;
extern void wasm_init(void);
extern int64_t wasm_export_checks(void);
extern void wasm_export_double_resume(void);
extern void wasm_export_foreign_escape(void);
extern void wasm_export_null_new(void);
extern void wasm_export_null_resume(void);
extern void wasm_export_unhandled(void);
extern void wasm_export_foreign_unmatched(void);

static void trap(const char *reason) {
  fprintf(stderr, "continuation trap: %s\n", reason);
  exit(86);
}

static Token *token(Stack *leaf, Stack *root) {
  Token *result = GC_MALLOC(sizeof *result);
  assert(result);
  result->leaf = leaf;
  result->root = root;
  return result;
}

// ---- Stack switching and collection ----

static void *set_bottom(void *end) {
  struct GC_stack_base bottom = {.mem_base = end};
  GC_set_stackbottom(NULL, &bottom);
  return NULL;
}

// Parked stacks and saved register contexts are ordinary traced GC objects.
// Registering every parked stack as a permanent root would leak unreachable
// continuation cycles. Only the still-live original OS stack needs a root span.
static void transfer(Stack *from, Stack *to) {
  if (from == &initial) {
    // A local's address could miss lower spill slots. This experiment targets
    // x86-64 SysV: preserve the actual stack pointer plus its 128-byte red zone.
    uintptr_t stack_pointer;
    __asm__ volatile("mov %%rsp, %0" : "=r"(stack_pointer));
    initial_live = (void *)(stack_pointer - 128);
    GC_add_roots(initial_live, initial_bottom.mem_base);
  }
  void *bottom =
      to == &initial ? initial_bottom.mem_base : (char *)to->memory + to->size;
  // No collection or allocating callback may occur between changing the
  // collector's active-stack bound and finishing this context switch.
  GC_call_with_alloc_lock(set_bottom, bottom);
  active = to;
  if (swapcontext(&from->context, &to->context) != 0)
    abort();
  assert(active == from);
  if (from == &initial) {
    GC_remove_roots(initial_live, initial_bottom.mem_base);
    initial_live = NULL;
  }
}

// Separate compilation keeps this opaque to the worker optimizer. Do not save
// the pointer globally: its only persistent owners must be the parked context.
void native_observe(uint64_t address) {
  volatile int64_t *field = (volatile int64_t *)(uintptr_t)(address + 8);
  *field = *field;
}

static void pressure(void) {
  GC_gcollect();
  for (unsigned i = 0; i < 50000; ++i) {
    // Match the workers' box size and overwrite payloads after collection.
    // Volatile prevents dead-store removal from weakening the root test.
    volatile uint64_t *garbage = GC_MALLOC(16);
    assert(garbage);
    garbage[1] = UINT64_C(0xdeadbeef);
  }
  GC_gcollect();
}

void native_collect(void) { pressure(); }

// ---- Creating, resuming, and suspending ----

static void enter_stack(void) {
  Stack *self = active;
  int64_t value = self->entry(self->input);
  Stack *parent = self->parent;
  assert(parent);
  parent->event = (Event){.value = value};
  ++returned;
  transfer(self, parent);
  trap("completed stack was resumed");
}

uint64_t native_cont_new(uint64_t entry) {
  if (!entry)
    trap("null function reference");
  Stack *stack = GC_MALLOC(sizeof *stack);
  assert(stack);
  stack->size = 1024 * 1024;
  stack->memory = GC_MALLOC(stack->size);
  stack->entry = (Worker)(uintptr_t)entry;
  assert(stack->memory);
  if (getcontext(&stack->context) != 0)
    abort();
  stack->context.uc_stack.ss_sp = stack->memory;
  stack->context.uc_stack.ss_size = stack->size;
  stack->context.uc_link = NULL;
  makecontext(&stack->context, enter_stack, 0);
  return (uint64_t)(uintptr_t)token(stack, stack);
}

void native_cont_resume(uint64_t handle, int64_t input, uint64_t tags, Event *event) {
  Token *reference = (Token *)(uintptr_t)handle;
  if (!reference)
    trap("null continuation reference");
  if (!reference->leaf)
    trap("continuation was already consumed");
  Stack *leaf = reference->leaf;
  Stack *root = reference->root;
  reference->leaf = reference->root = NULL; // All aliases observe consumption.
  root->parent = active;
  root->handled_tags = tags;
  leaf->input = input;
  Stack *parent = active;
  transfer(parent, leaf);
  *event = parent->event;
}

int64_t native_cont_suspend(int32_t tag, int64_t payload) {
  Stack *root = active;
  for (;;) {
    if (root->foreign_barriers)
      trap("suspension would cross a Rust boundary");
    if (!root->parent)
      trap("no matching suspension handler");
    if (root->handled_tags & (UINT64_C(1) << tag))
      break;
    root = root->parent;
  }
  Stack *parent = root->parent;
  root->parent = NULL;
  parent->event = (Event){
      .continuation = token(active, root), .tag = tag, .value = payload};
  Stack *leaf = active;
  ++suspended;
  transfer(leaf, parent);
  return leaf->input;
}

// ---- Foreign-boundary fixtures ----

// These markers model an active Rust boundary; they do not run Rust code or
// prove Rust unwinding. A nested delimiter may handle suspension above a marker.
void native_foreign_enter(void) { ++active->foreign_barriers; }
void native_foreign_leave(void) {
  assert(active->foreign_barriers);
  --active->foreign_barriers;
}

// ---- Tests ----

int main(int argc, char **argv) {
  wasm_init();
  GC_get_my_stackbottom(&initial_bottom);
  if (argc == 2 && !strcmp(argv[1], "--double-resume")) {
    wasm_export_double_resume();
    abort();
  }
  if (argc == 2 && !strcmp(argv[1], "--foreign-escape")) {
    wasm_export_foreign_escape();
    abort();
  }
  if (argc == 2 && !strcmp(argv[1], "--null-new")) {
    wasm_export_null_new();
    abort();
  }
  if (argc == 2 && !strcmp(argv[1], "--null-resume")) {
    wasm_export_null_resume();
    abort();
  }
  if (argc == 2 && !strcmp(argv[1], "--unhandled")) {
    wasm_export_unhandled();
    abort();
  }
  if (argc == 2 && !strcmp(argv[1], "--foreign-unmatched")) {
    wasm_export_foreign_unmatched();
    abort();
  }
  assert(wasm_export_checks() == 42);
  pressure();
  assert(suspended == 11 && returned == 13);
  assert(GC_get_gc_no() >= 8);
  printf("ok: %u suspensions, %u completed stacks, %lu collections\n",
         suspended, returned, (unsigned long)GC_get_gc_no());
}
