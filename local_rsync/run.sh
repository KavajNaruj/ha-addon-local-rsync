#!/usr/bin/with-contenv bashio

set -euo pipefail

SOURCE="$(bashio::config 'source')"
DESTINATION="$(bashio::config 'destination')"
RUN_MODE="$(bashio::config 'run_mode')"
SCHEDULE_MINUTES="$(bashio::config 'schedule_minutes')"
ARGS="$(bashio::config 'args')"

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

    if [[ "$original" == */ ]]; then
        printf '%s/\n' "${resolved%/}"
        return
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

    if [[ -n "$ARGS" ]]; then
        # User-provided rsync flags are split as shell words.
        read -r -a EXTRA_WORDS <<< "$ARGS"
        RSYNC_ARGS+=("${EXTRA_WORDS[@]}")
    fi
}

log_rsync_command() {
    declare -a command
    local quoted

    command=("rsync" "${RSYNC_ARGS[@]}" "$1" "$2")
    printf -v quoted '%q ' "${command[@]}"
    bashio::log.info "Command: ${quoted% }"
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
    log_rsync_command "$source_path" "$destination_path"

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
