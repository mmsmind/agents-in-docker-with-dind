#!/bin/sh
# The daemon shares this container's network namespace and listens on loopback.
# Explicit Docker contexts and hosts keep their normal meaning.
if [ -z "${DOCKER_HOST:-}" ] && [ -z "${DOCKER_CONTEXT:-}" ]; then
    use_default_host=true
    for arg in "$@"; do
        case "$arg" in
            --context|--context=*|-c) use_default_host=false; break ;;
        esac
    done
    if [ "$use_default_host" = true ]; then
        export DOCKER_HOST=tcp://127.0.0.1:2375
    fi
fi
exec /usr/local/libexec/dind/docker "$@"
