#!/usr/bin/env bash
# Run a command in a disposable, network-isolated fake Internet.
#
# The command runs in bubblewrap's private user, mount, PID, and network
# namespaces.  Its only writable filesystem is SANDBOX_ROOT.  HTTP(S) goes to
# a local static MITM proxy. github.com SSH uses a sandbox-local git-upload-pack
# shim; neither transport can reach the host network.

set -euo pipefail

if [ "${1:-}" = "--internal-run" ]; then
  shift
  : "${DEV_SANDBOX_ROOT:?missing DEV_SANDBOX_ROOT}"
  : "${DEV_SANDBOX_BASH:?missing DEV_SANDBOX_BASH}"

  runtime_mounts=()
  if [ -d /nix ] && [[ "$(readlink -f "$DEV_SANDBOX_BASH")" == /nix/* ]]; then
    runtime_mounts+=(--ro-bind /nix /nix)
  else
    # Non-Nix Linux distributions keep dynamic executables and their loaders
    # below these system paths.  They are read-only in the sandbox.
    for path in /usr /bin /sbin /lib /lib64; do
      [ -e "$path" ] && runtime_mounts+=(--ro-bind "$path" "$path")
    done
  fi

  bwrap \
    --unshare-user --uid 0 --gid 0 --unshare-pid --unshare-net --new-session \
    --die-with-parent --proc /proc --dev /dev --tmpfs /tmp \
    "${runtime_mounts[@]}" \
    --dir /usr \
    --bind "$DEV_SANDBOX_ROOT/root" /work \
    --bind "$DEV_SANDBOX_ROOT/root/usr/bin" /usr/bin \
    --bind "$DEV_SANDBOX_ROOT/root/usr/local" /usr/local \
    --bind "$DEV_SANDBOX_ROOT/home" /root \
    --bind "$DEV_SANDBOX_ROOT/etc" /etc \
    --chdir /work/repo \
    --clearenv \
    --setenv PATH "/usr/local/bin:/usr/bin:$PATH" \
    --setenv HOME /root \
    --setenv USER root \
    --setenv LOGNAME root \
    --setenv CURL_CA_BUNDLE /work/certs/ca.pem \
    --setenv SSL_CERT_FILE /work/certs/ca.pem \
    --setenv GIT_SSL_CAINFO /work/certs/ca.pem \
    --setenv HTTP_PROXY http://127.0.0.1:8080 \
    --setenv HTTPS_PROXY http://127.0.0.1:8080 \
    --setenv ALL_PROXY http://127.0.0.1:8080 \
    --setenv NO_PROXY '' \
    -- "$DEV_SANDBOX_BASH" -ceu '
      python3 /work/proxy.py /work/http /work/certs >/work/logs/proxy.log 2>&1 &
      proxy_pid=$!
      cleanup() {
        kill "$proxy_pid" 2>/dev/null || true
        wait "$proxy_pid" 2>/dev/null || true
      }
      trap cleanup EXIT INT TERM
      for _ in $(seq 1 50); do
        nc -z 127.0.0.1 8080 && break
        sleep 0.05
      done
      if ! nc -z 127.0.0.1 8080; then
        cat /work/logs/proxy.log >&2 || true
        exit 1
      fi
      "$@"
    ' sandbox-command "$@"
  exit $?
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_help() {
  cat <<'EOF'
Usage: dev-sandbox.sh [options] [--] <command...>
       dev-sandbox.sh install [options] [--] [installer arguments...]

Run COMMAND in a throwaway chroot-like bubblewrap sandbox. The sandbox has no
writable host mounts: only its own root, mounted at /work, is writable.

Options:
  --persistent          Keep the whole sandbox under .hermes-sandbox/.
  --delete              Delete the persistent sandbox (asks first).
  --from DIR            One-time copy of DIR into the sandbox's $HOME.
                        Existing persistent sandboxes are never overwritten.
  --http-root DIR       Copy DIR into the fake web server root for this run.
                        Requests map to DIR/<host>/<path>; no URL is forwarded.
  --installer PATH      With `install`, serve PATH at the canonical install.sh
                        URL. Default: scripts/install.sh in this worktree.
  --from-main           With `install`, fetch the real upstream main installer
                        and repository, then advance fake main to this folder
                        after a successful install for update testing.
  -h, --help            Show this help.

The fake web server signs certificates with a CA trusted only inside this
sandbox. HTTP_PROXY/HTTPS_PROXY point at it; clearing those variables still
cannot reach the host network because the sandbox has a private network
namespace. SSH to github.com runs a sandbox-local upload-pack shim, never your
SSH config, agent, known-hosts file, or authorized keys.

Fake github main always comes from this folder. If it has staged, unstaged, or
non-ignored untracked changes, the sandbox warns and creates a temporary local
commit containing them; it never stages or commits the real worktree.

Examples:
  mkdir -p /tmp/fake-web/hermes-agent.nousresearch.com
  cp /tmp/install.sh /tmp/fake-web/hermes-agent.nousresearch.com/install.sh
  scripts/dev-sandbox.sh --http-root /tmp/fake-web -- \
    bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash'
  scripts/dev-sandbox.sh --persistent -- bash -lc \
    'git clone git@github.com:NousResearch/hermes-agent.git'
  # Runs the exact curl | bash installer command, then opens a shell on a TTY.
  scripts/dev-sandbox.sh install --persistent --installer ./install.sh
  # Install the official upstream main, then test updating to this checkout.
  scripts/dev-sandbox.sh install --persistent --from-main
  # Deterministic clone/update test without downloading the dependency graph.
  scripts/dev-sandbox.sh install --persistent -- --stage repository --non-interactive
EOF
}

PERSISTENT=false
DELETE=false
SEED_DIR=""
HTTP_ROOT=""
INSTALL_SHORTCUT=false
INSTALLER_PATH=""
INSTALL_FROM_MAIN=false

if [ "${1:-}" = install ]; then
  INSTALL_SHORTCUT=true
  shift
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --persistent) PERSISTENT=true; shift ;;
    --delete) DELETE=true; shift ;;
    --from)
      [ "$#" -ge 2 ] || { echo 'error: --from needs a directory' >&2; exit 1; }
      SEED_DIR="$2"; shift 2 ;;
    --http-root)
      [ "$#" -ge 2 ] || { echo 'error: --http-root needs a directory' >&2; exit 1; }
      HTTP_ROOT="$2"; shift 2 ;;
    --installer)
      [ "$#" -ge 2 ] || { echo 'error: --installer needs a file' >&2; exit 1; }
      INSTALLER_PATH="$2"; shift 2 ;;
    --from-main) INSTALL_FROM_MAIN=true; shift ;;
    --from=*|--http-root=*|--installer=*)
      key="${1%%=*}"; value="${1#*=}"
      [ -n "$value" ] || { echo "error: $key needs a value" >&2; exit 1; }
      case "$key" in
        --from) SEED_DIR="$value" ;;
        --http-root) HTTP_ROOT="$value" ;;
        --installer) INSTALLER_PATH="$value" ;;
      esac
      shift ;;
    -h|--help) print_help; exit 0 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

if [ "$INSTALL_SHORTCUT" = false ] && [ "$#" -eq 0 ]; then
  print_help >&2
  exit 1
fi

if [ -n "$INSTALLER_PATH" ] && [ "$INSTALL_SHORTCUT" = false ]; then
  echo 'error: --installer is only valid with the install shortcut' >&2
  exit 1
fi
if [ "$INSTALL_FROM_MAIN" = true ] && [ "$INSTALL_SHORTCUT" = false ]; then
  echo 'error: --from-main is only valid with the install shortcut' >&2
  exit 1
fi
if [ "$INSTALL_FROM_MAIN" = true ] && [ -n "$INSTALLER_PATH" ]; then
  echo 'error: --from-main and --installer cannot be combined' >&2
  exit 1
fi

for dir in "$SEED_DIR" "$HTTP_ROOT"; do
  [ -z "$dir" ] || [ -d "$dir" ] || { echo "error: directory '$dir' does not exist" >&2; exit 1; }
done

GIT_ROOT="${HERMES_SANDBOX_SOURCE_ROOT:-$(git rev-parse --show-toplevel)}"
GIT_ROOT="$(cd "$GIT_ROOT" && pwd)"
if [ "$INSTALL_SHORTCUT" = true ] && [ "$INSTALL_FROM_MAIN" = false ] && [ -z "$INSTALLER_PATH" ]; then
  INSTALLER_PATH="$GIT_ROOT/scripts/install.sh"
fi
if [ -n "$INSTALLER_PATH" ] && [ ! -f "$INSTALLER_PATH" ]; then
  echo "error: installer '$INSTALLER_PATH' does not exist" >&2
  exit 1
fi
COMMIT="$(git -C "$GIT_ROOT" rev-parse --verify 'HEAD^{commit}')" || {
  echo "error: current folder has no HEAD commit" >&2
  exit 1
}
SANDBOX_DIR_NAME="${HERMES_DEV_SANDBOX_DIR:-.hermes-sandbox}"
PERSISTENT_ROOT="$GIT_ROOT/$SANDBOX_DIR_NAME"

if [ "$DELETE" = true ]; then
  if [ ! -d "$PERSISTENT_ROOT" ]; then
    echo "[sandbox] nothing to delete at $PERSISTENT_ROOT" >&2
    exit 0
  fi
  read -r -p "[sandbox] delete $PERSISTENT_ROOT? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) rm -rf -- "$PERSISTENT_ROOT" ;;
    *) echo '[sandbox] aborted' >&2; exit 1 ;;
  esac
  exit 0
fi

if [ "$PERSISTENT" = true ]; then
  SANDBOX_ROOT="$PERSISTENT_ROOT"
else
  SANDBOX_ROOT="$(mktemp -d -t hermes-sandbox.XXXXXX)"
  cleanup() { chmod -R u+w "$SANDBOX_ROOT"; rm -rf -- "$SANDBOX_ROOT"; }
  trap cleanup EXIT INT TERM
fi

mkdir -p "$SANDBOX_ROOT"/{root,home,etc}
UPSTREAM_REPO=""
UPSTREAM_COMMIT=""
if [ "$INSTALL_FROM_MAIN" = true ]; then
  echo '[sandbox] fetching real upstream main for installer/update test' >&2
  UPSTREAM_REPO="$(mktemp -d -t hermes-sandbox-upstream.XXXXXX)"
  git -C "$UPSTREAM_REPO" init -q
  if ! git -C "$UPSTREAM_REPO" fetch -q https://github.com/NousResearch/hermes-agent.git refs/heads/main; then
    rm -rf -- "$UPSTREAM_REPO"
    echo 'error: failed to fetch real upstream main' >&2
    exit 1
  fi
  UPSTREAM_COMMIT="$(git -C "$UPSTREAM_REPO" rev-parse FETCH_HEAD)"
fi
if [ ! -e "$SANDBOX_ROOT/root/repo/.sandbox-source" ]; then
  mkdir -p "$SANDBOX_ROOT/root/repo"
  # Persistent roots live under the worktree, so copying with cp would recurse
  # into the sandbox itself. tar also lets us exclude a worktree's .git file,
  # which can point at the host's shared worktree metadata.
  tar -C "$GIT_ROOT" --exclude='./.git' --exclude="./$SANDBOX_DIR_NAME" -cf - . \
    | tar -C "$SANDBOX_ROOT/root/repo" -xf -
  : > "$SANDBOX_ROOT/root/repo/.sandbox-source"
fi

if [ -n "$SEED_DIR" ] && [ ! -e "$SANDBOX_ROOT/.seeded" ]; then
  echo "[sandbox] seeding home from $SEED_DIR" >&2
  cp -a "$SEED_DIR/." "$SANDBOX_ROOT/home/"
  : > "$SANDBOX_ROOT/.seeded"
fi

rm -rf "$SANDBOX_ROOT/root/http"
mkdir -p "$SANDBOX_ROOT/root/http"
if [ -n "$HTTP_ROOT" ]; then
  cp -a "$HTTP_ROOT/." "$SANDBOX_ROOT/root/http/"
fi
if [ "$INSTALL_SHORTCUT" = true ]; then
  mkdir -p "$SANDBOX_ROOT/root/http/hermes-agent.nousresearch.com"
  if [ "$INSTALL_FROM_MAIN" = true ]; then
    git -C "$UPSTREAM_REPO" show "$UPSTREAM_COMMIT:scripts/install.sh" \
      > "$SANDBOX_ROOT/root/http/hermes-agent.nousresearch.com/install.sh"
  else
    cp -a "$INSTALLER_PATH" "$SANDBOX_ROOT/root/http/hermes-agent.nousresearch.com/install.sh"
  fi
  set -- bash -c '
    set +e
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- "$@"
    install_status=$?
    if [ "$install_status" -eq 0 ] && [ -f /work/promote-main ]; then
      next_main=$(cat /work/promote-main)
      if git --git-dir=/work/repos/hermes-agent.git update-ref refs/heads/main "$next_main"; then
        rm -f /work/promote-main
        printf "[sandbox] fake main advanced to this folder for update testing\n" >&2
      else
        printf "[sandbox] failed to advance fake main after install\n" >&2
        install_status=1
      fi
    fi
    if [ -t 0 ] && [ -t 1 ]; then
      printf "\n[sandbox] installer exited %s; entering sandbox shell\n" "$install_status" >&2
      exec bash -i
    fi
    exit "$install_status"
  ' sandbox-installer "$@"
fi

mkdir -p "$SANDBOX_ROOT/root"/{certs,logs,repos,ssh,usr/bin,usr/local}
SANDBOX_SHELL="$(command -v bash)"
printf 'root:x:0:0:Sandbox Root:/root:%s\n' "$SANDBOX_SHELL" > "$SANDBOX_ROOT/etc/passwd"
printf 'root:x:0:\n' > "$SANDBOX_ROOT/etc/group"
printf 'hosts: files dns\n' > "$SANDBOX_ROOT/etc/nsswitch.conf"
printf '127.0.0.1 localhost github.com\n' > "$SANDBOX_ROOT/etc/hosts"

SOURCE_REPO="$GIT_ROOT"
SOURCE_REF="$COMMIT"
SNAPSHOT_REPO=""
FAKE_REPO="$SANDBOX_ROOT/root/repos/hermes-agent.git"
git -C "$SANDBOX_ROOT/root/repos" init --bare -q hermes-agent.git
if [ "$INSTALL_FROM_MAIN" = true ]; then
  git --git-dir="$FAKE_REPO" fetch -q --force "$UPSTREAM_REPO" \
    "$UPSTREAM_COMMIT:refs/heads/main"
fi
if [ -n "$(git -C "$GIT_ROOT" status --porcelain)" ]; then
  echo '[sandbox] warning: current folder is dirty; creating a temporary fake commit for main' >&2
  SNAPSHOT_REPO="$(mktemp -d -t hermes-sandbox-snapshot.XXXXXX)"
  git -C "$SNAPSHOT_REPO" init -q
  git -C "$SNAPSHOT_REPO" fetch -q "$GIT_ROOT" "$COMMIT"
  git -C "$SNAPSHOT_REPO" config user.name 'Hermes sandbox'
  git -C "$SNAPSHOT_REPO" config user.email 'sandbox@invalid'
  GIT_DIR="$SNAPSHOT_REPO/.git" GIT_WORK_TREE="$GIT_ROOT" git read-tree "$COMMIT"
  GIT_DIR="$SNAPSHOT_REPO/.git" GIT_WORK_TREE="$GIT_ROOT" \
    git add -A -- . ":(exclude)$SANDBOX_DIR_NAME"
  SNAPSHOT_TREE="$(GIT_DIR="$SNAPSHOT_REPO/.git" git write-tree)"
  SNAPSHOT_PARENT="$COMMIT"
  if EXISTING_MAIN="$(git --git-dir="$FAKE_REPO" rev-parse --verify refs/heads/main 2>/dev/null)"; then
    git -C "$SNAPSHOT_REPO" fetch -q "$FAKE_REPO" "$EXISTING_MAIN"
    SNAPSHOT_PARENT="$EXISTING_MAIN"
  fi
  SOURCE_REF="$(GIT_DIR="$SNAPSHOT_REPO/.git" git commit-tree "$SNAPSHOT_TREE" -p "$SNAPSHOT_PARENT" \
    -m 'sandbox snapshot of dirty worktree')"
  SOURCE_REPO="$SNAPSHOT_REPO"
fi

if [ "$INSTALL_FROM_MAIN" = true ]; then
  git --git-dir="$FAKE_REPO" fetch -q --force "$SOURCE_REPO" \
    "$SOURCE_REF:refs/hermes-sandbox/next"
  printf '%s\n' "$SOURCE_REF" > "$SANDBOX_ROOT/root/promote-main"
else
  git --git-dir="$FAKE_REPO" fetch -q --force "$SOURCE_REPO" \
    "$SOURCE_REF:refs/heads/main"
fi
git --git-dir="$FAKE_REPO" symbolic-ref HEAD refs/heads/main
if [ -n "$SNAPSHOT_REPO" ]; then
  rm -rf -- "$SNAPSHOT_REPO"
fi
if [ -n "$UPSTREAM_REPO" ]; then
  rm -rf -- "$UPSTREAM_REPO"
fi

if [ ! -f "$SANDBOX_ROOT/root/certs/ca.pem" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
    -subj '/CN=Hermes dev sandbox CA' \
    -keyout "$SANDBOX_ROOT/root/certs/ca.key" \
    -out "$SANDBOX_ROOT/root/certs/ca.pem" >/dev/null 2>&1
fi
GIT_UPLOAD_PACK="$(command -v git-upload-pack)"
printf '#!%s\nexec %q /work/repos/hermes-agent.git\n' "$SANDBOX_SHELL" "$GIT_UPLOAD_PACK" \
  > "$SANDBOX_ROOT/root/usr/bin/ssh"
chmod 700 "$SANDBOX_ROOT/root/usr/bin/ssh"

cat > "$SANDBOX_ROOT/root/proxy.py" <<'PY'
import pathlib, socket, ssl, subprocess, sys, threading
from urllib.parse import unquote, urlsplit

ROOT, CERTS = map(pathlib.Path, sys.argv[1:])

def read_request(conn):
    data = b""
    while b"\r\n\r\n" not in data and len(data) < 65536:
        part = conn.recv(4096)
        if not part:
            return b""
        data += part
    return data

def cert_for(host):
    safe = ''.join(char if char.isalnum() or char in '.-' else '_' for char in host)
    cert, key = CERTS / f'{safe}.pem', CERTS / f'{safe}.key'
    if not cert.exists():
        csr = CERTS / f'{safe}.csr'
        subprocess.run(['openssl', 'req', '-newkey', 'rsa:2048', '-nodes',
                        '-subj', f'/CN={host}', '-addext', f'subjectAltName=DNS:{host}',
                        '-keyout', str(key), '-out', str(csr)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['openssl', 'x509', '-req', '-days', '2', '-in', str(csr),
                        '-CA', str(CERTS / 'ca.pem'), '-CAkey', str(CERTS / 'ca.key'),
                        '-CAcreateserial', '-copy_extensions', 'copy', '-out', str(cert)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return cert, key

def file_for(host, target):
    path = urlsplit(target).path or '/'
    parts = pathlib.PurePosixPath(unquote(path)).parts
    if '..' in parts:
        return None
    candidate = ROOT / host / pathlib.PurePosixPath(*[part for part in parts if part != '/'])
    if candidate.is_dir():
        candidate /= 'index.html'
    return candidate if candidate.is_file() else None

def respond(conn, host, target):
    found = file_for(host, target)
    if found is None:
        body = f'no fake response for {host}{urlsplit(target).path or "/"}\n'.encode()
        header = b'HTTP/1.1 404 Not Found\r\n'
    else:
        body = found.read_bytes()
        header = b'HTTP/1.1 200 OK\r\n'
    conn.sendall(header + f'Content-Length: {len(body)}\r\nConnection: close\r\n\r\n'.encode() + body)

def handle(conn):
    with conn:
        request = read_request(conn)
        if not request:
            return
        line = request.split(b'\r\n', 1)[0].decode('iso-8859-1')
        method, target, _ = line.split(' ', 2)
        if method.upper() == 'CONNECT':
            host = target.rsplit(':', 1)[0]
            conn.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            cert, key = cert_for(host)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(cert, key)
            with context.wrap_socket(conn, server_side=True) as tls:
                nested = read_request(tls)
                if nested:
                    nested_target = nested.split(b'\r\n', 1)[0].decode('iso-8859-1').split(' ', 2)[1]
                    respond(tls, host, nested_target)
            return
        parsed = urlsplit(target)
        host = parsed.hostname
        if not host:
            for header in request.split(b'\r\n')[1:]:
                if header.lower().startswith(b'host:'):
                    host = header.split(b':', 1)[1].strip().decode().split(':', 1)[0]
                    break
        respond(conn, host or 'unknown', target)

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 8080))
    server.listen()
    while True:
        conn, _ = server.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()
PY

if [ "$INSTALL_FROM_MAIN" = true ]; then
  echo "[sandbox] fake main: real upstream main ($UPSTREAM_COMMIT)" >&2
  echo "[sandbox] prepared update: current folder ($SOURCE_REF)" >&2
else
  echo "[sandbox] fake main: current folder ($SOURCE_REF)" >&2
fi
echo "[sandbox] root: $SANDBOX_ROOT" >&2
echo "[sandbox] http root: $SANDBOX_ROOT/root/http" >&2
[ "$PERSISTENT" = true ] && echo '[sandbox] persistent' >&2 || echo '[sandbox] ephemeral' >&2

for command in awk bash bwrap curl git nc openssl python3 tar; do
  command -v "$command" >/dev/null || {
    echo "error: missing required command: $command" >&2
    exit 1
  }
done

exec env \
  DEV_SANDBOX_ROOT="$SANDBOX_ROOT" \
  DEV_SANDBOX_BASH="$(command -v bash)" \
  "$BASH_SOURCE" --internal-run "$@"