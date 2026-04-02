#!/bin/bash

# Executable process script for FreeRadius docker image
RADIUS_PATH=/etc/raddb

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Logging functions with colors
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_config() {
    echo -e "${CYAN}[CONFIG]${NC} $1"
}

# Debug logging function
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo -e "${GRAY}[DEBUG]${NC} $1"
    fi
}


# Convert all environment variables with names ending in __FILE into the content of
# the file that they point at and use the name without the trailing __FILE.
# This can be used to carry in Docker secrets.
for VAR_NAME in $(env | grep '^[^=]\+__FILE=.\+' | sed -r 's/^([^=]*)__FILE=.*/\1/g'); do
	VAR_NAME_FILE="${VAR_NAME}__FILE"
	if [ "${!VAR_NAME}" ]; then
		log_error "Both ${VAR_NAME} and ${VAR_NAME_FILE} are set but are exclusive"
		exit 1
	fi
	VAR_FILENAME="${!VAR_NAME_FILE}"
	log_info "Getting secret ${VAR_NAME} from ${VAR_FILENAME}"
	if [ ! -r "${VAR_FILENAME}" ]; then
		log_error "${VAR_FILENAME} does not exist or is not readable"
		exit 1
	fi
	export "${VAR_NAME}"="$(<"${VAR_FILENAME}")"
	unset "${VAR_NAME_FILE}"
done

start_control_server() {
    socat TCP-LISTEN:${CONTROL_PORT},reuseaddr,fork "SYSTEM:CONTROL_TOKEN='${CONTROL_TOKEN}' \
    /usr/local/bin/02-restart-handler.sh" &
}

