#!/usr/bin/env bash

# shellcheck disable=SC2034
# shellcheck disable=SC2155
# shellcheck disable=SC2001

set -e

SCRIPT_DIR=$(dirname "$(realpath "$0")")
MANIFEST="${SCRIPT_DIR}/MANIFEST.linux"

SOURCE_ROOT="$HOME"
TARGET_ROOT="$SCRIPT_DIR"
BACKUP_HOME_DIR="${SCRIPT_DIR}/__backup__/home_backup/$(date +%y-%m-%d-%H%M%S)"
BACKUP_REPO_DIR="${SCRIPT_DIR}/__backup__/repo_backup/$(date +%y-%m-%d-%H%M%S)"

if ! source "${SCRIPT_DIR}/scripts/global_fn.sh"; then
    echo "Error: unable to source scripts/global_fn.sh..."
    exit 1
fi

ALL=()
INCLUDES=()
EXCLUDES=()

APP_NAME=""
SOURCE_PREFIX="$SOURCE_ROOT"
TARGET_PREFIX="$TARGET_ROOT"
OPERATION=""

LAST_APP_NAME=""

is_help_mode=0
is_debug_mode=0

reset_status() {
    APP_NAME=""
    SOURCE_PREFIX="$SOURCE_ROOT"
    TARGET_PREFIX="$TARGET_ROOT"
    OPERATION=""
}

getAllPaths() {
    local root_dir
    root_dir="$(norm_nosym "$1")"
    while IFS= read -r -d '' path; do
        if [ ! -d "$path" ]; then
            ALL+=("$(norm_nosym "$path")")
        fi
    done < <(find "$root_dir" -mindepth 1 -print0)
}

is_excluded() {
    local target
    target="$(norm_nosym "$1")"

    for i in "${!EXCLUDES[@]}"; do
        EXCLUDES[i]="$(norm_nosym "${EXCLUDES[$i]}")"
    done

    for ex in "${EXCLUDES[@]}"; do
        # Match the excluded directory itself or any of its subitems.
        if [[ "$target" == "$ex" || "$target" == "$ex/"* ]]; then
            return 0
        fi
    done
    return 1
}

getIncludePaths() {
    getAllPaths "$1"
    for path in "${ALL[@]}"; do
        if ! is_excluded "$path"; then
            INCLUDES+=("$path")
        fi
    done

    # reset
    ALL=()
}

copyFile() {
    local source="$1"
    local target="$2"
    local target_dir="$(dirname "$target")"
    local backup_dir="$BACKUP_REPO_DIR/$3"

    # Ensure the source file exists
    if [ ! -e "$source" ]; then
        printf "${ERROR} ${YELLOW}%s${RESET} does not exist - please check your MANIFEST file.\n" "$source"
        exit 1
    fi

    # If the source file already exists in your home directory,
    # but it is a symbolic link, just skiping it.
    if [ -L "$source" ]; then
        printf "${WARN} ${YELLOW}%s${RESET} already symlinked and doesn't need to sync it. skiping...\n" "$source"

        reset_status
        return
    fi

    # If the source file already exists in your home directory,
    # and it is a regular file or directory.
    if [ -f "$source" ]; then
        # If the target file or directory does not exist, or has not been modified,
        # it does not need to be backed up.
        if is_diff_mtime "$source" "$target"; then
            mkdir -p "$backup_dir"
            mv "$target" -t "$backup_dir"
            printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}.\n" "$target" "$backup_dir"
        fi
    fi

    # If the target directory does not exists, create the target directory.
    mkdir -p "$target_dir"

    # If the target file does not exist, or has been modified,
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
    local source_dir="$(dirname "$source")"
    local backup_dir="$BACKUP_REPO_DIR/$3"

    # If the source file does not exist, return immediately.
    if [ ! -e "$source" ]; then
        printf "${WARN} ${YELLOW}%s${RESET} does not exist but excluded - skipping.\n" "$source"

        reset_status
        return
    fi

    # If the file to be excluded already exist in your $HOME directory and is a symbolic link,
    # remove this symlink directly and move the excluded file back to your $HOME directory.
    if [ -L "$source" ]; then
        unlink "$source"
        mv "$target" -t "$source_dir"

        reset_status
        return
    fi

    # If the file to be excluded already exist in the repository,
    # move them to the backup directory and prompt the user to update the corresponding MANIFEST file
    # by moving the exclude entries before the related entries so this does not happen on the next sync.
    if [ -f "$target" ]; then
        # Backup target files
        mkdir -p "$backup_dir"
        mv "$target" -t "$backup_dir"

        # NOTE: You should list entries to be excluded before the related entries.
        printf "${WARN} Original ${YELLOW}%s${RESET} has been moved to ${YELLOW}%s${RESET}. \n" "$target" "$backup_dir"
    fi

    EXCLUDES+=("${source}")
    printf "${WARN} ${YELLOW}%s${RESET} has been excluded.\n" "$source"
}

