// Fetch private packages through the public command, using disposable loopback
// servers and keys. The servers run Git's upload-pack. The client PATH traps
// any attempt by the package manager to run Git or OpenSSH.
import assert from 'node:assert/strict';
import {execFile, spawn} from 'node:child_process';
import {copyFile, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer as httpsServer} from 'node:https';
import {createServer as tcpServer} from 'node:net';
import {tmpdir, userInfo} from 'node:os';
import {join, resolve} from 'node:path';
import {promisify} from 'node:util';

const exec = promisify(execFile), root = resolve(process.argv[2]);
const area = await mkdtemp(join(tmpdir(), 'snail-transports-'));
const client = join(area, 'client'), bin = join(client, 'bin');
const cli = join(root, 'snail-scheme'), trap = join(area, 'external-client');
const clientEnv = {...process.env, HOME: client, XDG_CONFIG_HOME: client, PATH: `${bin}:${process.env.PATH}`,
  NO_PROXY: '127.0.0.1', no_proxy: '127.0.0.1'};
const git = (cwd, ...args) => exec('git', ['-c', 'user.name=Snail', '-c', 'user.email=test@localhost',
  '-c', 'commit.gpgSign=false', '-c', 'tag.gpgSign=false', ...args], {cwd});
const put = (path, data, mode) => writeFile(path, data, {mode});

async function repository(format) {
  const path = join(area, format);
  await mkdir(path);
  await git(path, 'init', '--quiet', `--object-format=${format}`);
  await put(join(path, 'package.scm'), '(package catalog)\n');
  await put(join(path, 'version'), 'one');
  await git(path, 'add', '.');
  await git(path, 'commit', '--quiet', '-m', 'First');
  const first = (await git(path, 'rev-parse', 'HEAD')).stdout.trim();
  await git(path, 'tag', '-am', 'First release', 'v1');
  await put(join(path, 'version'), 'two');
  await git(path, 'commit', '--quiet', '-am', 'Second');
  return {path, first};
}

const servers = [];
async function listen(server) {
  await new Promise((done, fail) => server.once('error', fail).listen(0, '127.0.0.1', done));
  servers.push(server);
  return server.address().port;
}

async function install(name, url, ref) {
  const app = join(area, name);
  await mkdir(app, {recursive: true});
  await put(join(app, 'package.scm'), `(package app (depends (catalog (git "${url}" "${ref}"))))`);
  const {stdout} = await exec(cli, ['deps', app], {env: clientEnv, timeout: 20000});
  const checkout = stdout.split('\n').find(line => line.startsWith('catalog ')).slice('catalog '.length);
  assert.equal(await readFile(join(checkout, 'version'), 'utf8'), 'one');
}

// Serve smart HTTP discovery and the upload-pack request over verified TLS.
async function httpsRemote(uploadPack, upstream) {
  const key = join(area, 'tls.key'), cert = join(area, 'tls.crt');
  await exec('openssl', ['req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
    '-subj', '/CN=127.0.0.1', '-addext', 'subjectAltName=IP:127.0.0.1', '-keyout', key, '-out', cert]);
  const auth = 'Basic ' + Buffer.from('snail:fixture').toString('base64');
  const server = httpsServer({key: await readFile(key), cert: await readFile(cert)}, (req, res) => {
    if (req.headers.authorization !== auth) {
      res.writeHead(401, {'WWW-Authenticate': 'Basic realm="catalog"'}).end();
      return;
    }
    const advertise = req.method === 'GET' && req.url === '/catalog/info/refs?service=git-upload-pack';
    if (!advertise && !(req.method === 'POST' && req.url === '/catalog/git-upload-pack')) {
      res.writeHead(404).end();
      return;
    }
    const args = ['--stateless-rpc'];
    if (advertise) args.push('--advertise-refs');
    const service = spawn(uploadPack, [...args, upstream]);
    res.setHeader('Content-Type', `application/x-git-upload-pack-${advertise ? 'advertisement' : 'result'}`);
    if (advertise) res.write('001e# service=git-upload-pack\n0000');
    req.pipe(service.stdin);
    service.stdout.pipe(res);
  });
  return {url: `https://127.0.0.1:${await listen(server)}/catalog`, cert};
}

