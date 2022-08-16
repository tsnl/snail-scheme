#pragma once

#include <string>
#include "ss-core/intern.hh"

namespace ss {
  struct FLocPos {
    long line_index;
    long column_index;
  };
  struct FLocSpan {
    FLocPos first_pos;
    FLocPos last_pos;
    std::string as_text();
  };
  struct FLoc {
    IntStr source;
    FLocSpan span;
    std::string as_text();
  };
}
