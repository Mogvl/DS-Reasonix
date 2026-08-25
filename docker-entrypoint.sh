#!/bin/sh
# Reasonix container entrypoint.
# Runs as root so it can prepare bind-mounted directories, then drops
# privileges to uid 1000 before exec'ing the reasonix server.
set -e

UID_RUN=1000
GID_RUN=1000

# --- 1. Prepare runtime directories -------------------------------------------
mkdir -p "${REASONIX_HOME:-/home/reasonix}" /workspace /config
chown -R ${UID_RUN}:${GID_RUN} "${REASONIX_HOME:-/home/reasonix}" /workspace
chmod 700 "${REASONIX_HOME:-/home/reasonix}"

# --- 2. Seed the global config on first boot -----------------------------------
# The template lives in the read-only /config mount. Users may edit it on the
# host after first start (it is copied to the data dir, not bind-mounted).
if [ ! -f "${REASONIX_HOME:-/home/reasonix}/config.toml" ] && [ -f /config/config.toml ]; then
  cp /config/config.toml "${REASONIX_HOME:-/home/reasonix}/config.toml"
  chown ${UID_RUN}:${GID_RUN} "${REASONIX_HOME:-/home/reasonix}/config.toml"
  echo "Seeded ${REASONIX_HOME:-/home/reasonix}/config.toml from /config/config.toml"
fi

# --- 3. Write provider API keys into Reasonix's credential store (.env) --------
# reasonix resolves api_key_env values only from <Reasonix home>/.env at
# runtime, so container environment variables are copied there on every start.
cred_file="${REASONIX_HOME:-/home/reasonix}/.env"
for key in $(env | sed -n 's/^\([A-Z0-9_]*_API_KEY\|DEEPSEEK_API_KEY\)=.*/\1/p'); do
  value=$(printenv "$key" || true)
  if [ -n "$value" ]; then
    touch "$cred_file"
    chmod 600 "$cred_file"
    if grep -q "^${key}=" "$cred_file" 2>/dev/null; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$cred_file"
    else
      echo "${key}=${value}" >> "$cred_file"
    fi
    echo "Credential ${key} refreshed in ${cred_file}"
  fi
done
chown ${UID_RUN}:${GID_RUN} "$cred_file" 2>/dev/null || true

# --- 4. Assemble `reasonix serve` arguments from environment --------------------
ARGS="serve --addr 0.0.0.0:${REASONIX_SERVE_PORT:-7552}"

case "${REASONIX_SERVE_AUTH:-token}" in
  none)
    ARGS="$ARGS --auth none"
    ;;
  token)
    ARGS="$ARGS --auth token"
    if [ -n "$REASONIX_SERVE_TOKEN" ]; then
      ARGS="$ARGS --token $REASONIX_SERVE_TOKEN"
    else
      echo "REASONIX_SERVE_AUTH=token with no REASONIX_SERVE_TOKEN set: a random token is generated and printed below."
    fi
    ;;
  password)
    ARGS="$ARGS --auth password"
    if [ -n "$REASONIX_SERVE_PASSWORD" ]; then
      ARGS="$ARGS --password $REASONIX_SERVE_PASSWORD"
    else
      echo "ERROR: REASONIX_SERVE_AUTH=password requires REASONIX_SERVE_PASSWORD" >&2
      exit 1
    fi
    ;;
  *)
    echo "ERROR: unknown REASONIX_SERVE_AUTH '$REASONIX_SERVE_AUTH' (use none|token|password)" >&2
    exit 1
    ;;
esac

[ "${REASONIX_SERVE_BEHIND_PROXY:-false}" = "true" ] && ARGS="$ARGS --behind-proxy"

echo "Starting: reasonix $ARGS"
exec su-exec ${UID_RUN}:${GID_RUN} /usr/local/bin/reasonix $ARGS