// Inetd mode gives each connection directly to sshd. Restrict the test
// identity to reading the one fixture, with forwarding and terminals off.
async function sshRemote(uploadPack, upstream) {
  const host = join(area, 'host-key'), key = join(area, 'client-key');
  for (const path of [host, key]) await exec('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', path]);
  const config = join(area, 'sshd_config');
  await put(config, [`HostKey ${host}`, `AuthorizedKeysFile ${key}.pub`, 'StrictModes no',
    'PasswordAuthentication no', 'KbdInteractiveAuthentication no', 'UsePAM no', 'PermitRootLogin prohibit-password',
    'DisableForwarding yes', 'PermitTTY no', `AllowUsers ${userInfo().username}`,
    `ForceCommand "${uploadPack}" "${upstream}"`].join('\n') + '\n');
  const sshd = (await exec('sh', ['-c', 'command -v sshd'])).stdout.trim();
  const port = await listen(tcpServer(socket => {
    const session = spawn(sshd, ['-i', '-e', '-f', config], {stdio: [socket, socket, 'ignore']});
    session.on('close', () => socket.destroy());
  }));
  return {url: `ssh://${userInfo().username}@127.0.0.1:${port}/catalog`, key,
    knownHost: `[127.0.0.1]:${port} ${await readFile(host + '.pub', 'utf8')}`};
}

let agentPid;
try {
  await mkdir(bin, {recursive: true});
  await mkdir(join(client, '.ssh'), {mode: 0o700});
  await exec(cli, ['deps', root]); // Warm the launcher under its normal toolchain environment.
  for (const name of ['git', 'ssh']) {
    await put(join(bin, name), `#!/bin/sh\necho ${name} >> "${trap}"\nexit 1\n`, 0o755);
  }
  const sha1 = await repository('sha1'), sha256 = await repository('sha256');
  const uploadPack = join((await git(root, '--exec-path')).stdout.trim(), 'git-upload-pack');

  const web = await httpsRemote(uploadPack, sha1.path);
  await assert.rejects(install('https', web.url, 'v1'), /certificate/i);
  clientEnv.SSL_CERT_FILE = web.cert;
  const helper = join(bin, 'get-credentials');
  await put(helper, '#!/bin/sh\nprintf "username=snail\\npassword=fixture\\n"\n', 0o755);
  await put(join(client, '.gitconfig'), `[credential]\nhelper = ${helper}\n`);
  await install('https', web.url, 'v1');

  const ssh = await sshRemote(uploadPack, sha256.path);
  const socket = join(area, 'agent.sock');
  const agent = await exec('ssh-agent', ['-s', '-a', socket]);
  agentPid = Number(/SSH_AGENT_PID=(\d+)/.exec(agent.stdout)[1]);
  clientEnv.SSH_AUTH_SOCK = socket;
  await exec('ssh-add', [ssh.key], {env: clientEnv});
  await assert.rejects(install('ssh', ssh.url, 'v1'), /certificate|host ?key/i);
  await put(join(client, '.ssh/known_hosts'), ssh.knownHost, 0o600);
  await install('ssh', ssh.url, 'v1');

  // A stock upload-pack can serve commit history without advertising
  // fetch-by-ID. The pinned ancestor must still be available after tag removal.
  await git(sha1.path, 'tag', '-d', 'v1');
  await git(sha256.path, 'tag', '-d', 'v1');
  await install('https-hash', web.url, sha1.first);
  await install('ssh-hash', ssh.url, sha256.first);
  delete clientEnv.SSH_AUTH_SOCK;
  await copyFile(ssh.key, join(client, '.ssh/id_ed25519'));
  await install('ssh-key-file', ssh.url, sha256.first);
  await assert.rejects(readFile(trap), {code: 'ENOENT'});
  console.log('private HTTPS and SSH packages passed');
} finally {
  if (agentPid) process.kill(agentPid, 'SIGTERM');
  for (const server of servers) await new Promise(done => server.close(done));
  await rm(area, {recursive: true, force: true});
}
