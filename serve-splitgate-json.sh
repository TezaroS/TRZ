#!/usr/bin/env bash
#
# serve-splitgate-json.sh
#
# Install / configure Nginx to expose *all* files that start with "splitgate"
# and end with ".json" in the directory where this script resides.  
# Those files are zipped (password protected) before being served.
#
# Usage:
#   ./serve-splitgate-json.sh <zip_password>
#
# Example:
#   ./serve-splitgate-json.sh SuperSecret123
#

set -euo pipefail

##########################
#  CONSTANTS & SETTINGS #
##########################

DOMAIN="trztechnoo.xyz"          # domain that points to this server
ZIP_FILENAME="splitgate.zip"     # name of the archive that will be exposed
URL_PATH="/${ZIP_FILENAME}"      # URL path that Nginx will serve

# Where the ZIP will finally live (must be readable by nginx)
BASE_DIR="/usr/share/nginx/${DOMAIN}"
ZIP_PATH="${BASE_DIR}/${ZIP_FILENAME}"

# Default password – if left empty, the script will prompt you
ZIP_PASSWORD="${1:-}"

##########################
#  VALIDATE INPUT        #
##########################

if [[ -z "${ZIP_PASSWORD}" ]]; then
    echo "Password for ZIP not supplied. Please enter one now:"
    read -s "ZIP_PASSWORD"
    export ZIP_PASSWORD   # export so later commands can see it
fi

# Ensure the script's directory exists (it will be $SCRIPT_DIR)
SCRIPT_DIR="$(realpath "$(dirname "$0")")"

##########################
#  INSTALL NGINX         #
##########################

install_nginx() {
    if command -v nginx >/dev/null 2>&1; then
        echo "Nginx is already installed – skipping."
        return
    fi

    echo "Installing Nginx..."

    case "$(uname -s)" in
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y nginx
                USER="www-data"
                GROUP="www-data"
            elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
                # CentOS/RHEL 7/8/9
                sudo yum install -y epel-release && sudo yum install -y nginx
                USER="nginx"
                GROUP="nginx"
            else
                echo "Unsupported package manager. Install Nginx manually."
                exit 1
            fi
            ;;
        *) 
            echo "Unsupported OS ($(uname -s)). Install Nginx manually."
            exit 1
            ;;
    esac

    # Make sure the service is enabled and running
    sudo systemctl enable --now nginx
}

##########################
#  BUILD ZIP             #
##########################

build_zip() {
    echo "Collecting all 'splitgate*.json' files under ${SCRIPT_DIR}..."
    MAPFILE -t JSON_FILES < <(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name "splitgate*.json")

    if [[ ${#JSON_FILES[@]} -eq 0 ]]; then
        echo "❌ No matching JSON files found. Exiting."
        exit 2
    fi

    # Create the target directory
    sudo mkdir -p "${BASE_DIR}"
    chmod 755 "${BASE_DIR}"

    echo "Creating ZIP archive at ${ZIP_PATH} ..."
    # zip -e: encrypt, -P password: set without prompt, -j: junk pathnames (no dirs)
    sudo zip -j -P "${ZIP_PASSWORD}" "${ZIP_PATH}" "${JSON_FILES[@]}"

    echo "✅ ZIP created (${#JSON_FILES[@]} files zipped)."
}

##########################
#  CONFIGURE NGINX       #
##########################

configure_nginx() {
    CONF_DIR="/etc/nginx/sites-available"
    CONF_FILE="${CONF_DIR}/${DOMAIN}"
    echo "Creating Nginx config file ${CONF_FILE}..."

    cat >"${CONF_FILE}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    # OPTIONAL: Redirect HTTP → HTTPS (requires certbot or similar)
    # return 301 https://\$host\$request_uri;

    location = ${URL_PATH} {
        alias ${ZIP_PATH};
        default_type application/zip;          # ensure correct MIME type
        add_header Cache-Control "no-store";   # optional: disable caching
        add_header Content-Disposition "attachment; filename=${ZIP_FILENAME}";
    }

    # Default 404 for everything else (you can remove this if you want an index page)
    location / {
        return 404;
    }
}
EOF

    # Enable the site
    if [[ -d "/etc/nginx/sites-enabled" ]]; then
        sudo ln -sf "${CONF_FILE}" "/etc/nginx/sites-enabled/${DOMAIN}"
    fi

    # Test configuration & reload
    echo "Testing Nginx config..."
    sudo nginx -t && sudo systemctl reload nginx

    echo "✅ Nginx configured and reloaded."
}

##########################
#  MAIN ENTRYPOINT       #
##########################

main() {
    install_nginx
    build_zip
    configure_nginx

    echo ""
    echo "All done! 🎉"
    echo "You can now download the ZIP with:"
    echo "   curl -O http://${DOMAIN}${URL_PATH}"
    echo "or open it directly in your browser."
}

main "$@"
