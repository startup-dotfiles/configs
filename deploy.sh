#!/usr/bin/env bash

# This script is adapted from
# - https://github.com/rexim/dotfiles/blob/master/deploy.sh
# - https://kodekloud.com/blog/bash-getopts/

# shellcheck disable=SC2034
# shellcheck disable=SC2155

set -e

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

SCRIPT_DIR=$(dirname "$(realpath "$0")")
MANIFEST="${SCRIPT_DIR}/MANIFEST.linux"
BACKUP_DIR="${SCRIPT_DIR}/__backup__"

is_force_write=0
is_help_mode=0

symlinkFile() {
    local filename="$1"
    local destination="$HOME/$2"
    local newname="$3"

    # // -> /
    if [ -z "$2" ]; then
        destination="$HOME"
    fi

    # Source and target files
    local source="${SCRIPT_DIR}/$filename"
    local target="${destination}/$(basename "$filename")"

    if [ ! -z "$newname" ]; then
        target=${destination}/$newname
    fi

    # Ensure the target directory exists
    mkdir -p "$destination"

    # If it's a symlink, don't back it up; remove it instead.
    if [ -L "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            # Delete target files
            rm "$target"
        else
            printf "${WARN} ${YELLOW}%s${RESET} already symlinked.\n" "$target"
            return
        fi
    fi

    if [ -e "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            # Backup target files
            printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}.\n" "$target" "$BACKUP_DIR"
            mkdir -p "$BACKUP_DIR"
            mv "$target" "$BACKUP_DIR"
        else
            printf "${ERROR} ${YELLOW}%s${RESET} exists but it's not a symlink, try run again with -f option.\n" "$target"
            exit 1
        fi
    fi

    ln -s "$source" "$target"
    printf "${OK} ${YELLOW}%s${RESET} -> ${YELLOW}%s${RESET}\n" "$source" "$target"
}

copyFile() {
    local filename="$1"
    local destination="$HOME/$2"
    local newname="$3"

    # // -> /
    if [ -z "$2" ]; then
        destination="$HOME"
    fi

    # Source and target files
    local source="${SCRIPT_DIR}/$filename"
    local target="${destination}/$(basename "$filename")"

    if [ ! -z "$newname" ]; then
        target=${destination}/$newname
    fi

    # Ensure the target directory exists
    mkdir -p "$destination"

    # If it's a symlink, don't back it up; remove it instead.
    if [ -L "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            # Delete target files
            rm "$target"
        else
            printf "${WARN} ${YELLOW}%s${RESET} already symlinked, try run again with -f option.\n" "$target"
            return
        fi
    fi

    if [ -e "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            # Backup target files
            printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}.\n" "$target" "$BACKUP_DIR"
            mkdir -p "$BACKUP_DIR"
            mv "$target" "$BACKUP_DIR"
        else
            printf "${ERROR} ${YELLOW}%s${RESET} exists, try run again with -f option.\n" "$target"
            exit 1
        fi
    fi

    cp "$source" "$target"
    printf "${OK} ${YELLOW}%s${RESET} has been copied to ${YELLOW}%s${RESET}\n" "$source" "$target"
}

deployManifest() {
    local repofile    # e.g. coding/.clang-format
    local operation   # e.g. symlink
    local destination # e.g. .config (relative to $HOME)
    local newname     # e.g. .clangd -> config.yaml

    while IFS= read -r row; do
        # Filter out lines that start with # and empty lines.
        if [[ $row =~ ^# || $row =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        repofile="$(echo "$row" | cut -d \| -f 1)"
        operation="$(echo "$row" | cut -d \| -f 2)"
        destination="$(echo "$row" | cut -d \| -f 3)"
        newname="$(echo "$row" | cut -d \| -f 4)"

        case $operation in
        symlink)
            symlinkFile "$repofile" "$destination" "$newname"
            ;;
        copy)
            copyFile "$repofile" "$destination" "$newname"
            ;;
        *)
            printf "${ERROR} Unknown operation %s. Skipping..." "$operation"
            ;;
        esac
    done <"$MANIFEST"
}

help() {
    echo "Usage: $0 [options]"
    echo "This script links or copies certain files from the repository into your $HOME directory."
    echo "  -f : force overwrite target files"
    echo "  -m : specify a manifest file"
    echo "  -h : display available options"
}

optstrings=":fh :m:"
while getopts "${optstrings}" opt; do
    case ${opt} in
    f)
        is_force_write=1
        ;;
    h)
        is_help_mode=1
        help
        ;;
    m)
        MANIFEST="${OPTARG}"
        printf "${INFO} Use custom MANIFEST: %s\n" "$(realpath "$MANIFEST")"
        ;;
    *)
        echo "Invalid option: -${OPTARG}."
        ;;
    esac
done

if [ $is_help_mode -eq 0 ]; then
    deployManifest
fi
