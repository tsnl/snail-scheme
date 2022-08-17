#pragma once

#include <string>
#include "ss-core/intern.hh"

namespace ss {
  struct FLocPos {
    long line_index;
    long column_index;
    FLocPos() = default;
    FLocPos(long li, long ci): line_index(li), column_index(ci) {}
  };
  struct FLocSpan {
    FLocPos first_pos;
    FLocPos last_pos;
    std::string as_text();
    FLocSpan() = default;
    FLocSpan(FLocPos p0, FLocPos p1): first_pos(p0), last_pos(p1) {}
  };
  struct FLoc {
    IntStr source;
    FLocSpan span;
    std::string as_text();
    FLoc() = default;
    FLoc(IntStr f, FLocSpan s): source(f), span(s) {}
  };
}