function init_freeradius {
    debug_log "Starting FreeRadius initialization..."
    debug_log "RADIUS_PATH: $RADIUS_PATH"

    # Enable SQL support only if SQL_ENABLE is explicitly set to "true". This is meant to be RW database access.
    # If you want to use SQL in read-only mode (no accounting, no post-auth), set SQL_READ_ONLY=true
    # If you want to read clients from the database, set SQL_READ_CLIENTS=true
    # If you want to enable sqlcounter, set SQL_COUNTER_ENABLE=true
    # If you want to enable sqlippool, set SQL_IPPOOL_ENABLE=true
    # @docs https://www.freeradius.org/documentation/freeradius-server/3.2.8/tutorials/sql.html

    # Copy default sql config to sql.default to use it as a template
    debug_log "Copying default SQL config to sql.default template"
    cp $RADIUS_PATH/mods-available/sql $RADIUS_PATH/mods-available/sql.default

    if [ "$SQL_ENABLE" = true ] && [ -n "$MYSQL_HOST" ]; then
        debug_log "SQL_ENABLE=true and MYSQL_HOST is set, configuring main SQL module"
        debug_log "MySQL Configuration: HOST=$MYSQL_HOST, PORT=$MYSQL_PORT, USER=$MYSQL_USER, DATABASE=$MYSQL_DATABASE"

        # Enable SQL module
        debug_log "Configuring SQL module: setting dialect to mysql"
		sed -i 's|dialect = "sqlite"|dialect = "mysql"|' $RADIUS_PATH/mods-available/sql
		sed -i 's|driver = "rlm_sql_null"|#driver = "rlm_sql_null"|' $RADIUS_PATH/mods-available/sql
        sed -i 's|#\s*driver = "rlm_sql_${dialect}"|    driver = "rlm_sql_${dialect}"|' $RADIUS_PATH/mods-available/sql

        debug_log "Disabling SQL TLS encryption"
		# Disable TLS
        sed -i 's|ca_file = "/etc/ssl/certs/my_ca.crt"|# ca_file = "/etc/ssl/certs/my_ca.crt"|' $RADIUS_PATH/mods-available/sql # disable SQL encryption
        sed -i 's|ca_path = "/etc/ssl/certs/"|# ca_path = "/etc/ssl/certs/"|' $RADIUS_PATH/mods-available/sql # disable SQL encryption
		sed -i 's|certificate_file = "/etc/ssl/certs/private/client.crt"|# certificate_file = "/etc/ssl/certs/private/client.crt"|' $RADIUS_PATH/mods-available/sql # disable SQL encryption
		sed -i 's|private_key_file = "/etc/ssl/certs/private/client.key"|# private_key_file = "/etc/ssl/certs/private/client.key"|' $RADIUS_PATH/mods-available/sql # disable SQL encryption
        sed -i 's|cipher = "DHE-RSA-AES256-SHA:AES128-SHA"|# cipher = "DHE-RSA-AES256-SHA:AES128-SHA"|' $RADIUS_PATH/mods-available/sql # disable SQL encryption
		sed -i 's|tls_required = yes|tls_required = no|' $RADIUS_PATH/mods-available/sql # disable SQL encryption

        debug_log "Setting database connection parameters"
        # Set Database connection: replace commented defaults with envs and uncomment
        sed -i 's|^#\s*server = "localhost"|    server = "'"$MYSQL_HOST"'"|' $RADIUS_PATH/mods-available/sql
        sed -i 's|^#\s*port = 3306|    port = "'"$MYSQL_PORT"'"|' $RADIUS_PATH/mods-available/sql
        sed -i 's|^#\s*login = "radius"|    login = "'"$MYSQL_USER"'"|' $RADIUS_PATH/mods-available/sql
        sed -i 's|^#\s*password = "radpass"|    password = "'"$MYSQL_PASSWORD"'"|' $RADIUS_PATH/mods-available/sql
        sed -i '1,$s/radius_db.*/radius_db="'$MYSQL_DATABASE'"/g' $RADIUS_PATH/mods-available/sql

        # Set to 'yes' to read radius clients from the database ('nas' table). Clients will ONLY be read on server startup.
        if [ "$SQL_READ_CLIENTS" = true ]; then
            debug_log "Enabling SQL client reading from database (nas table)"
            sed -i 's|#\s*read_clients = yes|    read_clients = yes|' $RADIUS_PATH/mods-available/sql
        else
            debug_log "SQL_READ_CLIENTS not enabled, clients will be read from files"
        fi

        debug_log "Creating symbolic link for SQL module in mods-enabled"

        # Enable SQL module
		ln -s $RADIUS_PATH/mods-available/sql $RADIUS_PATH/mods-enabled/sql

        debug_log "Adding SQL to instantiate section in radiusd.conf"

        # mods-enabled does not ensure the right order
        sed -i 's|instantiate {|instantiate {\n    sql|' $RADIUS_PATH/radiusd.conf

        log_success "SQL support enabled."

        # FOR READ-ONLY: Disable accounting and post-auth by commenting out the sections in queries.conf
        if [ "$SQL_READ_ONLY" = true ]; then
            debug_log "SQL_READ_ONLY=true, disabling accounting and post-auth SQL queries"

            # Create a custom queries.conf that excludes accounting and post-auth
            cp $RADIUS_PATH/mods-config/sql/main/mysql/queries.conf $RADIUS_PATH/mods-config/sql/main/mysql/queries.conf.backup

            # Remove accounting section from queries.conf
            sed -i '/^accounting {/,/^}/d' $RADIUS_PATH/mods-config/sql/main/mysql/queries.conf

            # Remove post-auth section from queries.conf
            sed -i '/^post-auth {/,/^}/d' $RADIUS_PATH/mods-config/sql/main/mysql/queries.conf

            log_config "SQL configured in READ-ONLY mode (accounting and post-auth SQL queries disabled)."
        else
            debug_log "SQL_READ_ONLY not enabled, keeping all SQL queries active"
        fi

        # Enable sqlcounter only if SQL_COUNTER_ENABLE=true
        if [ "${SQL_COUNTER_ENABLE}" = true ]; then
            debug_log "SQL_COUNTER_ENABLE=true, enabling SQL counter module"

        	sed -i 's|dialect = ${modules.sql.dialect}|dialect = "mysql"|' $RADIUS_PATH/mods-available/sqlcounter # avoid instantiation error
            ln -s $RADIUS_PATH/mods-available/sqlcounter $RADIUS_PATH/mods-enabled/sqlcounter

            log_success "SQL counter support enabled."
        else
            debug_log "SQL_COUNTER_ENABLE not enabled, skipping SQL counter configuration"
        fi

        # Enable sqlippool only if SQL_IPPOOL_ENABLE=true
        if [ "${SQL_IPPOOL_ENABLE}" = true ]; then
            debug_log "SQL_IPPOOL_ENABLE=true, enabling SQL IP pool module"

            ln -s $RADIUS_PATH/mods-available/sqlippool $RADIUS_PATH/mods-enabled/sqlippool

            log_success "SQL IP pool support enabled."
        else
            debug_log "SQL_IPPOOL_ENABLE not enabled, skipping SQL IP pool configuration"
        fi
    else
        debug_log "SQL_ENABLE=$SQL_ENABLE, MYSQL_HOST=$MYSQL_HOST - skipping main SQL configuration"
	fi

    if [ "$SQL_ENABLE_RO" = true ] && [ -n "$MYSQL_HOST_RO" ]; then
        debug_log "SQL_ENABLE_RO=true and MYSQL_HOST_RO is set, configuring read-only SQL module"
        debug_log "MySQL RO Configuration: HOST=$MYSQL_HOST_RO, PORT=$MYSQL_PORT_RO, USER=$MYSQL_USER_RO, DATABASE=$MYSQL_DATABASE_RO"

        # Create sql_ro config by copying sql.default
        cp $RADIUS_PATH/mods-available/sql.default $RADIUS_PATH/mods-available/sql_ro

        debug_log "Configuring sql_ro module for read-only database access"

        # Change the module name from "sql {" to "sql_ro {" to avoid conflicts
        sed -i 's/^sql {/sql_ro {/' $RADIUS_PATH/mods-available/sql_ro

        # Configure sql_ro module for read-only DB
        sed -i 's|dialect = "sqlite"|dialect = "mysql"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|driver = "rlm_sql_null"|#driver = "rlm_sql_null"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|#\s*driver = "rlm_sql_${dialect}"|    driver = "rlm_sql_${dialect}"|' $RADIUS_PATH/mods-available/sql_ro

        debug_log "Disabling TLS for sql_ro module"

        # Disable TLS
        sed -i 's|ca_file = "/etc/ssl/certs/my_ca.crt"|# ca_file = "/etc/ssl/certs/my_ca.crt"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|ca_path = "/etc/ssl/certs/"|# ca_path = "/etc/ssl/certs/"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|certificate_file = "/etc/ssl/certs/private/client.crt"|# certificate_file = "/etc/ssl/certs/private/client.crt"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|private_key_file = "/etc/ssl/certs/private/client.key"|# private_key_file = "/etc/ssl/certs/private/client.key"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|cipher = "DHE-RSA-AES256-SHA:AES128-SHA"|# cipher = "DHE-RSA-AES256-SHA:AES128-SHA"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|tls_required = yes|tls_required = no|' $RADIUS_PATH/mods-available/sql_ro

        debug_log "Setting read-only database connection parameters"

        # Set Database connection: replace commented defaults with envs and uncomment
        sed -i 's|^#\s*server = "localhost"|    server = "'"$MYSQL_HOST_RO"'"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|^#\s*port = 3306|    port = "'"$MYSQL_PORT_RO"'"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|^#\s*login = "radius"|    login = "'"$MYSQL_USER_RO"'"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i 's|^#\s*password = "radpass"|    password = "'"$MYSQL_PASSWORD_RO"'"|' $RADIUS_PATH/mods-available/sql_ro
        sed -i '1,$s/radius_db.*/radius_db="'$MYSQL_DATABASE_RO'"/g' $RADIUS_PATH/mods-available/sql_ro

        # Set to 'yes' to read radius clients from the database ('nas' table). Clients will ONLY be read on server startup.
        if [ "$SQL_READ_CLIENTS_RO" = true ]; then
            debug_log "Enabling read-only SQL client reading from database"

            sed -i 's|#\s*read_clients = yes|    read_clients = yes|' $RADIUS_PATH/mods-available/sql_ro
        else
            debug_log "SQL_READ_CLIENTS_RO not enabled for read-only SQL"
        fi

        debug_log "Creating symbolic link for sql_ro module in mods-enabled"

        # Enable sql_ro module
        ln -s $RADIUS_PATH/mods-available/sql_ro $RADIUS_PATH/mods-enabled/sql_ro

        log_success "SQL read-only support enabled."
    else
        debug_log "Skipping sql_ro module configuration in mods-enabled."
    fi

    if [ "$SQL_ENABLE_RO_AUTH" = true ]; then
        debug_log "SQL_ENABLE_RO_AUTH=true, updating authorize section to use sql_ro instead of -sql"

        # Replace -sql with sql_ro in authorize section of default site
        sed -i '/^authorize {/,/^}/s/^-sql$/sql_ro/' "$RADIUS_PATH/sites-available/default"

        log_config "authorize section updated to use sql_ro instead of -sql in default site."
    else
        debug_log "SQL_ENABLE_RO_AUTH not enabled, keeping default authorize configuration"
    fi

    if [ "$STATUS_ENABLE" == true ]; then
        debug_log "STATUS_ENABLE=true, configuring status page"
        # Set defaults if not provided
        STATUS_INTERFACE="${STATUS_INTERFACE:-eth0}"
        STATUS_CLIENT="${STATUS_CLIENT:-admin}"
        STATUS_SECRET="${STATUS_SECRET:-adminsecret}"

        debug_log "Status Configuration: INTERFACE=$STATUS_INTERFACE, CLIENT=$STATUS_CLIENT, SECRET=$STATUS_SECRET"

        # Check if STATUS_USE_ALL_INTERFACES is set to true
        if [ "$STATUS_USE_ALL_INTERFACES" == true ]; then
            IP_STATUS="0.0.0.0"
            debug_log "Setting the status page to listen on all interfaces (0.0.0.0)"
        else
            # Get IP of the radius container
            IP_STATUS=$(ifconfig "$STATUS_INTERFACE" | awk '/inet /{ print $2;}' | grep -v 'inet6' | head -n1)
            debug_log "Detected IP for status page: $IP_STATUS"
        fi

        log_info "Setting the status page for IP $IP_STATUS"

        # Only run sed if variables are not empty
        if [ -n "$IP_STATUS" ]; then
            debug_log "Updating status site IP configuration"
            sed -i "0,/ipaddr = 127.0.0.1/s/ipaddr = 127.0.0.1/ipaddr = $IP_STATUS/" "$RADIUS_PATH/sites-available/status"
            sed -i "0,/ipaddr = 127.0.0.1/s/ipaddr = 127.0.0.1/ipaddr = 0.0.0.0/" "$RADIUS_PATH/sites-available/status"
        fi

        if [ -n "$STATUS_CLIENT" ]; then
            debug_log "Updating status client name to: $STATUS_CLIENT"
            sed -i "s|client[[:space:]]\+admin[[:space:]]*{|client $STATUS_CLIENT {|" "$RADIUS_PATH/sites-available/status"
        fi

        if [ -n "$STATUS_SECRET" ]; then
            debug_log "Updating status client secret"
            sed -i "/client[[:space:]]\+$STATUS_CLIENT[[:space:]]*{/,/}/{s|^\([[:space:]]*secret[[:space:]]*=[[:space:]]*\).*|\1$STATUS_SECRET|}" "$RADIUS_PATH/sites-available/status"
        fi

        debug_log "Creating symbolic link for status site in sites-enabled"
        # Enable status in freeradius
        ln -sf "$RADIUS_PATH/sites-available/status" "$RADIUS_PATH/sites-enabled/status"

        log_success "Setting the status page for client $STATUS_CLIENT has been completed."
    else
        debug_log "STATUS_ENABLE not set to true, skipping status page configuration"
    fi

    if [ "$COA_RELAY_ENABLE" == true ]; then
        debug_log "COA_RELAY_ENABLE=true, configuring CoA relay"
        # Set default CoA relay packet destination port
        COA_RELAY_PACKET_DST_PORT=${COA_RELAY_PACKET_DST_PORT:-3799}
        # Set default interface if not provided
        COA_RELAY_INTERFACE=${COA_RELAY_INTERFACE:-eth0}

        debug_log "CoA Relay Configuration: PACKET_DST_PORT=$COA_RELAY_PACKET_DST_PORT, INTERFACE=$COA_RELAY_INTERFACE"

        # Check if COA_RELAY_USE_ALL_INTERFACES is set to true
        if [ "$COA_RELAY_USE_ALL_INTERFACES" == true ]; then
            IP_COA="0.0.0.0"
            debug_log "Setting the CoA relay to listen on all interfaces (0.0.0.0)"
        else
            # Get IP of the radius container
            IP_COA=$(ifconfig "$COA_RELAY_INTERFACE" | awk '/inet /{ print $2;}' | grep -v 'inet6' | head -n1)
            debug_log "Setting the CoA relay for IP $IP_COA"
        fi

        # Escape IP address for sed to handle special characters
        IP_COA_ESCAPED=$(printf '%s\n' "$IP_COA" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "0,/ipaddr = 127\.0\.0\.1/s/ipaddr = 127\.0\.0\.1/ipaddr = $IP_COA_ESCAPED/" "$RADIUS_PATH/sites-available/coa-relay"
        awk '/update control {/,/}/{ sub(/^#/, ""); print; next }1' "$RADIUS_PATH/sites-available/coa-relay" > temp && mv temp "$RADIUS_PATH/sites-available/coa-relay"
        sed -i "s|CoA-Packet-DST-Port := *1700|CoA-Packet-DST-Port := $COA_RELAY_PACKET_DST_PORT |" "$RADIUS_PATH/sites-available/coa-relay"

        # Comment out problematic attributes for legacy NAS devices if requested
        if [ "$COA_RELAY_DISABLE_LEGACY_ATTRIBUTES" == true ]; then
            debug_log "Commenting out Event-Timestamp and Message-Authenticator attributes for legacy NAS compatibility"
            # Comment out Event-Timestamp
            sed -i 's/^[[:space:]]*disconnect:Event-Timestamp/#&/' "$RADIUS_PATH/sites-available/coa-relay"
            # Comment out Message-Authenticator
            sed -i 's/^[[:space:]]*disconnect:Message-Authenticator/#&/' "$RADIUS_PATH/sites-available/coa-relay"
        fi

        # Remove the existing NAS configurations
        sed -i '/home_server coa-nas1 {/,$d' "$RADIUS_PATH/sites-available/coa-relay"

        # Get the number of NAS configurations
        NAS_COUNT=$(env | grep -c '^COA_RELAY_NAS_IP_')

        # Check if there are NAS configurations
        if [ $NAS_COUNT -eq 0 ]; then
            log_error "No NAS configurations found. Please set COA_RELAY_NAS_IP_1, COA_RELAY_NAS_PORT_1, and COA_RELAY_NAS_SECRET_1 environment variables to enable CoA relay"
            exit 1
        fi

        # Iterate over NAS configurations
        for ((i=1; i<=NAS_COUNT; i++)); do
            # Get NAS configuration from environment variables
            IP_VAR="COA_RELAY_NAS_IP_$i"
            PORT_VAR="COA_RELAY_NAS_PORT_$i"
            SECRET_VAR="COA_RELAY_NAS_SECRET_$i"

            IP=${!IP_VAR}
            PORT=${!PORT_VAR}
            SECRET=${!SECRET_VAR}

# Append NAS configuration to the file
echo "home_server coa-nas$i {
    type = coa
    ipaddr = $IP
    port = $PORT
    secret = $SECRET
    coa {
        irt = 2
        mrt = 16
        mrc = 5
        mrd = 30
    }
}" >> "$RADIUS_PATH/sites-available/coa-relay"
# Append home_server_pool configuration to the file
echo "home_server_pool coa-nas$i {
    type = fail-over
    home_server = coa-nas$i
    virtual_server = originate-coa-relay
}" >> "$RADIUS_PATH/sites-available/coa-relay"
        done

        debug_log "Creating symbolic link for coa-relay in sites-enabled"
        # Enable coa-relay in freeradius
        ln -s "$RADIUS_PATH/sites-available/coa-relay" "$RADIUS_PATH/sites-enabled/coa-relay"
        log_success "CoA relay has been enabled."

        mkdir -p /var/log/freeradius/raddact
        touch /var/log/freeradius/raddact/detail_coa

        echo 'detail detail_coa {
            filename = ${radacctdir}/detail_coa
            escape_filenames = no
            permissions = 0600
            header = "%t"
            locking = yes
        }' > "$RADIUS_PATH/mods-available/detail_coa"

        # Create symbolic link to mods-enabled
        ln -s "$RADIUS_PATH/mods-available/detail_coa" "$RADIUS_PATH/mods-enabled/detail_coa"
        log_success "Detail logging for CoA requests has been enabled."
    fi

    # Set to true to disable Van Jacobson TCP/IP Header Compression for PPP (for Cisco ASR BRAS)
    if [ "$DISABLE_PPP_VJ_COMPRESSION" == true ]; then
        sed -i '0,/Framed-Protocol = PPP,/! s/Framed-Protocol = PPP,/Framed-Protocol = PPP/' $RADIUS_PATH/mods-config/files/authorize
        sed -i '0,/Framed-Compression = Van-Jacobson-TCP-IP/s/Framed-Compression = Van-Jacobson-TCP-IP/#Framed-Compression = Van-Jacobson-TCP-IP/' $RADIUS_PATH/mods-config/files/authorize

        log_config "PPP Van Jacobson TCP/IP Header Compression has been disabled."
    fi

    # Enable control socket for raddebug
    if [ "$RADDEBUG_ENABLE" == true ]; then
        log_info "Enabling control socket for raddebug..."

        # Step 1: Create control socket site symlink
        ln -s $RADIUS_PATH/sites-available/control-socket $RADIUS_PATH/sites-enabled/control-socket

        # Step 2: Configure control socket with proper permissions
        sed -i 's|#\s*mode = rw|mode = rw|' $RADIUS_PATH/sites-available/control-socket

        # Ensure required directories exist with proper permissions
        mkdir -p /var/run/radiusd
        chown -R freerad:freerad /var/run/radiusd
        chmod 755 /var/run/radiusd

        # Create debug logs directory
        mkdir -p /var/log/freeradius/debug
        chown -R freerad:freerad /var/log/freeradius/debug
        chmod 755 /var/log/freeradius/debug

        log_success "Control socket configuration completed. You can now use 'raddebug' for debugging."
    fi

    if [ "$EAP_USE_TUNNELED_REPLY" == true ]; then
        # Enable used tunnel for unifi
        sed -i 's|use_tunneled_reply = no|use_tunneled_reply = yes|' $RADIUS_PATH/mods-available/eap
		log_config "EAP tunneled reply enabled for UniFi compatibility."
	fi

	debug_log "FreeRadius initialization completed successfully"
	log_success "FreeRadius initialization completed."
}

