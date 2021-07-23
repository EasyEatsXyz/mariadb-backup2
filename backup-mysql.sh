#!/bin/bash

export LC_ALL=C

if [ -r "$(dirname "$0")/config.inc" ]; then
    source "$(dirname "$0")/config.inc"
elif [ -r "/var/lib/backup-mysql/config.inc" ]; then
    source "/var/lib/backup-mysql/config.inc"
else
    error "Can not find config.inc"
fi

if [ -r "$(dirname "$0")/common.inc" ]; then
    source "$(dirname "$0")/common.inc"
elif [ -r "/etc/backup-mysql/common.inc" ]; then
    source "/etc/backup-mysql/common.inc"
else
    error "Can not find common.inc"
fi

log_file="${todays_dir}/backup-progress.log"

parse_args () {
    for i in "$@"
    do
        case $i in
            -f|--force)
            force=1
            ;;
            *)
                # unknown option
                # echo $i
            ;;
        esac
    done
}

sanity_check () {
    # Check user running the script
    check_user

    if [ ! ${force} ] && [ -f "${todays_dir}/.lock" ]; then
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

    if [ $(mysql --defaults-file=${defaults_file} -e "SHOW SLAVE STATUS\G" | wc -l) -ne 0 ]; then
        mariabackup_args+=( "--slave-info" )
    fi

    openssl_args=(
        "-aes-256-cbc"
        "-kfile"
        "${encryption_key_file}"
    )
    
    backup_type="full"

    # Add option to read LSN (log sequence number) if a full backup has been
    # taken today.
    if grep -q -s "to_lsn" "${todays_dir}/xtrabackup_checkpoints"; then
        backup_type="incremental"
        lsn=$(awk '/to_lsn/ {print $3;}' "${todays_dir}/xtrabackup_checkpoints")
        mariabackup_args+=( "--incremental-lsn=${lsn}" )
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
    if [ -r ${encryption_key_file} ] && [ ! -z ${compression_tool} ]; then
        full_name="${base_name}.gz.enc"
        mariabackup "${mariabackup_args[@]}" "--target-dir=${todays_dir}" 2> "${log_file}" | "${compression_tool}" | openssl enc "${openssl_args[@]}" > "${full_name}.incomplete"
    elif [ -r ${encryption_key_file} ]; then
        full_name="${base_name}.enc"
        mariabackup "${mariabackup_args[@]}" "--target-dir=${todays_dir}" 2> "${log_file}" | openssl enc "${openssl_args[@]}" > "${full_name}.incomplete"
    elif [ ! -z ${compression_tool} ]; then
        full_name="${base_name}.gz"
        mariabackup "${mariabackup_args[@]}" "--target-dir=${todays_dir}" 2> "${log_file}" | "${compression_tool}" > "${full_name}.incomplete"
    else
        full_name="${base_name}"
        mariabackup "${mariabackup_args[@]}" "--target-dir=${todays_dir}" 2> "${log_file}" > "${full_name}.incomplete"
    fi && mv "${full_name}.incomplete" "${full_name}"

    rm "${todays_dir}/.lock"
}

main () {
    cd && parse_args $@ && sanity_check && set_options && rotate_old && take_backup

    # Check success and print message
    if tail -1 "${log_file}" | grep -q "completed OK"; then
        printf "Backup successful!\n"
        printf "Backup created at %s\n" "${full_name}"
    else
        error "Backup failure! Check ${log_file} for more information"
    fi
}

main $@
