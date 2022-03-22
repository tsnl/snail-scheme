#pragma once

#include <optional>
#include <cstddef>

#include "object.hh"
#include "intern.hh"

using ModuleID = size_t;
class Module;
class ModuleGraph;

class ModuleGraph {
private:
    std::vector<Module> m_modules;
    std::map<std::string, Module> m_path_to_module_map;

public:
    ModuleID load_module_from_path(std::string file_path);

public:
    Module const& module_data(ModuleID mod) const;
};

enum class ModuleState {
    Uninitialized,
    MidInitialization,
    InitializedAndFrozen,
    MidDeinitialization
};

class Module {
    friend ModuleGraph;

private:
    OBJECT m_code_obj;
    OBJECT m_env;
    ModuleState m_state;

private:
    Module(OBJECT code_obj);

public:
    bool try_run_startup_code();
    void de_initialize();
public:
    std::optional<OBJECT> lookup(IntStr name);
};
