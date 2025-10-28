#!/usr/bin/env bash

# shellcheck disable=SC2034
# shellcheck disable=SC2155
# shellcheck disable=SC2001

set -e

SCRIPT_DIR=$(dirname "$(realpath "$0")")
MANIFEST="${SCRIPT_DIR}/MANIFEST.linux"
HOME_BACKUP_DIR="${SCRIPT_DIR}/__backup__/home_backup/$(date +%y-%m-%d-%H%M%S)"
REPO_BACKUP_DIR="${SCRIPT_DIR}/__backup__/repo_backup/$(date +%y-%m-%d-%H%M%S)"
OP=""

if ! source "${SCRIPT_DIR}/scripts/global_fn.sh"; then
    echo "Error: unable to source scripts/global_fn.sh..."
    exit 1
fi

ALL=()
SOURCES=()
EXCLUDES=()
IS_EXCLUDED=0

APP_NAME=""
SOURCE_PREFIX="$SCRIPT_DIR"
TARGET_PREFIX="$HOME"
OPERATION=""
BACKUP_HOME_SUFFIX=""
BACKUP_REPO_SUFFIX=""

is_force_write=0
is_help_mode=0
is_debug_mode=0

reset_status() {
    APP_NAME=""
    SOURCE_PREFIX="$SCRIPT_DIR"
    TARGET_PREFIX="$HOME"
    OPERATION=""
    BACKUP_HOME_SUFFIX=""
    BACKUP_REPO_SUFFIX=""
}

splitDir() {

    for i in "${!EXCLUDES[@]}"; do
        EXCLUDES[i]="$(norm "${EXCLUDES[$i]}")"
    done

    local root_dir
    root_dir="$(norm "$1")"
    while IFS= read -r -d '' path; do
        if [ ! -d "$path" ]; then
            ALL+=("$(norm "$path")")
        fi
    done < <(find "$root_dir" -mindepth 1 -print0)
}

is_excluded() {
    local target
    target="$(norm "$1")"
    for ex in "${EXCLUDES[@]}"; do
        # Match the excluded directory itself or any of its subitems.
        if [[ "$target" == "$ex" || "$target" == "$ex/"* ]]; then
            return 0
        fi
    done
    return 1
}

filterPaths() {
    splitDir "$1"
    for path in "${ALL[@]}"; do
        if ! is_excluded "$path"; then
            SOURCES+=("$path")
        fi
    done

    # reset
    ALL=()
    EXCLUDES=()
}

symlinkFile() {
    local source="$1"
    local target="$2"
    local target_dir="$(dirname "$target")"
    local backup_dir="$HOME_BACKUP_DIR/$BACKUP_HOME_SUFFIX"

    # Ensure the source files/directories exists
    if [ ! -e "$source" ]; then
        printf "${ERROR} ${YELLOW}%s${RESET} does not exist - please check your MANIFEST file.\n" "$source"
        exit 1
    fi

    # If the target file or directory already exists in your home directory,
    # but it is a symbolic link, just skiping it.
    if [ -L "$target" ]; then
        printf "${WARN} ${YELLOW}%s${RESET} already symlinked. skiping...\n" "$target"

        reset_status
        return
    fi

    # If the target file or directory already exists in your $HOME directory,
    # and it is a regular file or directory.
    if [ -d "$target" ] || [ -f "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            mkdir -p "$backup_dir"
            mv "$target" -t "$backup_dir"
            printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}.\n" "$target" "$backup_dir"
        else
            printf "${ERROR} ${YELLOW}%s${RESET} exists, try run again with -f option.\n" "$target"
            exit 1
        fi
    fi

    # If the target file or directory does not exists, create the target directory.
    mkdir -p "$target_dir"

    # If the target file or directory does not exist, or has been backup
    ln -s "$source" "$target"
    printf "${OK} ${YELLOW}%s${RESET} -> ${SKY_BLUE}%s${RESET}\n" "$target" "$source"
}

copyFile() {
    local source="$1"
    local target="$2"
    local target_dir="$(dirname "$target")"
    local backup_dir="$HOME_BACKUP_DIR/$BACKUP_HOME_SUFFIX"

    # Ensure the source files/directories exists
    if [ ! -e "$source" ]; then
        printf "${ERROR} ${YELLOW}%s${RESET} does not exist - please check your MANIFEST file.\n" "$source"
        exit 1
    fi

    # If the target file or directory already exists in your home directory and is a symbolic link,
    # specifying the `-f` option will force its removal;
    # otherwise you'll need to handle it manually.
    if [ -L "$target" ]; then
        if [ $is_force_write -eq 1 ]; then
            # Remove the symlink
            unlink "$target"
        else
            printf "${WARN} ${YELLOW}%s${RESET} already symlinked, try run again with -f option.\n" "$target"

            reset_status
            return
        fi
    fi

    # If the target file or directory is a regular file or directory,
    # and it is a regular file or directory.
    # Specifying the `-f` option will move it to the specified backup directory;
    # otherwise you'll need to handle it manually.
    if [ -d "$source" ] || [ -f "$source" ]; then
        if [ $is_force_write -eq 1 ]; then
            # If the target file or directory does not exist, or has not been modified,
            # it does not need to be backed up.
            if is_diff_mtime "$source" "$target"; then
                mkdir -p "$backup_dir"
                mv "$target" -t "$backup_dir"
                printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}.\n" "$target" "$backup_dir"
            fi
        else
            printf "${ERROR} ${YELLOW}%s${RESET} exists, try run again with -f option.\n" "$target"
            exit 1
        fi
    fi

    # If the target file or directory does not exists, create the target directory.
    mkdir -p "$target_dir"

    # If the target file or directory does not exist, or has been modified,
    # then the local source and the target repository need to be synchronized.
    if [[ ! -e "$target" ]]; then
        cp -p -r "$source" "$target_dir"
        printf "${OK} ${YELLOW}%s${RESET} has been copied to ${SKY_BLUE}%s${RESET}\n" "$source" "$target_dir"
    else
        printf "${INFO} ${SKY_BLUE}%s${RESET} was not modified — skipping. \n" "$target"
    fi
}

