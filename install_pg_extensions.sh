#!/bin/bash
set -euxo pipefail

# calling syntax: install_pg_extensions.sh [extension1] [extension2] ...

# Install postgresql contrib
apt-get install -y pgxnclient r-cran-pkgmaker
# install extensions
EXTENSIONS="$@"
# cycle through extensions list
for EXTENSION in ${EXTENSIONS}; do    
    # special case: timescaledb
    if [ "$EXTENSION" == "timescaledb" ]; then
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
            timescaledb-toolkit-postgresql-${PG_MAJOR} \
            timescaledb-2-loader-postgresql-${PG_MAJOR} \
            timescaledb-2-${TIMESCALEDB_VERSION}-postgresql-${PG_MAJOR}

        # cleanup
        apt-get remove apt-transport-https lsb-release wget --auto-remove -y

        continue
    fi

    if [ "$EXTENSION" == "vchord" ]; then
        # Install JQ
        apt install -y jq
        # Get the actual latest release tag (follow redirect)
        latest_tag=$(curl -sL -o /dev/null -w '%{url_effective}' https://github.com/tensorchord/VectorChord/releases/latest | awk -F/ '{print $NF}')

        # List all assets for that release
        assets_json=$(curl -s https://api.github.com/repos/tensorchord/VectorChord/releases/tags/$latest_tag)

        # Extract the .deb URL for PostgreSQL 17 and x86_64
        # deb_url=$(echo "$assets_json" | jq -r '.assets[] | select(.name | test("vchord-pg${PG_MAJOR}_.*_amd64.deb")) | .browser_download_url')
        deb_url=$(echo "$assets_json" | jq -r \
          --arg pg_major "$PG_MAJOR" \
          '.assets[] | select(.name | test("vchord-pg" + $pg_major + "_.*_amd64.deb")) | .browser_download_url')

        apt install ${deb_url}
        
        existing=$(sudo -u postgres psql -Atc "SHOW shared_preload_libraries;")
        if [[ "$existing" != *vchord.so* ]]; then
            combined=$(echo "$existing" | sed 's/^$//' | awk -v add="vchord.so" '{ if ($0 == "") print add; else print $0","add }')
            sudo -u postgres psql -c "ALTER SYSTEM SET shared_preload_libraries = '$combined';"
        fi
        continue
    fi

    # is it an extension found in apt?
    if apt-cache show "postgresql-${PG_MAJOR}-${EXTENSION}" &> /dev/null; then
        install the extension
        apt-get install -y "postgresql-${PG_MAJOR}-${EXTENSION}"
       continue
    fi

    # extension not found/supported
    echo "Extension '${EXTENSION}' not found/supported"
    exit 1
done
