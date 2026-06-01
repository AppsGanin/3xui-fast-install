#!/usr/bin/env bash
# Общие функции для локальных скриптов deploy/backup/restore.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

shell_quote() {
    printf '%q' "$1"
}

init_ssh_options() {
    SSH_PORT="${SSH_PORT:-22}"
    SSH_USER="${SSH_USER:-root}"
    _KNOWN_HOSTS="${HOME}/.ssh/known_hosts"
    _SSH_SOCKET="${TMPDIR:-/tmp}/ssh-ctl-$$-${SSH_USER}.sock"

    SSH_OPTS=(
        -o StrictHostKeyChecking=accept-new
        -o UserKnownHostsFile="$_KNOWN_HOSTS"
        -o ConnectTimeout="${SSH_CONNECT_TIMEOUT:-10}"
        -o ControlMaster=auto
        -o ControlPath="$_SSH_SOCKET"
        -o ControlPersist=180
        -p "$SSH_PORT"
        ${SSH_EXTRA[@]+"${SSH_EXTRA[@]}"}
    )
    SCP_OPTS=(
        -o StrictHostKeyChecking=accept-new
        -o UserKnownHostsFile="$_KNOWN_HOSTS"
        -o ConnectTimeout="${SSH_CONNECT_TIMEOUT:-10}"
        -o ControlMaster=auto
        -o ControlPath="$_SSH_SOCKET"
        -o ControlPersist=180
        -P "$SSH_PORT"
        ${SSH_EXTRA[@]+"${SSH_EXTRA[@]}"}
    )
}
