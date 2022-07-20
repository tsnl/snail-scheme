#include "ss-pkgman/library.hh"

#include "ss-config/config.hh"

#include <filesystem>
#include <sstream>
#include <cstdlib>
#include <cassert>

///
// Common
//

namespace ss {

    static std::string const ROOT_PATH_ENV_VAR = "SNAIL_SCHEME_ROOT_PATH";
    static std::string const LIB_SUBDIR = "/lib";
    static std::string const SUBREPO_SUBDIR = "/subrepo";
    static std::string const BIN_SUBDIR = "/bin";
    
    static std::string dirname(std::filesystem::path file_path, bool exists_check = true);

    static std::string dirname(std::string file_path, bool exists_check = true) {
#if CONFIG_DEBUG_MODE
        if (exists_check) {
            if (!std::filesystem::exists(file_path)) {
                throw SsiError();
            }
        }
#endif
        // scanning for the last occurrence of '/' on all platforms and '\\' on Windows
        size_t lp;
#ifdef _WIN32
        lp = file_path.find_last_of("/\\");
#else
        lp = file_path.rfind('/');
#endif
        if (lp != std::string::npos) {
            return file_path.substr(0, lp);
        } else {
            // no '/' found => this is a relpath => return '.'
            return ".";
        }
    }

}

///
// BaseLibraryContainer: inherited by LibraryRepository and BaseLibrary
//

namespace ss {

    OBJECT BaseLibraryContainer::extract_key_from_path(std::filesystem::path path) {
        std::string filename = path.filename().string();
        bool is_numeric = true;
        int num_decimal_points = 0;
        for (auto ch: filename) {
            if (isdigit(ch)) {
                // is_numeric = true;
            }
            else if (ch == '.') {
                num_decimal_points++;
                // is_numeric = true;
            }
            else {
                is_numeric = false;
                break;
            }
        }

        if (is_numeric) {
            return OBJECT::make_integer(std::strtoull(filename.c_str(), nullptr, 10));
        } else {
            return OBJECT::make_interned_symbol(intern(std::move(filename)));
        }
    }

    void BaseLibraryContainer::install(std::filesystem::path src_path, OBJECT dst_key) {
        std::stringstream dst_path_ss;
        dst_path_ss << abspath() << "/" << dst_key;
        std::filesystem::path dst_path = dst_path_ss.str();
        if (!std::filesystem::is_directory(dst_path)) {
            bool ok = std::filesystem::remove(dst_path);
            if (!ok) {
                std::stringstream ss;
                ss << "Installation failed: could not remove existing file/directory in conflict: " << dst_path;
                error(ss.str());
                throw SsiError();
            }
        }
        
        // copy from 'src_path' into 'dst_path'
        std::filesystem::copy(
            src_path, dst_path, 
            std::filesystem::copy_options::recursive | 
            std::filesystem::copy_options::update_existing |
            std::filesystem::copy_options::create_symlinks
        );

        OBJECT key = discover(dst_path);
        assert(key.as_raw() == dst_key.as_raw());

    }

    void BaseLibraryContainer::uninstall(OBJECT key) {
        auto it = m_index.find(key.as_raw());
        if (it != m_index.end()) {
            it->second->uninstall_self();
            m_index.erase(it);
        } else {
            std::stringstream ss;
            ss << "uninstall: library not installed, so no action taken: " << key << std::endl;
            warning(ss.str());
        }
    }
    BaseLibrary const* BaseLibraryContainer::lookup(OBJECT key) const {
        auto it = m_index.find(key.as_raw());
        if (it != m_index.end()) {
            return it->second;
        } else {
            return nullptr;
        }
        // TODO: perform file deletion
    }

    void BaseLibraryContainer::uninstall_self() {
        for (auto const& it: m_index) {
            it.second->uninstall_self();
        }
        m_index.clear();
    }

}

///
// CentralLibraryRepository
//

namespace ss {

