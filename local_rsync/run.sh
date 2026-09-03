#!/usr/bin/with-contenv bashio

set -euo pipefail

CONFIG_PATH=/data/options.json
STATUS_PATH=/data/last_run.json
STATE_ENTITY_ID=sensor.local_rsync_last_run
RUN_MODE="$(jq -r '.run_mode // "once"' "$CONFIG_PATH")"
SCHEDULE_MINUTES="$(jq -r '.schedule_minutes // 60' "$CONFIG_PATH")"
STARTED_AT=""
FINISHED_AT=""
LAST_STATUS="idle"
LAST_SUMMARY=""
LAST_RETURN_CODE=0
LAST_FAILED_JOB_INDEX=""
JOBS_TOTAL=0
JOBS_COMPLETED=0
LAST_COMMAND=""

resolve_path() {
    realpath -m "$1"
}

iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

status_icon() {
    case "$1" in
        running) printf "mdi:sync" ;;
        success) printf "mdi:check-circle" ;;
        error) printf "mdi:alert-circle" ;;
        *) printf "mdi:clock-outline" ;;
    esac
}

write_status_file() {
    local status="$1"
    local summary="$2"
    local return_code="$3"
    local failed_job_index="$4"
    local output

    output="$(
        jq -n \
            --arg status "$status" \
            --arg summary "$summary" \
            --arg started_at "$STARTED_AT" \
            --arg finished_at "$FINISHED_AT" \
            --arg run_mode "$RUN_MODE" \
            --arg last_command "$LAST_COMMAND" \
            --argjson return_code "$return_code" \
            --argjson jobs_total "$JOBS_TOTAL" \
            --argjson jobs_completed "$JOBS_COMPLETED" \
            --arg failed_job_index "$failed_job_index" \
            '
            {
              status: $status,
              summary: $summary,
              started_at: $started_at,
              finished_at: $finished_at,
              run_mode: $run_mode,
              return_code: $return_code,
              jobs_total: $jobs_total,
              jobs_completed: $jobs_completed,
              last_command: $last_command
            }
            + (if $failed_job_index == "" then {} else {failed_job_index: ($failed_job_index | tonumber)} end)
            '
    )"

    printf '%s\n' "$output" > "$STATUS_PATH"
}

publish_state() {
    local status="$1"
    local summary="$2"
    local return_code="$3"
    local failed_job_index="$4"
    local payload

    payload="$(
        jq -n \
            --arg state "$status" \
            --arg friendly_name "Local Rsync Last Run" \
            --arg icon "$(status_icon "$status")" \
            --arg summary "$summary" \
            --arg started_at "$STARTED_AT" \
            --arg finished_at "$FINISHED_AT" \
            --arg run_mode "$RUN_MODE" \
            --arg last_command "$LAST_COMMAND" \
            --argjson return_code "$return_code" \
            --argjson jobs_total "$JOBS_TOTAL" \
            --argjson jobs_completed "$JOBS_COMPLETED" \
            --arg failed_job_index "$failed_job_index" \
            '
            {
              state: $state,
              attributes: {
                friendly_name: $friendly_name,
                icon: $icon,
                summary: $summary,
                started_at: $started_at,
                finished_at: $finished_at,
                run_mode: $run_mode,
                return_code: $return_code,
                jobs_total: $jobs_total,
                jobs_completed: $jobs_completed,
                last_command: $last_command
              }
            }
            | if $failed_job_index == "" then . else .attributes.failed_job_index = ($failed_job_index | tonumber) end
            '
    )"

    curl -sS \
        -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "http://supervisor/core/api/states/${STATE_ENTITY_ID}" \
        >/dev/null || bashio::log.warning "Failed to publish Home Assistant state"
}

record_status() {
    local status="$1"
    local summary="$2"
    local return_code="$3"
    local failed_job_index="${4:-}"

    LAST_STATUS="$status"
    LAST_SUMMARY="$summary"
    LAST_RETURN_CODE="$return_code"
    LAST_FAILED_JOB_INDEX="$failed_job_index"

    write_status_file "$status" "$summary" "$return_code" "$failed_job_index"
    publish_state "$status" "$summary" "$return_code" "$failed_job_index"
}

handle_exit() {
    local exit_code="$1"

    if [[ -z "$STARTED_AT" ]]; then
        exit "$exit_code"
    fi

    FINISHED_AT="$(iso_timestamp)"

    if (( exit_code == 0 )); then
        if [[ "$RUN_MODE" == "interval" ]]; then
            record_status "success" "Sync cycle finished successfully" 0
        elif [[ "$LAST_STATUS" == "running" ]]; then
            record_status "success" "All rsync jobs finished successfully" 0
        fi
        exit 0
    fi

    if [[ "$LAST_STATUS" == "running" ]]; then
        record_status "error" "Addon exited with an error" "$exit_code" "$LAST_FAILED_JOB_INDEX"
    fi

    exit "$exit_code"
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

    JOBS_TOTAL="$jobs_count"
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
    LAST_COMMAND="${quoted% }"
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

    if rsync "${RSYNC_ARGS[@]}" "$source_path" "$destination_path"; then
        :
    else
        local exit_code=$?
        FINISHED_AT="$(iso_timestamp)"
        LAST_FAILED_JOB_INDEX="$job_index"
        record_status "error" "Rsync job $job_index failed" "$exit_code" "$job_index"
        exit "$exit_code"
    fi

    JOBS_COMPLETED=$((JOBS_COMPLETED + 1))
    bashio::log.info "Rsync job $job_index finished successfully"
}

run_all_sync_jobs() {
    local job_count job_index

    job_count="$(jq -r '.jobs | length' "$CONFIG_PATH")"

    for ((job_index = 0; job_index < job_count; job_index++)); do
        run_sync_job "$job_index"
    done
}

trap 'handle_exit $?' EXIT
STARTED_AT="$(iso_timestamp)"
record_status "running" "Local Rsync addon started" 0
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
    STARTED_AT="$(iso_timestamp)"
    FINISHED_AT=""
    JOBS_COMPLETED=0
    LAST_FAILED_JOB_INDEX=""
    LAST_COMMAND=""
    record_status "running" "Sync cycle started" 0
    run_all_sync_jobs
    FINISHED_AT="$(iso_timestamp)"
    record_status "success" "Sync cycle finished successfully" 0
    bashio::log.info "Sleeping for ${SCHEDULE_MINUTES} minute(s)"
    sleep "$((SCHEDULE_MINUTES * 60))"
done
