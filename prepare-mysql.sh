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

log_file="prepare-progress.log"

sanity_check () {
    # Check user running the script
    # check_user

    if [ "${number_of_args}" -lt 1 ]; then
        error "Script requires restore directory as an argument."
    fi

    shopt -s nullglob
    incremental_dirs=( $1/incremental-*/ )
    full_dirs=( $1/full-*/ )
    shopt -u nullglob

    # Check whether a single full backup directory are available
    if (( ${#full_dirs[@]} != 1 )); then
        error "Exactly one full backup directory is required."
    fi

    full_backup_dir="${full_dirs[0]}"
}

do_prepare () {
    # Apply the logs to each of the backups
    printf "Initial prep of full backup %s\n" "${full_backup_dir}"
    mariabackup --prepare --target-dir="${full_backup_dir}"
    
    for increment in "${incremental_dirs[@]}"; do
        printf "Applying incremental backup %s to %s\n" "${increment}" "${full_backup_dir}"
        mariabackup --prepare --incremental-dir="${increment}" --target-dir="${full_backup_dir}"
    done
    
}

main () {
    sanity_check $@ && do_prepare > "${log_file}" 2>&1

    # Check the number of reported completions.  Each time a backup is processed,
    # an informational "completed OK" and a real version is printed.  At the end of
    # the process, a final full apply is performed, generating another 2 messages.
    ok_count="$(grep -c 'completed OK' "${log_file}")"

    if (( ${ok_count} == ${#full_dirs[@]} + ${#incremental_dirs[@]} )); then
        cat << EOF
    Backup looks to be fully prepared.  Please check the "prepare-progress.log" file
    to verify before continuing.

    If everything looks correct, you can apply the restored files.

    First, stop MySQL and move or remove the contents of the MySQL data directory:
        
            sudo systemctl stop mariadb
            sudo mv /var/lib/mysql/ /tmp/
        
    Then, recreate the data directory and  copy the backup files:
        
            sudo mkdir /var/lib/mysql
            sudo mariabackup --copy-back --target-dir=${1}/$(basename "${full_backup_dir}")
        
    Afterward the files are copied, adjust the permissions and restart the service:
        
            sudo chown -R mysql:mysql /var/lib/mysql
            sudo find /var/lib/mysql -type d -exec chmod 755 {} \;
            sudo systemctl start mariadb
EOF
    else
        error "It looks like something went wrong.  Check the \"${log_file}\" file for more information."
    fi
}

main $@