function init_database {
	mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < $RADIUS_PATH/mods-config/sql/main/mysql/schema.sql
	mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < $RADIUS_PATH/mods-config/sql/ippool/mysql/schema.sql

	# Insert a client for the current subnet only if DEFAULT__ENABLE = "true"
	if [ "$DEFAULT_CLIENT_ENABLE" == true ]; then
		IP=`ifconfig eth0 | awk '/inet/{ print $2;} '` # does also work: $IP=`hostname -I | awk '{print $1}'`
		NM=`ifconfig eth0 | awk '/netmask/{ print $4;} '`
		CIDR=`ipcalc $IP $NM | awk '/Network/{ print $2;} '`
        SECRET="${DEFAULT_CLIENT_SECRET:-testing123}"
        SHORTNAME="${DEFAULT_CLIENT_SHORTNAME:-DOCKER NET}"

		log_config "Adding client for $CIDR with default secret $SECRET and shortname $SHORTNAME"
		mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "INSERT INTO nas (nasname,shortname,type,ports,secret,server,community,description) VALUES ('$CIDR','$SHORTNAME','other',0,'$SECRET',NULL,'','')"
	else
		log_warn "Skipping default client addition. Set DEFAULT_CLIENT_ENABLE=true to enable."
	fi

	log_success "Database initialization for FreeRadius completed."
}

