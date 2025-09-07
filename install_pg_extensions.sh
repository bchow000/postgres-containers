#!/bin/bash
set -euxo pipefail
PG_MAJOR=17.6
# calling syntax: install_pg_extensions.sh [extension1] [extension2] ...

function install_vchord() {
    # Install JQ
    apt-get install -y jq curl
    
    # Get the actual latest release tag (follow redirect)
    latest_tag=$(curl -sL -o /dev/null -w '%{url_effective}' \
        https://github.com/tensorchord/VectorChord/releases/latest | awk -F/ '{print $NF}')
    
    name_regex=".*${PG_MAJOR}.*${latest_tag}.*$(dpkg --print-architecture).*.deb"
   
    deb_url=$(curl -s "https://api.github.com/repos/tensorchord/VectorChord/releases/tags/${latest_tag}" \
        | tr -d '\000-\037' \
        | jq -r '.assets[].browser_download_url' \
        | grep -E "${name_regex}")
    
    file_name=$(echo "${deb_url}" | awk -F/ '{print $NF}')

    curl -LJO --output-dir "/tmp/" "${deb_url}"

    apt-get install -y "/tmp/${file_name}"
    
    # cleanup
    apt-get remove curl jq -y
}

check_existing_vchord_install() {
    # Locate the first relevant PostgreSQL config file
    conf_file=$(find /etc/postgresql/ -type f \( -name "postgresql.conf" -o -name "postgresql.auto.conf" \) 2>/dev/null | head -n 1)
    [[ -z "$conf_file" ]] && echo "No PostgreSQL config file found, creating" && \
        mkdir -p "/etc/postgresql/${PG_MAJOR}/main" && \
        touch "/etc/postgresql/${PG_MAJOR}/main/postgresql.auto.conf" && \
        conf_file="/etc/postgresql/${PG_MAJOR}/main/postgresql.auto.conf"

    # Extract current shared_preload_libraries value, if present
    existing=$(grep -E '^\s*shared_preload_libraries\s*=' "$conf_file" | sed -E "s/.*=\s*'([^']*)'.*/\1/") 

    # If vchord.so is already listed, exit
    if [[ "$existing" == *vchord.so* ]]; then
        echo "vchord.so is already in shared_preload_libraries"
        return 0
    fi

    # Construct new value with vchord.so added
    [[ -z "$existing" ]] && combined="vchord.so" || combined="${existing},vchord.so"

    # Update or insert the setting
    if grep -qE '^\s*shared_preload_libraries\s*=' "$conf_file"; then
        sed -i -E "s|^\s*shared_preload_libraries\s*=.*|shared_preload_libraries = '$combined'|" "$conf_file"
    else
        echo "shared_preload_libraries = '$combined'" >> "$conf_file"
    fi

    echo "Updated shared_preload_libraries to: $combined"
}

function install_timescaledb() {
    # dependencies
    apt-get install apt-transport-https lsb-release wget -y
    
    # repository
    echo "deb https://packagecloud.io/timescale/timescaledb/debian/" \
        "$(lsb_release -c -s) main" \
        > /etc/apt/sources.list.d/timescaledb.list
    
    # key
    wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey \
        | gpg --dearmor > /etc/apt/trusted.gpg.d/timescaledb.gpg
         
    apt-get update
    apt-get install --yes \
        timescaledb-tools \
        "timescaledb-toolkit-postgresql-${PG_MAJOR}" \
        "timescaledb-2-loader-postgresql-${PG_MAJOR}" \
        "timescaledb-2-${TIMESCALEDB_VERSION}-postgresql-${PG_MAJOR}"
    
    # cleanup
    apt-get remove apt-transport-https lsb-release wget --auto-remove -y
}
# install extensions
EXTENSIONS="$@"
# cycle through extensions list
for EXTENSION in ${EXTENSIONS}; do    
    # special case: timescaledb
    if [ "$EXTENSION" == "timescaledb" ]; then
        install_timescaledb
        continue
    fi

    if [ "$EXTENSION" == "vchord" ]; then
        install_vchord
        # check_existing_vchord_install
        continue
    fi

    # is it an extension found in apt?
    if apt-cache show "postgresql-${PG_MAJOR}-${EXTENSION}" &> /dev/null; then
        # install the extension
        apt-get install -y "postgresql-${PG_MAJOR}-${EXTENSION}"
       continue
    fi

    # extension not found/supported
    echo "Extension '${EXTENSION}' not found/supported"
    exit 1
done



