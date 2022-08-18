#include "ss-core/pinvoke.hh"

namespace ss {
    std::optional<PlatformProcID> PlatformProcTable::lookup(IntStr proc_name) {
      auto it = m_id_symtab.find(proc_name);
      if (it != m_id_symtab.end()) {
        return {it->second};
      } else {
        return {};
      }
    }
    PlatformProcID PlatformProcTable::define(
      IntStr proc_name, 
      std::vector<IntStr> arg_names,
      PlatformProcCb cb, 
      std::string docstring,
      bool is_variadic
    ) {
      if (m_id_symtab.find(proc_name) != m_id_symtab.end()) {
        error("Cannot re-define platform procedure: " + interned_string(proc_name));
        throw SsiError();
      }
      
      if (m_cb_table.size() != m_metadata_table.size()) {
        error("Corrupt PlatformProcTable; expected hot and cold tables to be same length");
        throw SsiError();
      }
      auto new_id = m_cb_table.size();
      
      m_cb_table.emplace_back(std::move(cb));
      m_metadata_table.emplace_back(
        proc_name, 
        is_variadic ? -1 : static_cast<my_ssize_t>(arg_names.size()),
        std::move(docstring), 
        std::move(arg_names)
      );
      
      m_id_symtab[proc_name] = new_id;
      return new_id;
    }
}