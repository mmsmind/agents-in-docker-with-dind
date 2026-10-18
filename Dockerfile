ARG AGENT_BASE_IMAGE=ghcr.io/sigmalko/agents-in-docker:sha-8a5414950a08a3edb1702bf29455a6c6fec3f846
FROM docker:29-cli AS docker-cli
FROM ${AGENT_BASE_IMAGE}

ARG AGENT_BASE_IMAGE
# CI supplies version, revision and creation time through OCI labels.
# Clear the base image's build-specific values for local builds.
ARG IMAGE_VERSION=dev
ARG IMAGE_REVISION=""
ARG IMAGE_CREATED=""
LABEL org.opencontainers.image.title="agents-in-docker-with-dind" \
      org.opencontainers.image.description="Run coding agents over SSH with their own Docker-in-Docker daemon." \
      org.opencontainers.image.url="https://github.com/sigmalko/agents-in-docker-with-dind" \
      org.opencontainers.image.documentation="https://github.com/sigmalko/agents-in-docker-with-dind#readme" \
      org.opencontainers.image.source="https://github.com/sigmalko/agents-in-docker-with-dind" \
      org.opencontainers.image.vendor="sigmalko" \
      org.opencontainers.image.base.name="${AGENT_BASE_IMAGE}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}"

COPY --from=docker-cli /usr/local/bin/docker /usr/local/libexec/dind/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/
COPY docker-wrapper.sh /usr/local/bin/docker

RUN install -d -o agent -g agent -m 0700 /home/agent/.codex /home/agent/.claude

# Both agent CLIs load these user-level instructions across workspaces.
COPY --chown=agent:agent AGENTS.md /home/agent/.codex/AGENTS.md
COPY --chown=agent:agent AGENTS.md /home/agent/.claude/CLAUDE.md
