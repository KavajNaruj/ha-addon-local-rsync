#!/usr/bin/with-contenv bashio

set -euo pipefail

SOURCE="$(bashio::config 'source')"
DESTINATION="$(bashio::config 'destination')"
RUN_MODE="$(bashio::config 'run_mode')"
SCHEDULE_MINUTES="$(bashio::config 'schedule_minutes')"
ARCHIVE="$(bashio::config 'archive')"
DELETE_FLAG="$(bashio::config 'delete')"
CHECKSUM="$(bashio::config 'checksum')"
VERBOSE="$(bashio::config 'verbose')"
DRY_RUN="$(bashio::config 'dry_run')"
EXTRA_ARGS="$(bashio::config 'extra_args')"

resolve_path() {
    realpath -m "$1"
}

ensure_local_media_path() {
    local original="$1"
    local resolved

    resolved="$(resolve_path "$original")"

    if [[ "$resolved" != /share/* ]] && [[ "$resolved" != "/share" ]] && [[ "$resolved" != /media/* ]] && [[ "$resolved" != "/media" ]]; then
        bashio::log.fatal "Path '$original' resolves outside /share or /media: $resolved"
        exit 1
    fi

    printf '%s\n' "$resolved"
}

validate_mode() {
    if [[ "$RUN_MODE" != "once" ]] && [[ "$RUN_MODE" != "interval" ]]; then
        bashio::log.fatal "Unsupported run_mode: $RUN_MODE"
        exit 1
    fi
}

validate_schedule_minutes() {
    if ! [[ "$SCHEDULE_MINUTES" =~ ^[0-9]+$ ]] || (( SCHEDULE_MINUTES < 1 )); then
        bashio::log.fatal "schedule_minutes must be a positive integer"
        exit 1
    fi
}

build_rsync_args() {
    declare -ga RSYNC_ARGS
    RSYNC_ARGS=()

    if [[ "$ARCHIVE" == "true" ]]; then
        RSYNC_ARGS+=("-a")
    fi

    if [[ "$DELETE_FLAG" == "true" ]]; then
        RSYNC_ARGS+=("--delete")
    fi

    if [[ "$CHECKSUM" == "true" ]]; then
        RSYNC_ARGS+=("--checksum")
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        RSYNC_ARGS+=("--verbose" "--human-readable" "--itemize-changes")
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        RSYNC_ARGS+=("--dry-run")
    fi

    if [[ -n "$EXTRA_ARGS" ]]; then
        # User-provided extra rsync flags are split as shell words.
        read -r -a EXTRA_WORDS <<< "$EXTRA_ARGS"
        RSYNC_ARGS+=("${EXTRA_WORDS[@]}")
    fi
}

run_sync() {
    local source_path destination_path

    source_path="$(ensure_local_media_path "$SOURCE")"
    destination_path="$(ensure_local_media_path "$DESTINATION")"

    if [[ ! -e "$source_path" ]]; then
        bashio::log.fatal "Source path does not exist: $source_path"
        exit 1
    fi

    mkdir -p "$destination_path"
    build_rsync_args

    bashio::log.info "Starting local rsync"
    bashio::log.info "Source: $source_path"
    bashio::log.info "Destination: $destination_path"
    bashio::log.info "Flags: ${RSYNC_ARGS[*]:-(none)}"

    rsync "${RSYNC_ARGS[@]}" "$source_path" "$destination_path"

    bashio::log.info "Rsync finished successfully"
}

validate_mode
validate_schedule_minutes

if [[ "$RUN_MODE" == "once" ]]; then
    bashio::log.info "Run mode: once"
    run_sync
    exit 0
fi

bashio::log.info "Run mode: interval"
bashio::log.info "Sync interval: ${SCHEDULE_MINUTES} minute(s)"

while true; do
    run_sync
    bashio::log.info "Sleeping for ${SCHEDULE_MINUTES} minute(s)"
    sleep "$((SCHEDULE_MINUTES * 60))"
done
