#!/bin/bash
# Run this on your VPS host machine in the same directory as docker-compose.yml

CONF_FILE="./configs/nginx/nginx.conf"
AUTH_FILE="./auth/.htpasswd"

echo "Initializing proxy generation sequence..."

# 1. Safely load variables directly from .env (Best Practice for secrets)
if [ -f ".env" ]; then
    set -a
    . .env
    set +a
fi

# 2. Generate the Basic Auth file if credentials exist
if [ -n "$BASIC_AUTH_USER" ] && [ -n "$BASIC_AUTH_PASSWORD" ]; then
    echo " -> Generating .htpasswd for user: $BASIC_AUTH_USER"

    # Use OpenSSL (natively available on the Linux host) to generate the hash
    # -apr1 creates an MD5-based password hash compatible with NGINX auth_basic
    HASH=$(openssl passwd -apr1 "$BASIC_AUTH_PASSWORD")

    # Write the user and hash to the file
    echo "$BASIC_AUTH_USER:$HASH" > "$AUTH_FILE"
else
    echo " -> Warning: BASIC_AUTH_USER or BASIC_AUTH_PASSWORD missing from .env. Skipping .htpasswd generation."
fi

echo " -> Generating NGINX configuration from Docker Compose labels..."

# 3. Write the core NGINX configuration block
cat << 'EOF' > "$CONF_FILE"
events {
    worker_connections 1024;
}

http {
    # Reference the 15-year static Cloudflare keys globally
    ssl_certificate     /etc/nginx/certs/cloudflare.crt;
    ssl_certificate_key /etc/nginx/certs/cloudflare.key;

    # Modern TLS standards required by Cloudflare edge nodes
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

EOF

# 4. Parse Docker Compose and dynamically map endpoints
docker compose config --format json | jq -r '
  .services | to_entries[] |
  select(.value.hostname != null and .value.domainname != null) |
  "\(.key)|\(.value.hostname)|\(.value.domainname)|\((.value.labels // {})["nginx.schema"] // "http")|\((.value.labels // {})["nginx.port"] // "80")|\((.value.labels // {})["nginx.auth"] // "false")"
' | while IFS="|" read -r svc hostname domainname schema port auth; do

    echo " -> Mapping vhost: ${hostname}.${domainname} to ${schema}://${svc}:${port} (Auth: ${auth})"

    # Generate optional Basic Auth block
    AUTH_CONF=""
    if [ "$auth" = "true" ]; then
        AUTH_CONF="
            auth_basic \"Restricted Access\";
            auth_basic_user_file /etc/nginx/auth/.htpasswd;"
    fi

    # Append the server block
    cat << EOF >> "$CONF_FILE"
    server {
        listen 443 ssl;
        server_name ${hostname}.${domainname};

        location / {
            proxy_pass ${schema}://${svc}:${port};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;${AUTH_CONF}
        }
    }

EOF
done

# 5. Close the HTTP block
cat << 'EOF' >> "$CONF_FILE"
}
EOF

echo "NGINX configuration generated successfully."

# 6. Gracefully reload NGINX if the container is already running
if docker ps --format '{{.Names}}' | grep -q "vps-nginx"; then
    echo " -> Reloading NGINX container without dropping connections..."
    docker exec vps-nginx nginx -s reload
fi
