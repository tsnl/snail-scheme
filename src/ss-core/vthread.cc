#include "ss-core/vthread.hh"

#include "ss-core/object.hh"

namespace ss {

    void VThread::init() {
        m_regs.init();
    }

    void VmRegs::init() {
        a = OBJECT::null;
        // m_reg.x set by VCode loader.
        f = 0;
        c = OBJECT::null;
        s = 0;
    }

}   // namespace ss