excludeFile() {
    local source="$1"
    local target="$2"
    local target_dir="$(dirname "$target")"
    local backup_dir="$REPO_BACKUP_DIR/$BACKUP_REPO_SUFFIX"

    # If the files or directories to be excluded already exist in your $HOME directory and is a symbolic link,
    # remove this symlink directly and move the excluded files and directories back to your $HOME directory.
    if [ -L "$target" ]; then
        unlink "$target"
        mv "$source" -t "$target_dir"

        reset_status
        return
    fi

    # If the files or directories to be excluded already exist in the repository,
    # move them to the backup directory and prompt the user to update the corresponding MANIFEST file
    # by moving the exclude entries before the related entries so this does not happen on the next deployment.
    if [ -f "$source" ] || [ -d "$source" ]; then
        # Backup target files
        mkdir -p "$backup_dir"
        mv "$source" -t "$backup_dir"

        # NOTE: You should list entries to be excluded before the related entries.
        printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}. \n" "$source" "$backup_dir"
    fi

    EXCLUDES+=("${source}")
    IS_EXCLUDED=1
    printf "${WARN} ${YELLOW}%s${RESET} has been excluded.\n" "$source"
}

deployManifest() {
    local appname
    local source_suffix
    local file_or_dir
    local target_suffix
    local operation

    local source
    local target

    while IFS= read -r row; do
        # Filter out lines that start with # and empty lines.
        if [[ $row =~ ^# || $row =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        # Extract fields
        IFS='|' read -r appname source_suffix file_or_dir \
            operation target_suffix <<<"$(sed 's/ *| */|/g' <<<"$row")"

        APP_NAME="$appname"
        if [[ ! -z "$target_suffix" ]]; then
            TARGET_PREFIX+="/$target_suffix"
        fi
        SOURCE_PREFIX+="/$source_suffix"

        # $REPO -> $HOME
        source="$(norm_nosym "$SOURCE_PREFIX/$file_or_dir")"
        target="$(norm_nosym "$TARGET_PREFIX/$file_or_dir")"

        BACKUP_REPO_SUFFIX="$source_suffix/$(dirname "$file_or_dir")"
        BACKUP_HOME_SUFFIX="$target_suffix/$(dirname "$file_or_dir")"

        # If the `-o` option is used to specify an operation,
        # it overrides the operation recorded in the MANIFEST file.
        if [[ ! -z "$OP" ]] && [[ "$operation" != "exclude" ]]; then
            operation="$OP"
        fi

        # DEBUG: INFO
        if [[ $is_debug_mode -ne 0 ]]; then
            SOURCE="$source"
            TARGET="$target"
            OPERATION="$operation"

            log_info
            continue
        fi

        case $operation in
        symlink)
            if [[ "$IS_EXCLUDED" -eq 1 ]]; then
                filterPaths "$source"
                for path in "${SOURCES[@]}"; do
                    source="$(norm_nosym "$path")"
                    target="$(norm_nosym "$TARGET_PREFIX/${path#"$SOURCE_PREFIX/"}")"

                    BACKUP_REPO_SUFFIX="$(dirname "${source#"$SCRIPT_DIR/"}")"
                    BACKUP_HOME_SUFFIX="$(dirname "${target#"$HOME/"}")"

                    symlinkFile "$source" "$target"
                done
                IS_EXCLUDED=0
                SOURCES=()
                reset_status
            else
                symlinkFile "$source" "$target"
                reset_status
            fi
            ;;
        copy)
            if [[ "$IS_EXCLUDED" -eq 1 ]]; then
                filterPaths "$source"
                for path in "${SOURCES[@]}"; do
                    source="$(norm_nosym "$path")"
                    target="$(norm_nosym "$TARGET_PREFIX/${path#"$SOURCE_PREFIX/"}")"

                    BACKUP_REPO_SUFFIX="$(dirname "${source#"$SCRIPT_DIR/"}")"
                    BACKUP_HOME_SUFFIX="$(dirname "${target#"$HOME/"}")"

                    copyFile "$source" "$target"
                done
                IS_EXCLUDED=0
                SOURCES=()
                reset_status
            else
                copyFile "$source" "$target"
                reset_status
            fi
            ;;
        exclude)
            excludeFile "$source" "$target"
            reset_status
            ;;
        *)
            printf "${ERROR} Unknown operation %s. Skipping..." "$operation"
            ;;
        esac

    done <"$MANIFEST"
}

log_info() {
    echo "[AppName]          : $APP_NAME"
    echo "[Source prefix]    : $SOURCE_PREFIX"
    echo "[Source]           : $SOURCE"
    echo "[Target prefix]    : $TARGET_PREFIX"
    echo "[Target]           : $TARGET"
    echo "[Operation]        : $OPERATION"
    printf '\n'

    reset_status
}

help() {
    echo "Usage: $0 [options]"
    echo "This script syncs files or directories from your local $HOME to the repository (copy)"
    echo "  -f : force overwrite target files"
    echo "  -m : specify a manifest file"
    echo "  -o : specify default operation(copy/symlink), it will ignore the operation field for all entries in the MANIFEST file."
    echo "  -h : display available options"
    echo "  -d : enable debug"
}

optstrings=":fhd :m:o:"
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
    d)
        is_debug_mode=1
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
