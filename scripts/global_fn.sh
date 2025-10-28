#!/usr/bin/env bash

# shellcheck disable=SC2034
# shellcheck disable=SC2155

# Colored text
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
BLUE="$(tput setaf 4)"
MAGENTA="$(tput setaf 5)"
SKY_BLUE="$(tput setaf 6)"
ORANGE="$(tput setaf 214)"
RESET="$(tput sgr0)"
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
WARN="$(tput setaf 214)[WARN]$(tput sgr0)"
ACTION="$(tput setaf 6)[ACTION]$(tput sgr0)"

norm() { realpath -m "$1"; }

norm_nosym() {
    realpath -m --no-symlinks "$1"
}

is_diff_mtime() {
    local src=$1
    local tgt=$2
    if [ ! -e "$src" ] || [ ! -e "$tgt" ]; then
        return 2
    fi

    local t1=$(stat -c %Y "$src")
    local t2=$(stat -c %Y "$tgt")
    if [ "$t1" -ne "$t2" ]; then
        return 0
    else
        return 1
    fi
}
