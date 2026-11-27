//! Native Git operations used by the Scheme package resolver. Only tag lookup
//! and checkout open a remote. Verification uses the existing checkout offline.
use git2::{
    AutotagOption, Config, Cred, CredentialType, Direction, Error, ErrorClass, FetchOptions,
    ObjectFormat, Oid, ProxyOptions, Reference, Remote, RemoteCallbacks, Repository,
    RepositoryInitOptions, StatusOptions,
};
use std::{
    env, fs,
    path::{Path, PathBuf},
    process::ExitCode,
};
use url::Url;

type Result<T> = std::result::Result<T, Error>;

// ---- Transport ----

fn proxy() -> ProxyOptions<'static> {
    let mut proxy = ProxyOptions::new();
    proxy.auto();
    proxy
}

fn default_ssh_keys() -> impl Iterator<Item = PathBuf> {
    env::home_dir()
        .into_iter()
        .flat_map(|home| {
            ["id_ed25519", "id_ecdsa", "id_rsa"].map(|name| home.join(".ssh").join(name))
        })
        .filter(|key| key.is_file())
}

// libgit2 verifies TLS certificates and SSH host keys. An SSH agent can try
// several identities in one credential. A rejected credential must not be
// offered forever when libgit2 asks again.
fn callbacks() -> RemoteCallbacks<'static> {
    let mut callbacks = RemoteCallbacks::new();
    let mut tried_agent = false;
    let mut tried_https = false;
    let mut keys = default_ssh_keys();
    callbacks.credentials(move |url, username, allowed| {
        if allowed.contains(CredentialType::USERNAME) {
            return Cred::username(username.unwrap_or("git"));
        }
        if allowed.contains(CredentialType::SSH_KEY) {
            let user = username.unwrap_or("git");
            if !tried_agent {
                tried_agent = true;
                return Cred::ssh_key_from_agent(user);
            }
            if let Some(key) = keys.next() {
                return Cred::ssh_key(user, None, &key, None);
            }
        }
        if allowed.contains(CredentialType::USER_PASS_PLAINTEXT) && !tried_https {
            tried_https = true;
            return Cred::credential_helper(&Config::open_default()?, url, username);
        }
        Err(Error::from_str("Git authentication failed"))
    });
    callbacks
}

fn check_tag(name: &str) -> Result<()> {
    if name.starts_with("refs/tags/") && Reference::is_valid_name(name) {
        Ok(())
    } else {
        Err(Error::from_str(&format!("invalid Git tag: {name}")))
    }
}

fn tag_id(url: &str, name: &str) -> Result<Oid> {
    check_tag(name)?;
    let mut remote = Remote::create_detached(url)?;
    let connection = remote.connect_auth(Direction::Fetch, Some(callbacks()), Some(proxy()))?;
    let refs = connection.list()?;
    let find = |name: &str| {
        refs.iter()
            .find(|item| item.name() == name)
            .map(|item| item.oid())
    };
    find(&format!("{name}^{{}}"))
        .or_else(|| find(name))
        .ok_or_else(|| Error::from_str(&format!("Git tag not found: {name}")))
}

fn commit_id(hex: &str) -> Result<Oid> {
    let format = match hex.len() {
        40 => ObjectFormat::Sha1,
        64 => ObjectFormat::Sha256,
        _ => return Err(Error::from_str("expected a full Git commit hash")),
    };
    Oid::from_str_ext(hex, format)
}

// ---- Checkout ----

fn download(remote: &mut Remote<'_>, refs: &[&str], depth: i32) -> Result<()> {
    let mut options = FetchOptions::new();
    options
        .remote_callbacks(callbacks())
        .proxy_options(proxy())
        .depth(depth)
        .download_tags(AutotagOption::None);
    remote.download(refs, Some(&mut options))
}

