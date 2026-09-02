#!/usr/bin/with-contenv bashio

set -euo pipefail

CONFIG_PATH=/data/options.json
RUN_MODE="$(jq -r '.run_mode // "once"' "$CONFIG_PATH")"
SCHEDULE_MINUTES="$(jq -r '.schedule_minutes // 60' "$CONFIG_PATH")"

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

validate_jobs() {
    local jobs_type jobs_count

    jobs_type="$(jq -r 'if (.jobs | type) == "array" then "array" else (.jobs | type) end' "$CONFIG_PATH")"
    if [[ "$jobs_type" != "array" ]]; then
        bashio::log.fatal "jobs must be an array"
        exit 1
    fi

    jobs_count="$(jq -r '.jobs | length' "$CONFIG_PATH")"
    if (( jobs_count < 1 )); then
        bashio::log.fatal "jobs must contain at least one item"
        exit 1
    fi
}

build_rsync_args() {
    local args="$1"

    declare -ga RSYNC_ARGS
    RSYNC_ARGS=()

    if [[ -n "$args" ]]; then
        # User-provided rsync flags are split as shell words.
        read -r -a EXTRA_WORDS <<< "$args"
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

run_sync_job() {
    local job_index="$1"
    local source destination args source_path destination_path

    source="$(jq -r ".jobs[$job_index].source // empty" "$CONFIG_PATH")"
    destination="$(jq -r ".jobs[$job_index].destination // empty" "$CONFIG_PATH")"
    args="$(jq -r ".jobs[$job_index].args // empty" "$CONFIG_PATH")"

    if [[ -z "$source" ]]; then
        bashio::log.fatal "jobs[$job_index].source is required"
        exit 1
    fi

    if [[ -z "$destination" ]]; then
        bashio::log.fatal "jobs[$job_index].destination is required"
        exit 1
    fi

    source_path="$(ensure_local_media_path "$source")"
    destination_path="$(ensure_local_media_path "$destination")"

    if [[ ! -e "$source_path" ]]; then
        bashio::log.fatal "Source path does not exist: $source_path"
        exit 1
    fi

    mkdir -p "$destination_path"
    build_rsync_args "$args"

    bashio::log.info "Starting local rsync job $job_index"
    bashio::log.info "Source: $source_path"
    bashio::log.info "Destination: $destination_path"
    bashio::log.info "Flags: ${RSYNC_ARGS[*]:-(none)}"
    log_rsync_command "$source_path" "$destination_path"

    rsync "${RSYNC_ARGS[@]}" "$source_path" "$destination_path"

    bashio::log.info "Rsync job $job_index finished successfully"
}

run_all_sync_jobs() {
    local job_count job_index

    job_count="$(jq -r '.jobs | length' "$CONFIG_PATH")"

    for ((job_index = 0; job_index < job_count; job_index++)); do
        run_sync_job "$job_index"
    done
}

validate_mode
validate_schedule_minutes
validate_jobs

if [[ "$RUN_MODE" == "once" ]]; then
    bashio::log.info "Run mode: once"
    run_all_sync_jobs
    exit 0
fi

bashio::log.info "Run mode: interval"
bashio::log.info "Sync interval: ${SCHEDULE_MINUTES} minute(s)"

while true; do
    run_all_sync_jobs
    bashio::log.info "Sleeping for ${SCHEDULE_MINUTES} minute(s)"
    sleep "$((SCHEDULE_MINUTES * 60))"
done
