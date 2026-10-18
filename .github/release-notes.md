## Installation

On a Linux host with Docker Engine and Docker Compose installed:

```bash
mkdir -p ~/agents-in-docker-with-dind/.ssh
cd ~/agents-in-docker-with-dind
curl -fsSLO https://github.com/sigmalko/agents-in-docker-with-dind/releases/download/RELEASE_TAG/docker-compose.yml
curl -fsSL https://github.com/sigmalko/agents-in-docker-with-dind/releases/download/RELEASE_TAG/env.example -o .env.example
cp .env.example .env
```

Copy your SSH **public** key to `.ssh/authorized_keys`, then run `chmod 600 .ssh/authorized_keys`. Edit `.env`, especially `GH_TOKEN`, `AGENT_REPOSITORY` and any ports you need to change. Keep the private key on your client computer.

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -i ~/.ssh/agents-in-docker -p 2222 agent@HOST_ADDRESS
```

The environment template selects this release's published image. If GHCR denies an anonymous pull, log in with an authorized token or ask the package administrator to configure visibility. The SSH and agent service ports bind all host IPv4 interfaces by default; configure your firewall.

DinD uses a privileged container and shares the host kernel. It separates the Docker daemons but is not a strong security boundary for untrusted code. See the [README](https://github.com/sigmalko/agents-in-docker-with-dind#readme) for security, persistence, networking and Redis examples.
