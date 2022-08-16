#pragma once

#include "ss-core/object.hh"

namespace ss {
  
  enum class RelVarScope { Local, Free, Global };

  OBJECT macroexpand_syntax(OBJECT expr_stx);

}