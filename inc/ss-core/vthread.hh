#pragma once

#include <vector>
#include "ss-core/common.hh"
#include "ss-core/object.hh"
#include "ss-core/gc.hh"

namespace ss {
  
    using VmExpID = ssize_t;

    struct VmRegs {
    public:
        OBJECT a;       // the accumulator
        VmExpID x;      // the next expression
        ssize_t f;   // the current frame pointer on the stack
        OBJECT c;       // the current 'closure' display vector
        ssize_t s;   // the current stack pointer
    public:
        void init();
    };

    class VmStack {
    private:
        std::vector<OBJECT> m_items;

    public:
        explicit VmStack(size_t capacity)
        :   m_items(capacity, OBJECT::null)
        {}

    public:
        ssize_t push(OBJECT x, ssize_t s) {
            m_items[s] = x;
            return s + 1;
        }
        OBJECT index (ssize_t s, ssize_t i) {
            return m_items[s - i - 1];
        }
        void index_set(ssize_t s, ssize_t i, OBJECT v) {
            m_items[s - i - 1] = v;
        }
    
    public:
        std::vector<OBJECT>::iterator begin() { return m_items.begin(); }
        size_t capacity() { return m_items.size(); }
    };

    class VThread {        
    private:
        VmRegs m_regs;
        VmStack m_stack;
        GcThreadFrontEnd m_gc_tfe;
    public:
        VThread(Gc* gc, size_t stack_capacity = (4<<20))
        :   m_regs(),
            m_stack(stack_capacity),
            m_gc_tfe(gc)
        {}
    public:
        void init();
    public:
        inline VmRegs& regs() { return m_regs; }
        inline VmStack& stack() { return m_stack; }
        inline GcThreadFrontEnd* gc_tfe() { return &m_gc_tfe; }
    };

}