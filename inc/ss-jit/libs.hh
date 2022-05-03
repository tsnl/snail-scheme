/// Libraries
// - all packages are registered at a central `SNAIL_SCHEME_ROOT` repo whose path is determined at compile-time.
// - installations performed by copying source code + the path from which files were copied
//   - will initially try loading from original source code.
//   - if this fails, will try loading from copy, which may be stale.
//   - upon reinstallation, source directory soft-link is updated and files are re-copied.
//   - Installation => copying + pre-compilation
// - libraries referenced/loaded by a unique library identifiers: (list of identifier or 0.1)
//   - cf R7RS-Small
//   - The first identifier specifies a library root. Each subsequent identifier or number corresponds to a 
//     directory name within this library root (sub-libraries). The library root also contains the library
//     loader entry-point, named `init.scm`
//   - Upon library pre-compilation, all libraries and sub-packages are compiled into byte-code.
// - each library is a directory containing a `main.scm` file

#pragma once

#include <string>
#include <optional>
#include <filesystem>
#include "ss-core/object.hh"
#include "ss-core/intern.hh"
#include "ss-core/common.hh"

///
// BaseLibraryContainer
//

namespace ss {

    class BaseLibrary;

    class BaseLibraryContainer {
    protected:
        UnstableHashMap<size_t, BaseLibrary*> m_index;
    public:
        BaseLibraryContainer() = default;
    public:
        virtual OBJECT discover(std::filesystem::path dirent_path) = 0;
        void install(std::filesystem::path src_path, OBJECT dst_key);
        void uninstall(OBJECT key);
        BaseLibrary const* lookup(OBJECT key) const;
        void uninstall_self();
    public:
        static OBJECT extract_key_from_path(std::filesystem::path path);
    public:
        virtual std::string abspath() const = 0;
    };

}

///
// LibraryRepository, CentralLibraryRepository
//

namespace ss {

    class CentralLibraryRepository: public BaseLibraryContainer {
    private:
        std::string m_abspath;
        bool m_is_init;
    private:
        inline static CentralLibraryRepository* s_singleton = nullptr;
    public:
        static bool ensure_init(std::string snail_scheme_root_path);
    private:
        bool try_init_instance(std::string snail_scheme_root_path);
        bool try_init_env(std::string snail_scheme_root_path);
        bool try_init_index();
    public:
        OBJECT discover(std::filesystem::path path) override;
    public:
        void abspath(std::string v) { m_abspath = std::move(v); }
        std::string abspath() const override { return m_abspath; }
    };

}

///
// BaseLibrary, RootLibrary, SubLibrary
//

namespace ss {

    // All libraries are loaded lazily and in a cached way.
    // This lets us 'load all installed libraries' at run-time without
    // paying a variable initialization cost depending on the environment.
    // Each library is a directory, optionally containing a single `main.scm` file. 
    // Each directory library may contain sub-libraries that are also directories. 
    // Hence, each library is associated with a single OBJECT called its 'key' that
    // is the name of the directory containing 'main.scm' and/or more sub-directories.
    // E.g.
    // (scheme base 1 0 0) => /scheme/base/1/0/0/main.scm
    class BaseLibrary: public BaseLibraryContainer {
    protected:
        std::string m_relpath;
        OBJECT m_key;
        BaseLibrary* m_opt_parent;
        OBJECT m_wb_ast;
    protected:
        BaseLibrary(std::string relpath, OBJECT key, BaseLibrary* opt_parent);
    public:
        bool is_parsed() { return !m_wb_ast.is_undef(); }
        void wb_ast(OBJECT ast) { m_wb_ast = ast; }
        OBJECT wb_ast() const { return m_wb_ast; }
    public:
        std::string relpath() const { return m_relpath; };
    public:
        OBJECT discover(std::filesystem::path path) override;
    };

    // RootLibrary is installed into a repository.
    // This string cannot be `scheme` or `srfi`
    class RootLibrary: public BaseLibrary {
    private:
        CentralLibraryRepository* m_clr;
    public:
        RootLibrary(std::string relpath, OBJECT key, CentralLibraryRepository* clr)
        :   BaseLibrary(std::move(relpath), std::move(key), nullptr),
            m_clr(clr)
        {}
    public:
        std::string abspath() const override { return m_clr->abspath() + "/" + relpath(); }
    };

    // SubLibrary is a library contained within a RootLibrary.
    class SubLibrary: public BaseLibrary {
    public:
        SubLibrary(std::string relpath, OBJECT key, BaseLibrary* parent)
        :   BaseLibrary(std::move(relpath), std::move(key), nullptr)
        {}
    public:
        std::string abspath() const override { return m_opt_parent->abspath() + "/" + relpath(); }
    };

}
