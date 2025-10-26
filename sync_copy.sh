#!/usr/bin/env bash

# shellcheck disable=SC2034
# shellcheck disable=SC2155

set -e

# If you choose the symlink option, manual syncing is not required.

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
BACKUP_DIR="${SCRIPT_DIR}/__backup__/repo_backup/$(date +%d-%H%M%S)"

is_help_mode=0

is_same_mtime() {
    local src=$1
    local tgt=$2
    if [ ! -e "$src" ] || [ ! -e "$tgt" ]; then
        return 2
    fi

    local t1=$(stat -c %Y "$src")
    local t2=$(stat -c %Y "$tgt")
    if [ "$t1" -eq "$t2" ]; then
        return 0
    else
        return 1
    fi
}

copyFile() {
    local file_or_dir="$1"
    local source_dir="$HOME/$2"
    local target_dir="$SCRIPT_DIR"
    local backup_dir="$BACKUP_DIR/$(dirname "$file_or_dir")"
    local newname="$3"

    # // -> /
    if [ -z "$2" ]; then
        source_dir="$HOME"
    fi

    # Source and target files/directories
    local source="${source_dir}/$(basename "$file_or_dir")"
    local target="${target_dir}/$file_or_dir"

    if [ ! -z "$newname" ]; then
        source=${source_dir}/$newname
    fi

    # Ensure the target directory exists
    mkdir -p "$target_dir"

    # If the target file or directory already exists in your home directory and is a symbolic link,
    # Just skiping it.
    if [ -L "$source" ]; then
        printf "${WARN} ${YELLOW}%s${RESET} already symlinked and doesn't need to sync it. skiping...\n" "$source"
        return
    fi

    if [ -e "$source" ]; then
        # NOTE: If the file or directory has not been modified, it does not need to be backed up.
        if ! is_same_mtime "$source" "$target"; then
            mkdir -p "$backup_dir"
            mv "$target" -t "$backup_dir"
            printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}.\n" "$target" "$backup_dir"
        fi
    fi

    # Finally, if the above steps complete without issues,
    # the corresponding source file or directory from the repository
    # will be copied into the target directory.
    # NOTE: However, if the target file or directory is identical to the corresponding file or directory in the repository,
    # it means the item has not been modified and does not need to be copied.
    if ! is_same_mtime "$source" "$target"; then
        cp -p -r "$source" "$target"
        printf "${OK} ${YELLOW}%s${RESET} has been copied to ${SKY_BLUE}%s${RESET}\n" "$source" "$target"
    else
        printf "${INFO} ${SKY_BLUE}%s${RESET} was not modified — skipping. \n" "$target"
    fi
}

syncRepoAndHome() {
    local repofile    # e.g. coding/.clang-format
    local destination # e.g. .config (relative to $HOME)
    local newname     # e.g. .clangd -> config.yaml

    while IFS= read -r row; do
        # Filter out lines that start with # and empty lines.
        if [[ $row =~ ^# || $row =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        repofile="$(echo "$row" | cut -d \| -f 1)"
        destination="$(echo "$row" | cut -d \| -f 3)"
        newname="$(echo "$row" | cut -d \| -f 4)"

        copyFile "$repofile" "$destination" "$newname"
    done <"$MANIFEST"
}

help() {
    echo "Usage: $0 [options]"
    echo "This script syncs files or directories from your local $HOME to the repository (copy)"
    echo "  -m : specify a manifest file"
    echo "  -h : display available options"
}

optstrings=":h :m:"
while getopts "${optstrings}" opt; do
    case ${opt} in
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
    syncRepoAndHome
fi