log_info "Starting FreeRadius..."

# Wait for MySQL-Server to be ready
if [ "$SQL_ENABLE" = true ] && [ -n "$MYSQL_HOST" ]; then
    MAX_RETRIES=10
    RETRY=0
    until mysqladmin --silent ping -h"$MYSQL_HOST"; do
        RETRY=$((RETRY+1))
        if [ $RETRY -ge $MAX_RETRIES ]; then
            log_error "MySQL ($MYSQL_HOST) did not become ready after $((MAX_RETRIES*2)) seconds, exiting."
            exit 1
        fi
        log_warn "Waiting for mysql ($MYSQL_HOST)... ($RETRY/$MAX_RETRIES)"
        sleep 2
    done
fi

if [ "$SQL_ENABLE" = true ] && [ -n "$MYSQL_HOST" ]; then
    if [ "$MYSQL_INIT" == true ]; then
        MYSQL_LOCK=/data/.MYSQL_init_done
        if test -f "$MYSQL_LOCK"; then
            log_info "Database lock file exists, skipping initial setup of mysql database."
        else
            init_database
            date > $MYSQL_LOCK
        fi
    else
        log_info "Database exists, skipping initial setup of mysql database."
    fi
fi

# Ensure postauth table schema is up-to-date (runs on every start, safe to re-run)
if [ "$CUSTOM_MYSQL_QUERIES_POST_AUTH" == true ] && [ "$SQL_ENABLE" = true ] && [ -n "$MYSQL_HOST" ]; then
    log_info "Checking postauth table schema..."

    # Check if reply_message column exists
    REPLY_MESSAGE_EXISTS=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SHOW COLUMNS FROM radpostauth LIKE 'reply_message';" | wc -l)
    if [ "$REPLY_MESSAGE_EXISTS" -eq 0 ]; then
        log_config "Adding reply_message column to radpostauth table..."
        mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "ALTER TABLE radpostauth ADD COLUMN reply_message varchar(253) default '';"
    fi

    # Check if nasipaddress column exists
    NASIP_EXISTS=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SHOW COLUMNS FROM radpostauth LIKE 'nasipaddress';" | wc -l)
    if [ "$NASIP_EXISTS" -eq 0 ]; then
        log_config "Adding nasipaddress column to radpostauth table..."
        mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "ALTER TABLE radpostauth ADD COLUMN nasipaddress varchar(15) default '';"
    fi

    # Add extended columns if CUSTOM_MYSQL_QUERIES_POST_AUTH_EXTENDED is enabled
    if [ "$CUSTOM_MYSQL_QUERIES_POST_AUTH_EXTENDED" == true ]; then
        # Check if callingstationid column exists
        CALLING_EXISTS=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SHOW COLUMNS FROM radpostauth LIKE 'callingstationid';" | wc -l)
        if [ "$CALLING_EXISTS" -eq 0 ]; then
            log_config "Adding callingstationid column to radpostauth table..."
            mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "ALTER TABLE radpostauth ADD COLUMN callingstationid varchar(50) default '';"
        fi

        # Check if calledstationid column exists
        CALLED_EXISTS=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SHOW COLUMNS FROM radpostauth LIKE 'calledstationid';" | wc -l)
        if [ "$CALLED_EXISTS" -eq 0 ]; then
            log_config "Adding calledstationid column to radpostauth table..."
            mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "ALTER TABLE radpostauth ADD COLUMN calledstationid varchar(50) default '';"
        fi
    fi

    log_success "Postauth table schema validation completed."
