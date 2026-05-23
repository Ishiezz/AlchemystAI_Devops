#!/bin/bash

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local attempts="${3:-60}"
  local delay="${4:-5}"

  echo "Waiting for ${host}:${port} (up to $((attempts * delay)))s..." >&2
  for _ in $(seq 1 "${attempts}"); do
    if timeout 2 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
      echo "Port ${port} open on ${host}" >&2
      return 0
    fi
    sleep "${delay}"
  done

  echo "Timed out waiting for ${host}:${port}" >&2
  return 1
}

install_iii_cli() {
  if command -v iii >/dev/null 2>&1; then
    return 0
  fi

  apt-get install -y jq
  curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
  export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"
}

clone_repo() {
  local dest="/opt/alchemyst"
  mkdir -p "${dest}"
  if [ ! -d "${dest}/AlchemystAI_Devops/.git" ]; then
    git clone --depth 1 https://github.com/Ishiezz/AlchemystAI_Devops.git "${dest}/AlchemystAI_Devops"
  else
    git -C "${dest}/AlchemystAI_Devops" pull --ff-only || true
  fi
}
