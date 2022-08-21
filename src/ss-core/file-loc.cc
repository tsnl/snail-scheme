#include "ss-core/file-loc.hh"

#include <sstream>

namespace ss {
  std::string FLocSpan::as_text(bool include_guard_brackets) {
      std::stringstream ss;
      
      if (include_guard_brackets) {
        ss << '[';
      }
      
      if (first_pos.line_index == last_pos.line_index) {
          ss << 1+first_pos.line_index << ":";
          if (first_pos.column_index == last_pos.column_index) {
              ss << 1+first_pos.column_index;
          } else {
              ss << 1+first_pos.column_index << "-" << 1+last_pos.column_index;
          }
      } else {
          ss 
            << 1+first_pos.line_index << ":" << 1+first_pos.column_index << "-"
            << 1+last_pos.line_index << ":" << 1+last_pos.column_index;
      }
      
      if (include_guard_brackets) {
        ss << ']';
      }
      
      return ss.str();   
  }
  std::string FLoc::as_text() {
    return interned_string(source) + ":" + span.as_text(false);
  }
}
