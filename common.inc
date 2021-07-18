#!/bin/bash

# Use this to echo to standard error
error () {
    rm -f "${todays_dir}/.lock"
    printf "%s: %s\n" "$(basename "${0}")" "${1}" >&2
    exit 1
}

trap 'error "An unexpected error occurred. Try checking the \"${log_file}\" file for more information."' ERR

check_user () {
    if [ "${current_user}" != "$backup_owner" ]; then
        error "Script can only be run as the \"$backup_owner\" user"
    fi
}