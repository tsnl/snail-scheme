#pragma once

#include <vector>

#include "ss-core/gc.hh"
#include "ss-core/defn.hh"
#include "ss-core/pinvoke.hh"
#include "ss-core/object.hh"

namespace ss {
  
  enum class RelVarScope { Local, Free, Global };

  std::vector<OBJECT> macroexpand_syntax(
    GcThreadFrontEnd& gc_tfe,
    DefTable& def_tab,
    PlatformProcTable& pproc_tab,
    std::vector<OBJECT> expr_stx
  );

}