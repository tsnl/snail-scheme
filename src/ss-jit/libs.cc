#include "ss-jit/libs.hh"

#include "ss-config/config.hh"

#include <filesystem>
#include <sstream>
#include <cstdlib>
#include <cassert>

namespace ss {

    static std::string const ROOT_PATH_ENV_VAR = "SNAIL_SCHEME_ROOT_PATH";

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

    bool CentralLibraryRepository::try_init(std::string executable_file_path) {
        return (
            try_init_env(std::move(executable_file_path)) &&
            try_init_index()
        );     
    }

    bool CentralLibraryRepository::try_init_env(std::string executable_file_path) {
        // determine a root path:
        bool using_local_repo;
        {
            std::string const env_path = std::getenv(ROOT_PATH_ENV_VAR.c_str());
            using_local_repo = env_path.empty();
            if (using_local_repo) {
                // local/portable interpreter build: setenv ourselves
                m_abspath = dirname(executable_file_path);
            } else {
                // use the global environment variable-specified central library repo:
                m_abspath = env_path;
            }
        }

        // validate determined root path:
        {
            bool in_error = false;
            
            // ensuring path is a directory:
            if (!std::filesystem::is_directory(m_abspath)) {
                std::stringstream ss;
                ss  << "ERROR: " << ROOT_PATH_ENV_VAR << " does not refer to a directory." << std::endl
                    << "       " << ROOT_PATH_ENV_VAR << "=" << m_abspath;
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
            if (!in_error) {
                throw SsiError();
            }
        }

        // set the environment variable to the computed root path:
        {
#ifdef _WIN32
            _putenv_s(ROOT_PATH_ENV_VAR.c_str(), m_abspath.c_str());
#else
            setenv(ROOT_PATH_ENV_VAR.c_str(), m_abspath.c_str());
#endif
        }

        // Reporting:
        {
            std::cerr << "INFO: using " << ROOT_PATH_ENV_VAR << "=" << m_abspath << " (local=" << using_local_repo << ")" << std::endl;
        }

        return true;
    }

    bool CentralLibraryRepository::try_init_index() {
        assert(!m_abspath.empty() && "CentralLibraryRepository: Expected 'm_abspath' to be initialized");
        // TODO: initialize the index by scanning all available directory entries
        // - upon install, we always copy relevant portions of the source subtree into the root.
        // - upon init-index, scan all files in the `lib` subdirectory of the root directory
        return true;
    }

}