fn local_path(url: &str) -> Result<Option<PathBuf>> {
    if url.starts_with("file://") {
        return Url::parse(url)
            .ok()
            .and_then(|url| url.to_file_path().ok())
            .map(Some)
            .ok_or_else(|| Error::from_str("invalid local repository URL"));
    }
    Ok(Path::new(url).is_absolute().then(|| PathBuf::from(url)))
}

// A local repository can supply any commit still in its object database,
// even after a tag or branch was deleted. Copy that commit and its tree
// into an independent pack and record its shallow boundary.
fn copy_local(repo: &Repository, path: &Path, id: Oid) -> Result<()> {
    let source = Repository::open(path)?;
    let commit = source.find_commit(id)?;
    let mut pack = source.packbuilder()?;
    pack.insert_commit(id)?;
    pack.write(&repo.path().join("objects/pack"), 0)?;
    if commit.parent_count() > 0 {
        fs::write(repo.path().join("shallow"), format!("{id}\n"))
            .map_err(|error| Error::from_str(&error.to_string()))?;
    }
    Ok(())
}

// A stock upload-pack can serve only advertised refs. Prefer a ref that
// already names the pin, then try the ID directly. If the server requires
// refs and the pin is an ancestor, its advertised history supplies it.
fn fetch_commit(repo: &Repository, url: &str, id: Oid) -> Result<()> {
    let mut remote = repo.remote_anonymous(url)?;
    if let Some(path) = local_path(remote.url()?)? {
        return copy_local(repo, &path, id);
    }
    let mut connection = remote.connect_auth(Direction::Fetch, Some(callbacks()), Some(proxy()))?;
    let source = connection
        .list()?
        .iter()
        .find(|head| head.oid() == id)
        .map(|head| head.name().trim_end_matches("^{}").to_owned())
        .unwrap_or_else(|| id.to_string());
    match download(connection.remote(), &[&source], 1) {
        Ok(()) if repo.odb()?.exists(id) => return Ok(()),
        Err(error) if error.class() != ErrorClass::Invalid => return Err(error),
        _ => {}
    }
    drop(connection);
    download(
        &mut repo.remote_anonymous(url)?,
        &[
            "+refs/heads/*:refs/remotes/package/*",
            "+refs/tags/*:refs/tags/*",
        ],
        0,
    )
}

fn checkout(url: &str, hex: &str) -> Result<()> {
    let id = commit_id(hex)?;
    let mut init = RepositoryInitOptions::new();
    init.object_format(id.object_format())
        .external_template(false)
        .no_reinit(true);
    let repo = Repository::init_opts(".", &init)?;
    fetch_commit(&repo, url, id)?;
    let commit = repo.find_commit(id)?;
    repo.checkout_tree(commit.as_object(), None)?;
    repo.set_head_detached(id)?;
    verify(&repo, id)
}

fn verify(repo: &Repository, id: Oid) -> Result<()> {
    if repo.head()?.target() != Some(id) {
        return Err(Error::from_str("wrong Git commit in cached package"));
    }
    let mut options = StatusOptions::new();
    options
        .include_untracked(true)
        .include_ignored(true)
        .recurse_untracked_dirs(true)
        .recurse_ignored_dirs(true);
    if !repo.statuses(Some(&mut options))?.is_empty() {
        return Err(Error::from_str("modified Git package checkout"));
    }
    Ok(())
}

// ---- Command line ----

fn run(args: &[String]) -> Result<()> {
    match args {
        [op, name] if op == "check-tag" => check_tag(name),
        [op, url, name] if op == "resolve-tag" => {
            print!("{}", tag_id(url, name)?);
            Ok(())
        }
        [op, url, hex] if op == "checkout" => checkout(url, hex),
        [op, hex] if op == "verify" => verify(&Repository::open(".")?, commit_id(hex)?),
        _ => Err(Error::from_str(
            "expected check-tag, resolve-tag, checkout, or verify",
        )),
    }
}

fn main() -> ExitCode {
    match run(&env::args().skip(1).collect::<Vec<_>>()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{}", error.message());
            ExitCode::FAILURE
        }
    }
}
