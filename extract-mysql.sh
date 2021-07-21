#!/bin/bash

export LC_ALL=C

source "$(dirname "$0")/config.inc"
source "$(dirname "$0")/common.inc"

log_file="extract-progress.log"

sanity_check () {
    # Check user running the script
    # check_user
    
    # Check whether any arguments were passed
    if [ "${number_of_args}" -lt 1 ]; then
        error "Script requires at least one \".xbstream\" file as an argument."
    fi
}

set_options () {
    mbstream_args=(
        "--verbose"
        "--parallel=${processors}"
    )

    openssl_args=(
        "-aes-256-cbc"
        "-kfile"
        "${encryption_key_file}"
    )
}

do_extraction () {
    for file in "${@}"; do
        base_filename="$(basename "${file%.xbstream%}")"
        restore_dir="./restore/${base_filename}"
    
        printf "\n\nExtracting file %s\n\n" "${file}"
    
        # Extract the directory structure from the backup file
        mkdir --verbose -p "${restore_dir}"

        if [ -r ${encryption_key_file} ] && [ ! -z ${compression_tool} ]; then
            openssl enc -d "${openssl_args[@]}" -in "${file}" | "${compression_tool}" -d | mbstream "${mbstream_args[@]}" -x -C "${restore_dir}"
        elif [ -r ${encryption_key_file} ]; then
            openssl enc -d "${openssl_args[@]}" -in "${file}" | mbstream "${mbstream_args[@]}" -x -C "${restore_dir}"
        elif [ ! -z ${compression_tool} ]; then
            "${compression_tool}" -dc "${file}" | mbstream "${mbstream_args[@]}" -x -C "${restore_dir}"
        else
            mbstream "${mbstream_args[@]}" -x -C "${restore_dir}"
        fi
    
        printf "\n\nFinished work on %s\n\n" "${file}"
    
    done > "${log_file}" 2>&1
}

main () {
    set_options && sanity_check && do_extraction "$@"

    ok_count="$(grep -c 'xtrabackup_info' "${log_file}")"

    if (( $ok_count != $# )); then
        error "It looks like something went wrong. Please check the \"${log_file}\" file for additional information"
    else
        printf "Extraction complete! Backup directories have been extracted to the \"restore\" directory.\n"
    fi
}

main $@
