#include "ss-jit/vthread.hh"

#include "ss-core/object.hh"

namespace ss {

    void VThread::init(OBJECT init_val_rib) {
        m_regs.init(&m_gc_tfe, init_val_rib);
    }

    void VmRegs::init(GcThreadFrontEnd* gc_tfe, OBJECT init_val_rib) {
        a = OBJECT::make_null();
        // m_reg.x set by loader.
        e = list(gc_tfe, init_val_rib);
        r = OBJECT::make_null();
        s = 0;
    }

}   // namespace ss
