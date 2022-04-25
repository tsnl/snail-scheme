#include "ss-jit/vthread.hh"

#include "ss-core/object.hh"

namespace ss {

    void VThread::init() {
        m_regs.init(&m_gc_tfe);
    }

    void VmRegs::init(GcThreadFrontEnd* gc_tfe) {
        a = OBJECT::make_null();
        // m_reg.x set by VCode loader.
        e = 0;
        s = 0;
    }

}   // namespace ss
