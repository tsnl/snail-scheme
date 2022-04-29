/// Libraries
// - all packages are registered at a central `SNAIL_SCHEME_ROOT` repo whose path is an environment variable.
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

#pragma once

#include <string>
#include <optional>
#include "ss-core/object.hh"
#include "ss-core/intern.hh"
#include "ss-core/common.hh"

///
// BaseLibraryContainer
//

namespace ss {

    class BaseLibrary;

    class BaseLibraryContainer {
    private:
        UnstableHashMap<size_t, BaseLibrary*> m_index;
    public:
        BaseLibraryContainer() = default;
    public:
        void install(std::string path);
        void uninstall(OBJECT key);
        BaseLibrary* lookup(OBJECT key) const;
    };

}

///
// BaseLibrary
//

namespace ss {

    // All libraries are loaded lazily and in a cached way.
    // This lets us 'load all installed libraries' at run-time without
    // paying a variable initialization cost depending on the environment.
    // Each library is associated with a single file OR a directory containing
    // a single `init.scm` file. Each directory library may contain sub-libraries
    // that are also files or directories. Hence, each library is associated with 
    // a single OBJECT called its 'key'.
    // E.g.
    // (scheme base v1.0.0) => 
    //      (lookup (lookup (lookup 'scheme) 'base) 'v1.0.0)...
    enum BaseLibraryFlag: size_t {
        LIB_IS_DIRECTORY_NOT_SINGLE_FILE = 0x1,
        LIB_IS_PARSED_ALREADY            = 0x2,
    };
    class BaseLibrary: public BaseLibraryContainer {
    protected:
        OBJECT m_key;
        BaseLibrary* m_opt_parent;
        std::string m_relpath;
        BaseLibraryFlag m_flags;
        OBJECT m_wb_ast;
    protected:
        BaseLibrary(std::string relpath, OBJECT key, BaseLibrary* opt_parent);
    public:
        void wb_ast(OBJECT ast) { m_wb_ast = m_wb_ast; }
        OBJECT wb_ast() const { return m_wb_ast; }
    public:
        virtual std::string relpath() const = 0;
        virtual std::string abspath() const = 0;
    };

}

///
// LibraryRepository
//

namespace ss {

    // LibraryRepository 
    class LibraryRepository: public BaseLibraryContainer {
    protected:
        std::string m_abspath;

    public:
        explicit LibraryRepository(std::string abspath);

    public:
        static std::optional<LibraryRepository> load(std::string path);
        void save();
    
    public:
        std::string abspath() const { return m_abspath; }
    };

}

///
// CentralLibraryRepository
//

namespace ss {

    class CentralLibraryRepository: public LibraryRepository {
    public:
        bool try_init(std::string executable_file_path);
    private:
        bool try_init_env(std::string executable_file_path);
        bool try_init_index();
    };

}

///
// RootLibrary, SubLibrary
//

namespace ss {

    // RootLibrary is installed into a repository.
    // This string cannot be `scheme` or `srfi`
    class RootLibrary: public BaseLibrary {
        LibraryRepository* m_repo;
    public:
        RootLibrary(OBJECT key, std::string abspath, LibraryRepository* repo);
    public:
    public:
        std::string relpath() const override { return m_relpath; }
        std::string abspath() const override { return m_repo->abspath() + "/" + relpath(); }
    };

    // SubLibrary is a library contained within a RootLibrary.
    class SubLibrary: public BaseLibrary {
    public:
        SubLibrary(IntStr name, std::string relpath, BaseLibrary* parent);
    public:
        std::string relpath() const override { return m_relpath; }
        std::string abspath() const override { return m_opt_parent->abspath() + "/" + relpath(); }
    };

}