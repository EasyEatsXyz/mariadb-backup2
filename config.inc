#!/bin/bash

days_of_backups=3
backup_owner="backup"
parent_dir="/var/backup/mysql"
defaults_file="/var/backup/.my.cnf"
compression_tool="pigz"
space_treshold_kb=5242880

todays_dir="${parent_dir}/$(date +%Y-%m-%d)"
encryption_key_file="${parent_dir}/encryption_key"
number_of_args="${#}"
now="$(date +%m-%d-%Y_%H-%M-%S)"
processors="$(nproc --all)"
current_user="$(id -un)"
