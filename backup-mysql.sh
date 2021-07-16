#!/bin/bash

export LC_ALL=C

days_of_backups=3
backup_owner="backup"
parent_dir="/var/backup/mysql"
defaults_file="/var/backup/.my.cnf"
todays_dir="${parent_dir}/$(date +%Y-%m-%d)"
log_file="${todays_dir}/backup-progress.log"
encryption_key_file="${parent_dir}/encryption_key"
use_compression=1
now="$(date +%m-%d-%Y_%H-%M-%S)"
processors="$(nproc --all)"
space_treshold_kb=52428800

# Use this to echo to standard error
error () {
    printf "%s: %s\n" "$(basename "${BASH_SOURCE}")" "${1}" >&2
    exit 1
}

trap 'error "An unexpected error occurred."' ERR

sanity_check () {
    # Check user running the script
    if [ "$(id --user --name)" != "$backup_owner" ]; then
        error "Script can only be run as the \"$backup_owner\" user"
    fi

    if [ -f "${todays_dir}/.lock" ]; then
        error "Another process working"
    fi

    if [ `df ${parent_dir} | awk '/[0-9]%/{print $(NF-2)}'` -lt ${space_treshold_kb} ]; then
        error "Not enough space";
    fi
}

set_options () {
    # List the mariabackup arguments
    mariabackup_args=(
        "--defaults-file=${defaults_file}"
        "--extra-lsndir=${todays_dir}"
        "--backup"
        "--stream=xbstream"
        "--parallel=${processors}"
    )
    
    backup_type="full"

    # Add option to read LSN (log sequence number) if a full backup has been
    # taken today.
    if grep -q -s "to_lsn" "${todays_dir}/xtrabackup_checkpoints"; then
        backup_type="incremental"
        lsn=$(awk '/to_lsn/ {print $3;}' "${todays_dir}/xtrabackup_checkpoints")
        xtrabackup_args+=( "--incremental-lsn=${lsn}" )
    fi
}

rotate_old () {
    if [ ${days_of_backups} -gt 0 ]; then
        find ${parent_dir} -maxdepth 1 -ctime +${days_of_backups} -type d -exec rm -rf {} \;
    fi
}

take_backup () {
    # Make sure today's backup directory is available and take the actual backup
    mkdir -p "${todays_dir}"
    touch "${todays_dir}/.lock"
    find "${todays_dir}" -type f -name "*.incomplete" -delete

    base_name="${todays_dir}/${backup_type}-${now}.xbstream"
    if [ -r ${encryption_key_file} ] && [ ${use_compression} -gt 0 ]; then
        full_name="${base_name}.gz.enc"
        mariabackup "${mariabackup_args[@]}" "--target-dir=${todays_dir}" 2> "${log_file}" | gzip | openssl enc -aes-256-cbc -kfile ${encryption_key_file} > "${full_name}.incomplete"
    elif [ -r ${encryption_key_file} ]; then
        full_name="${base_name}.enc"
        mariabackup "${mariabackup_args[@]}" "--target-dir=${todays_dir}" 2> "${log_file}" | openssl enc -aes-256-cbc -kfile ${encryption_key_file} > "${full_name}.incomplete"
    elif [ ${use_compression} -gt 0 ]; then
        full_name="${base_name}.gz"
        mariabackup "${mariabackup_args[@]}" "--target-dir=${todays_dir}" 2> "${log_file}" | gzip > "${full_name}.incomplete"
    else
        full_name="${base_name}"
        mariabackup "${mariabackup_args[@]}" "--target-dir=${todays_dir}" 2> "${log_file}" > "${full_name}.incomplete"
    fi
    
    mv "${full_name}.incomplete" "${full_name}"

    rm "${todays_dir}/.lock"
}

main () {
    cd && sanity_check && set_options && rotate_old && take_backup

    # Check success and print message
    if tail -1 "${log_file}" | grep -q "completed OK"; then
        printf "Backup successful!\n"
        printf "Backup created at %s\n" "${full_name}"
    else
        error "Backup failure! Check ${log_file} for more information"
    fi
}

main
