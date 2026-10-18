ARG AGENT_BASE_IMAGE=ghcr.io/sigmalko/agents-in-docker:sha-8a5414950a08a3edb1702bf29455a6c6fec3f846
FROM docker:29-cli AS docker-cli
FROM ${AGENT_BASE_IMAGE}

LABEL org.opencontainers.image.title="agents-in-docker-with-dind" \
      org.opencontainers.image.source="https://github.com/sigmalko/agents-in-docker-with-dind"

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/

# docker:29-dind has a docker group with GID 2375. The shared socket uses
# the same numeric GID, even though the two containers have separate users.
RUN if ! getent group 2375 >/dev/null; then groupadd -g 2375 dind; fi \
    && usermod -aG "$(getent group 2375 | cut -d: -f1)" agent \
    && ln -s /var/run/dind/docker.sock /var/run/docker.sock \
    && install -d -o agent -g agent -m 0700 /home/agent/.codex /home/agent/.claude

# Both agent CLIs load these user-level instructions across workspaces.
COPY --chown=agent:agent AGENTS.md /home/agent/.codex/AGENTS.md
COPY --chown=agent:agent AGENTS.md /home/agent/.claude/CLAUDE.md
