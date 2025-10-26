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
BACKUP_DIR="${SCRIPT_DIR}/__backup__/home_backup/$(date +%d-%H%M%S)"
OP=""

is_force_write=0
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

symlinkFile() {
    local file_or_dir="$1"
    local source_dir="$SCRIPT_DIR"
    local target_dir="$HOME/$2"
    local backup_dir="$BACKUP_DIR/$2"
    local newname="$3"

    # // -> /
    if [ -z "$2" ]; then
        target_dir="$HOME"
        backup_dir="$BACKUP_DIR"
    fi

    # Source and target files
    local source="${source_dir}/$file_or_dir"
    local target="${target_dir}/$(basename "$file_or_dir")"

    if [ ! -z "$newname" ]; then
        target=${target_dir}/$newname
    fi

    # Ensure the target directory exists
    mkdir -p "$target_dir"

    # If the target file or directory already exists in your home directory and is a symbolic link,
    # specifying the `-f` option will force its removal;
    # otherwise you'll need to handle it manually.
    if [ -L "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            # Remove the symlink
            unlink "$target"
        else
            printf "${WARN} ${YELLOW}%s${RESET} already symlinked.\n" "$target"
            return
        fi
    fi

    # If the target file or directory is a regular file or directory,
    # specifying the `-f` option will move it to the specified backup directory;
    # otherwise you'll need to handle it manually.
    if [ -e "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            # NOTE: If the file or directory has not been modified, it does not need to be backed up.
            # if ! is_same_mtime "$source" "$target"; then
            # fi
            # Backup target files to $backup_dir
            mkdir -p "$backup_dir"
            mv "$target" -t "$backup_dir"
            printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}.\n" "$target" "$backup_dir"
        else
            printf "${ERROR} ${YELLOW}%s${RESET} exists but it's not a symlink, try run again with -f option.\n" "$target"
            exit 1
        fi
    fi

    # Finally, if the above steps complete without issues,
    # a symbolic link pointing from the target directory to the corresponding source file or directory
    # in the repository will be created.
    ln -s "$source" "$target"
    printf "${OK} ${YELLOW}%s${RESET} -> ${SKY_BLUE}%s${RESET}\n" "$target" "$source"
}

copyFile() {
    local file_or_dir="$1"
    local source_dir="$SCRIPT_DIR"
    local target_dir="$HOME/$2"
    local backup_dir="$BACKUP_DIR/$2"
    local newname="$3"

    # // -> /
    if [ -z "$2" ]; then
        target_dir="$HOME"
        backup_dir="$BACKUP_DIR"
    fi

    # Source and target files/directories
    local source="${source_dir}/$file_or_dir"
    local target="${target_dir}/$(basename "$file_or_dir")"

    if [ ! -z "$newname" ]; then
        target=${target_dir}/$newname
    fi

    # Ensure the target directory exists
    mkdir -p "$target_dir"

    # If the target file or directory already exists in your home directory and is a symbolic link,
    # specifying the `-f` option will force its removal;
    # otherwise you'll need to handle it manually.
    if [ -L "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            # Remove the symlink
            unlink "$target"
        else
            printf "${WARN} ${YELLOW}%s${RESET} already symlinked, try run again with -f option.\n" "$target"
            return
        fi
    fi

    # If the target file or directory is a regular file or directory,
    # specifying the `-f` option will move it to the specified backup directory;
    # otherwise you'll need to handle it manually.
    if [ -e "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            # NOTE: If the file or directory has not been modified, it does not need to be backed up.
            if ! is_same_mtime "$source" "$target"; then
                # Backup target files to $backup_dir
                mkdir -p "$backup_dir"
                mv "$target" -t "$backup_dir"
                printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}.\n" "$target" "$backup_dir"
            fi
        else
            printf "${ERROR} ${YELLOW}%s${RESET} exists, try run again with -f option.\n" "$target"
            exit 1
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

        # If the `-o` option is used to specify an operation,
        # it overrides the operation recorded in the MANIFEST file.
        if [ ! -z "$OP" ]; then
            operation="$OP"
        fi

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
    echo "  -o : specify default operation(copy/symlink), it will ignore the operation field for all entries in the MANIFEST file."
    echo "  -h : display available options"
}

optstrings=":fh :m:o:"
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
    o)
        OP="${OPTARG}"
        printf "${INFO} Use the specified OP: %s\n" "$OP"
        ;;
    *)
        echo "Invalid option: -${OPTARG}."
        ;;
    esac
done

if [ $is_help_mode -eq 0 ]; then
    deployManifest
fi