syncRepoAndHome() {
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
        IFS='|' read -r appname target_suffix file_or_dir \
            operation source_suffix <<<"$(sed 's/ *| */|/g' <<<"$row")"

        # Global infos
        APP_NAME="$appname"
        [[ ! -z "$source_suffix" ]] && SOURCE_PREFIX+="/$source_suffix"
        [[ ! -z "$target_suffix" ]] && TARGET_PREFIX+="/$target_suffix"

        # $HOME -> $REPO
        source="$(norm_nosym "$SOURCE_PREFIX/$file_or_dir")"
        target="$(norm_nosym "$TARGET_PREFIX/$file_or_dir")"
        #backup_home_suffix="$(dirname "${source#"$SOURCE_ROOT/"}")"
        backup_repo_suffix="$(dirname "${target#"$TARGET_ROOT/"}")"

        # This condition is generally always true, except if an exclude operation has been performed
        # and the entries with the same APP_NAME have not all completed; in that case the EXCLUDES array state
        # will be preserved.
        if [[ "$APP_NAME" -ne "$LAST_APP_NAME" ]]; then
            EXCLUDES=()
        fi

        # DEBUG: INFO
        if [[ $is_debug_mode -ne 0 ]]; then
            SOURCE="$source"
            TARGET="$target"
            OPERATION="$operation"

            log_info
            continue
        fi

        # Begin performing the concrete operations.
        # If the target is a directory, it will be split into multiple individual files.
        if [[ $operation == "exclude" ]]; then
            if [[ -d "$source" ]]; then
                # This will deduplicate the EXCLUDES array.
                getIncludePaths "$source"
                for path in "${INCLUDES[@]}"; do
                    source="$(norm_nosym "$path")"
                    target="$(norm_nosym "$TARGET_PREFIX/${path#"$SOURCE_PREFIX/"}")"
                    #backup_home_suffix="$(dirname "${source#"$SOURCE_ROOT/"}")"
                    backup_repo_suffix="$(dirname "${target#"$TARGET_ROOT/"}")"

                    excludeFile "$source" "$target" "$backup_repo_suffix"
                done
            else # [[ -f "$source" ]]
                excludeFile "$source" "$target" "$backup_repo_suffix"
            fi
            # If there are subsequent entries with the same APP_NAME,
            # this will be used to preserve the EXCLUDES array state.
            LAST_APP_NAME="$APP_NAME"
        elif [[ $operation == "copy" || $operation == "symlink" ]]; then
            if [[ -d "$source" ]]; then
                getIncludePaths "$source"
                for path in "${INCLUDES[@]}"; do
                    source="$(norm_nosym "$path")"
                    target="$(norm_nosym "$TARGET_PREFIX/${path#"$SOURCE_PREFIX/"}")"
                    #backup_home_suffix="$(dirname "${source#"$SOURCE_ROOT/"}")"
                    backup_repo_suffix="$(dirname "${target#"$TARGET_ROOT/"}")"

                    copyFile "$source" "$target" "$backup_repo_suffix"
                done
            else # [[ -f "$source" ]]
                copyFile "$source" "$target" "$backup_repo_suffix"
            fi
        else
            printf "${ERROR} Unknown operation %s. Skipping..." "$operation"
            exit 1
        fi
        # Reset status
        INCLUDES=()
        reset_status
    done <"$MANIFEST"
}

log_info() {
    echo "[AppName]   : $APP_NAME"
    echo "[Source]    : $SOURCE"
    echo "[Target]    : $TARGET"
    echo "[Operation] : $OPERATION"
    printf '\n'

    reset_status
}

help() {
    echo "Usage: $0 [options]"
    echo "This script syncs files or directories from your local $HOME to the repository (copy)"
    echo "  -m : specify a manifest file"
    echo "  -h : display available options"
}

optstrings=":hd :m:"
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
    d)
        is_debug_mode=1
        ;;
    *)
        echo "Invalid option: -${OPTARG}."
        ;;
    esac
done

if [ $is_help_mode -eq 0 ]; then
    syncRepoAndHome
fi