fi

INIT_LOCK=/internal_data/.init_done

if test -f "$INIT_LOCK"; then
	log_info "Init lock file exists, skipping initial setup."
else
	init_freeradius
	date > $INIT_LOCK
fi

# Apply custom post-auth queries on every start (not locked by init)
if [ "$CUSTOM_MYSQL_QUERIES_POST_AUTH" == true ] && [ "$SQL_ENABLE" = true ]; then
    log_info "Applying custom MySQL post-auth queries..."

    # Create temporary file with the new post-auth block
    if [ "$CUSTOM_MYSQL_QUERIES_POST_AUTH_EXTENDED" == true ]; then
        cat > /tmp/new_postauth.txt << 'EOF'
post-auth {
        # Write SQL queries to a logfile. This is potentially useful for bulk inserts
        # when used with the rlm_sql_null driver.
#       logfile = ${logdir}/post-auth.sql

        query = "\
                INSERT INTO ${..postauth_table} \
                        (username, pass, reply, reply_message, nasipaddress, callingstationid, calledstationid, authdate ${..class.column_name}) \
                VALUES ( \
                        '%{SQL-User-Name}', \
                        '%{%{User-Password}:-%{Chap-Password}}', \
                        '%{reply:Packet-Type}', \
                        '%{reply:Reply-Message}', \
                        '%{NAS-IP-Address}', \
                        '%{Calling-Station-Id}', \
                        '%{Called-Station-Id}', \
                        '%S.%M' \
                        ${..class.reply_xlat})"
}
EOF
    else
        cat > /tmp/new_postauth.txt << 'EOF'
