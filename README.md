# agents-in-docker-with-dind

Run coding agents over SSH with their own Docker daemon. This project extends [agents-in-docker](https://github.com/sigmalko/agents-in-docker) with Docker CLI, Docker Compose, and Docker-in-Docker (DinD). Agents can build images and start their own services, such as Redis or containerized MCP servers.

## Architecture and security

```text
Host Docker
├── agent (SSH, Codex, Claude, Docker CLI and Compose)
└── dind (a separate Docker daemon)
    └── its own images, networks, volumes and containers (e.g. Redis, MCP)

agent:/var/run/docker.sock ── private Unix socket ──> dockerd in dind
agent:/workspaces <──────── shared volume ────────> dind:/workspaces
```

The host Docker socket is not mounted. Host `docker ps` shows the outer agent and DinD containers, but not containers created by the inner daemon. `docker ps` inside the agent shows the inner containers, not the host's containers.

**This separates Docker resources; it is not a strong security boundary.** DinD runs with `privileged`, shares the host kernel, and can potentially compromise the host. A host administrator can access its processes and data. Use trusted agents and code; use a dedicated VM or another stronger isolation boundary for untrusted workloads. Access to the DinD socket grants full control over that inner daemon. The daemon does not expose its API over TCP.

## Install from a release

Requirements: Linux with Docker Engine, the Docker Compose v2 plugin and support for privileged containers; an SSH key pair; access to the GHCR image; and sufficient disk space for nested images. Restricted VPS containers and runtimes may not support the required cgroups, networking or filesystems.

On the Docker host, download the two release assets:

```bash
mkdir -p ~/agents-in-docker-with-dind/.ssh
cd ~/agents-in-docker-with-dind
curl -fsSLO https://github.com/sigmalko/agents-in-docker-with-dind/releases/latest/download/docker-compose.yml
curl -fsSL https://github.com/sigmalko/agents-in-docker-with-dind/releases/latest/download/env.example -o .env.example
cp .env.example .env
```

Copy your SSH **public** key into `.ssh/authorized_keys` on the host and restrict its permissions:

```bash
chmod 600 .ssh/authorized_keys
```

Keep the corresponding private key on your client computer. Edit `.env`, especially `GH_TOKEN` and `AGENT_REPOSITORY`, and change any occupied ports. Keep `.env` and private keys out of Git. Start the environment:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

Connect from the client computer:

```bash
ssh -i ~/.ssh/agents-in-docker -p 2222 agent@HOST_ADDRESS
```

The release includes a standalone Compose file generated from the pinned upstream configuration and this project's overlay. The environment template points to the matching versioned agent image. GitHub sanitizes leading dots in release asset names, so the template is uploaded as `env.example` and downloaded as `.env.example`.

`SSH_PORT` and `SERVICE_PORT` publish ports `2222` and `7777` on all host IPv4 interfaces by default, as in the upstream project. Configure your firewall and SSH access accordingly. `DIND_SERVICE_PORT` publishes the DinD service port on host loopback only. See the [upstream README](https://github.com/sigmalko/agents-in-docker#readme) for details on the agent environment and credentials.

A newly published GHCR package may be private. If the image cannot be pulled anonymously, an administrator can change its visibility in package settings, or an authorized user can log in to GHCR with a token that has `read:packages` and access to the package. A public package can be pulled anonymously. Alternatively, build the image locally as described below.

The image installs this project's English-language instructions in the agent's `~/.codex/AGENTS.md` and `~/.claude/CLAUDE.md`, so both CLIs receive the same default guidance across workspaces. The instructions are guidance, not an enforcement mechanism; an explicit user request can override them. These files are part of the agent image and are recreated with the container.

## Verify Docker and run Redis

On the host, `docker ps` lists the outer containers. After connecting over SSH as `agent`:

```bash
docker version                 # Server is the DinD daemon
docker compose version
mkdir -p /workspaces/redis-demo
cd /workspaces/redis-demo
cat > compose.yaml <<'YAML'
services:
  redis:
    image: redis:7-alpine
    ports:
      - "7778:6379"
YAML
docker compose up -d
docker compose exec redis redis-cli ping  # PONG
docker ps                                  # lists the inner Redis container
```

The agent can reach that port at `dind:7778`, for example:

```bash
node -e 'const s=require("net").connect(7778,"dind",()=>s.write("*1\r\n$4\r\nPING\r\n")); s.on("data",b=>{console.log(b.toString());s.end()})'
```

Inner container ports are published in the DinD container's network namespace, not directly on the agent or host. The outer Compose file maps host `127.0.0.1:${DIND_SERVICE_PORT:-7778}` to port `7778` in DinD. Therefore Redis is available on host loopback at `127.0.0.1:7778` by default. The inner port mapping must listen on `0.0.0.0` in DinD, as above. Other ports need additional outer Compose mappings; `docker run -p` inside the agent does not by itself publish them on the host. Remove the outer mapping if host access is not needed.

Inner bind mounts are resolved by the DinD daemon, not by the client. Use paths under `/workspaces`, which has the same location in both containers. For example, after creating `/workspaces/data`, `docker run --rm -v /workspaces/data:/data alpine ls /data` sees that directory. Other paths in the agent are not automatically available to the daemon. A `docker build` context is sent to the daemon by the client.

For an MCP server using stdio, configure the MCP client to launch `docker run --rm -i ...`. For an HTTP MCP server, publish an inner port and configure the client with `http://dind:PORT`. The image, arguments and authentication depend on the server. Services on the same inner Compose network can also reach each other by service name.

Clean up the example with `docker compose down` in `/workspaces/redis-demo`.

## Data and cleanup

Outer Compose named volumes retain `/workspaces`, DinD data and SSH host keys across `docker compose down` and container recreation. This makes `/workspaces` persistent, unlike the ephemeral workspace in the upstream project. Inner containers, images, build caches and volumes consume host disk space. Agent CLI configuration and authentication elsewhere in the agent filesystem remain ephemeral when that container is recreated.

`docker compose down -v` **deletes** the project's volumes, including the workspace, DinD data and SSH host keys. Back up anything needed first. Nested containers share the host kernel and resources; DinD can also be slower than using a single daemon directly.

## Development and upstream dependency

Clone with the submodule to develop or build locally:

```bash
git clone --recurse-submodules https://github.com/sigmalko/agents-in-docker-with-dind.git
cd agents-in-docker-with-dind
cp .env.example .env
mkdir -p .ssh
# Copy an SSH public key to .ssh/authorized_keys and edit .env.
./compose up -d --build
```

If the repository was cloned without submodules, run `git submodule update --init --recursive`. The `./compose` wrapper combines `upstream/docker-compose.yml` with `compose.dind.yml`, resolving `.env` and relative paths from this repository. For example, use `./compose logs dind`, `./compose restart` or `./compose down`.

`upstream/` is a [Git submodule](https://git-scm.com/docs/gitsubmodules) pinned to a specific commit. This reuses the upstream Compose file without maintaining a duplicate in the repository. `IMAGE` selects the base image during a local build and defaults to the SHA tag matching that upstream commit. `DIND_IMAGE` selects the resulting or published agent image. To update upstream, run `git submodule update --remote upstream`, review the change and update the base image tag in `.env.example`, `Dockerfile` and `compose.dind.yml` after checking compatibility. In particular, verify the `agent` service, UID/GID 1000, `/workspaces`, SSH configuration, and DinD socket group 2375. A submodule or README link alone does not guarantee an entry in GitHub's [dependency graph](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependency-graph).

## Images, tests and releases

[GitHub Actions](.github/workflows/build-release.yml) runs real SSH and DinD integration tests for pull requests, pushes to `main` and version tags. It verifies Docker, Compose, Redis, networking, bind mounts and separation of the host and inner container lists, including the standalone release configuration. Functional tests run on AMD64; ARM64 images are built using emulation.

A successful push to `main` publishes `ghcr.io/sigmalko/agents-in-docker-with-dind:latest` and a `sha-...` image tag for `linux/amd64` and `linux/arm64`. A successful push of a tag in the form `vMAJOR.MINOR.PATCH` pointing to a commit on `main` publishes the matching image tag without `v` and creates a GitHub Release with only `docker-compose.yml` and `env.example`. The generated Compose file contains the pinned upstream configuration and uses the published image; the template selects the release's image version. The release description contains installation instructions.

To create a new release after verifying `main`:

```bash
git tag v1.2.3
git push origin v1.2.3
```

Choose an unused version for subsequent releases. The release job runs only after tests and image publication succeed. Jobs use the built-in `GITHUB_TOKEN` with the permissions each job needs.

For additional background, see [Docker Engine security](https://docs.docker.com/engine/security/) and the [official Docker image](https://hub.docker.com/_/docker).