    bool CentralLibraryRepository::ensure_init(std::string executable_file_path) {
        if (s_singleton == nullptr) {
            s_singleton = new CentralLibraryRepository();
        }
        return s_singleton->try_init_instance(std::move(executable_file_path));
    }
    bool CentralLibraryRepository::try_init_instance(std::string executable_file_path) {
        return (
            try_init_env(std::move(executable_file_path)) &&
            try_init_index()
        );
    }
    bool CentralLibraryRepository::try_init_env(std::string snail_scheme_root_path) {
        // determine a root path:
        // NOTE: this install directory is determined AT BUILD TIME.
        // If the installation is moved, it must be rebuilt from source with the new install path.
        // This allows us to NOT USE ENVIRONMENT VARS.
        m_abspath = std::filesystem::absolute(snail_scheme_root_path);

        // validate determined root path:
        {
            bool in_error = false;
            
            // ensuring path is a directory:
            if (!std::filesystem::is_directory(m_abspath)) {
                std::stringstream ss;
                ss  << "Supplied '-snail-root " << m_abspath << "' does not refer to a directory." << std::endl
                    << ROOT_PATH_ENV_VAR << "=" << m_abspath << std::endl;
                error(ss.str());
                in_error = true;
            }

            // Setting the correct permissions for this path: u+rwx
            // Ideally, the interpreter has its own user/group who has exclusive access to this repo.
            // For now, we assume the interpreter is running as this user.
            // https://en.cppreference.com/w/cpp/filesystem/permissions
            std::filesystem::perms p = std::filesystem::status(m_abspath).permissions();
            if ((p & std::filesystem::perms::owner_all) != std::filesystem::perms::owner_all) {
                try {
                    std::filesystem::permissions(m_abspath, std::filesystem::perms::owner_all, std::filesystem::perm_options::add);
                } catch (std::filesystem::filesystem_error) {
                    std::stringstream ss;
                    ss  << "ERROR: " << ROOT_PATH_ENV_VAR << " does not have the minimum required permission: u+rwx" << std::endl
                        << "       " << ROOT_PATH_ENV_VAR << "=" << m_abspath;
                    error(ss.str());
                    in_error = true;
                }
            }
            
            // terminating if any errors were encountered:
            if (in_error) {
                return false;
            }
        }

        // Reporting:
        {
            std::cerr << "INFO: using " << ROOT_PATH_ENV_VAR << "=" << m_abspath << std::endl;
        }

        return true;
    }

    bool CentralLibraryRepository::try_init_index() {
        assert(!m_abspath.empty() && "CentralLibraryRepository: Expected 'm_abspath' to be initialized");
        
        // ensuring the 'lib' subdirectory exists:
        auto lib_path = m_abspath + LIB_SUBDIR;
        if (!std::filesystem::is_directory(lib_path)) {
            // notifying the user:
            {
                std::stringstream ss;
                ss  << "Broken snail-root: missing subdir: " << lib_path << std::endl
                    << "Repairing...";
                info(ss.str());
            }

            // trying to create the directory
            bool libs_dir_create_ok = std::filesystem::create_directory(lib_path);
            if (!libs_dir_create_ok) {
                std::stringstream ss;
                ss  << "Could not repair snail-root: directory creation failed." << std::endl
                    << "Does the user running this process have write perissions here?" << std::endl;
                error(ss.str());
                return false;
            }
        }

        // scanning this directory:
#if CONFIG_DEBUG_MODE
        {
            size_t entry_count = 0;
            for (auto entry: std::filesystem::directory_iterator(lib_path)) {
                auto root_lib_path = entry.path();
                std::cerr << "INFO: detected cached library in snail-root: " << root_lib_path.filename() << std::endl;
                discover(std::move(root_lib_path));
                entry_count++;
            }
            std::cerr << "INFO: detected " << entry_count << " cached libs." << std::endl;
        }
#endif
        
        // returning whether successful:
        return true;
    }

    OBJECT CentralLibraryRepository::discover(std::filesystem::path dirent_path) {
        OBJECT key = extract_key_from_path(dirent_path);
        auto res = m_index.insert_or_assign(key.as_raw(), new RootLibrary(std::move(dirent_path.string()), key, this));
        if (!res.second) {
            std::stringstream ss;
            ss << "install: library re-installed: " << key << std::endl;
            warning(ss.str());
        }

        // TODO: discover sub-packages

        return key;
    }
}

///
// BaseLibrary, RootLibrary, SubLibrary
//

namespace ss {

    BaseLibrary::BaseLibrary(std::string relpath, OBJECT key, BaseLibrary* opt_parent)
    :   BaseLibraryContainer(),
        m_relpath(std::move(relpath)),
        m_key(std::move(key)),
        m_opt_parent(opt_parent),
        m_wb_ast(OBJECT::undef)
    {}

    OBJECT BaseLibrary::discover(std::filesystem::path dirent_path) {
        OBJECT key = extract_key_from_path(dirent_path);
        auto res = m_index.insert_or_assign(key.as_raw(), new SubLibrary(dirent_path.string(), key, this));
        if (!res.second) {
            std::stringstream ss;
            ss << "install: library re-installed: " << key << std::endl;
            warning(ss.str());
        }
        return key;
    }
    
}