post-auth {
        # Write SQL queries to a logfile. This is potentially useful for bulk inserts
        # when used with the rlm_sql_null driver.
#       logfile = ${logdir}/post-auth.sql

        query = "\
                INSERT INTO ${..postauth_table} \
                        (username, pass, reply, reply_message, nasipaddress, authdate ${..class.column_name}) \
                VALUES ( \
                        '%{SQL-User-Name}', \
                        '%{%{User-Password}:-%{Chap-Password}}', \
                        '%{reply:Packet-Type}', \
                        '%{reply:Reply-Message}', \
                        '%{NAS-IP-Address}', \
                        '%S.%M' \
                        ${..class.reply_xlat})"
}
EOF
    fi

    # Use awk to replace the post-auth block
    awk '
    /^post-auth \{/ {
        # Skip until closing brace
        while (getline > 0 && !/^}/) continue
        # Insert new post-auth block
        while ((getline line < "/tmp/new_postauth.txt") > 0) print line
        close("/tmp/new_postauth.txt")
        next
    }
    { print }
    ' $RADIUS_PATH/mods-config/sql/main/mysql/queries.conf > /tmp/queries_new.conf

    mv /tmp/queries_new.conf $RADIUS_PATH/mods-config/sql/main/mysql/queries.conf
    rm -f /tmp/new_postauth.txt

    log_success "Custom MySQL post-auth queries configuration completed."
fi

if [ "$CONTROL_ENABLE" == true ]; then
    log_info "Control server is enabled. Starting control server..."

     if [ -z "$CONTROL_PORT" ]; then
        log_error "CONTROL_PORT is not set. Please set CONTROL_PORT environment variable to enable control server."
        exit 1
    fi

    if [ -z "$CONTROL_TOKEN" ]; then
        log_error "CONTROL_TOKEN is not set. Please set CONTROL_TOKEN environment variable to enable control server."
        exit 1
    fi

    start_control_server

    log_success "Control server started on port $CONTROL_PORT."
fi

# this if will check if the first argument is a flag
# but only works if all arguments require a hyphenated flag
# -v; -SL; -f arg; etc will work, but not arg1 arg2
if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
    set -- freeradius "$@"
fi

# check for the expected command
if [ "$1" = 'freeradius' ]; then
    shift
    exec freeradius -f "$@"
fi

# many people are likely to call "radiusd" as well, so allow that
if [ "$1" = 'radiusd' ]; then
    shift
    exec freeradius -f "$@"
fi

# else default to run whatever the user wanted like "bash" or "sh"
exec "$@"
