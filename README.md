# VPS WordPress Backbone

## Introduction
This project is a flexible, highly portable, and dynamic Docker Compose backbone for deploying and managing your own WordPress environment on a Virtual Private Server (VPS). It utilizes a containerized architecture to ensure you can easily, without loosing any data, migrate from one server to another, spin up new subdomains instantly, and securely manage your applications behind an NGINX reverse proxy.

## Included Services
The `docker-compose.yml` orchestrates the following core services:

*   **NGINX (Reverse Proxy):** Acts as the entry point for all traffic on port 443 (HTTPS), automatically routing requests to the correct container based on the hostname.
*   **WordPress:** The core content management system, running on the latest official image.
*   **MySQL 8 (db):** The relational database backing WordPress and any other future services.
*   **phpMyAdmin:** A web-based interface for managing the MySQL database.
*   **Portainer:** A lightweight management UI to easily monitor and control your Docker containers.

## Prerequisites
*   A Linux VPS.
*   Docker and Docker Compose installed.
*   A domain name pointing to your VPS IP address.
*   Your 15-year static Cloudflare origin certificates placed in `./certs/cloudflare.crt` and `./certs/cloudflare.key`.

## Configuration Workflow
This architecture uses an `.env` file to centrally manage all domains and secrets, ensuring no hard-coded sensitive data exists in your compose files.

1.  **Clone the Repository:** Pull your project into your desired VPS directory.
2.  **Prepare the Environment:** Duplicate or create an `.env` file based on the provided sample and populate it with your specific domain names and secure passwords.

## The Setup Script (`setup.sh`)
The core power of this backbone lies in the `setup.sh` file. Instead of manually writing complex NGINX configurations, this script parses your `docker-compose.yml` file, reads the `.env` variables, and dynamically builds `nginx.conf` and HTTP Basic Authentication files.

**What the script does:**

*   Reads the `.env` file to securely access credentials.
*   Uses OpenSSL to generate an `.htpasswd` file inside the `./auth/` directory for services requiring extra security (like phpMyAdmin and Portainer).
*   Extracts `hostname`, `domainname`, and `nginx.*` labels from the `docker-compose.yml` to automatically map virtual hosts (vhosts).
*   Generates the final `./configs/nginx/nginx.conf` file configured for strict HTTPS and Cloudflare TLS standards.
*   Seamlessly reloads NGINX if the container is already running to apply new changes with zero downtime.

## How to Use This Project

**Initial Deployment**

1.  Verify your `.env` variables and Cloudflare certificates are in place.
2.  Run the setup script: `bash setup.sh`
3.  Start the entire stack: `docker compose up -d`

**Making Changes (Domains, Passwords, Adding Services)**

1.  Update the relevant variables in your `.env` file or modify the labels in `docker-compose.yml`.
2.  Run `bash setup.sh` to regenerate the configurations. The script will automatically trigger NGINX to reload its configuration.

## Advanced Features
*   **Dynamic Routing:** Want to change your Portainer URL? Just update `PORTAINER_HOST` in `.env` and run the setup script.
*   **Basic Auth Protection:** To protect any service with HTTP Basic Auth, simply add the label `nginx.auth: "true"` to its service block in `docker-compose.yml`. The script will handle the rest.
*   **Portability:** To migrate, simply copy this directory (including the `.env` and mounted volumes) to a new server with Docker installed, point your DNS, and run `docker compose up -d`.

## Explaining Docker Compose Parameters for `setup.sh`

The `setup.sh` script inspects each service block in `docker-compose.yml` to automatically build reverse proxy routes and security policies. To enable automatic proxying for a service, both `hostname` and `domainname` **must** be set.

### Domain Name Resolution (`hostname` & `domainname`)

* **`hostname`**: Specifies the subdomain prefix for the container (e.g., `prt`, `pma`, `www`).
* **`domainname`**: Specifies the base or core domain for the service (e.g., `myproject.com`).

#### Transformation Logic
During execution, `setup.sh` extracts both properties and combines them into the Fully Qualified Domain Name (FQDN) used for NGINX's `server_name` directive:

`FQDN = ${hostname}.${domainname}`

**Example:**
If `hostname: prt` and `domainname: myproject.com`, `setup.sh` generates:

```nginx
server {
    listen 443 ssl;
    server_name prt.myproject.com;
    ...
}
```

---

### Custom Control Labels (`labels:`)

You can control upstream protocols, port mappings, and access restrictions by attaching specific `nginx.*` labels to any service:

| Label | Supported Values | Default | Description |
| :--- | :--- | :--- | :--- |
| **`nginx.auth`** | `"true"` \| `"false"` | `"false"` | Enables HTTP Basic Authentication. When set to `"true"`, `setup.sh` injects `auth_basic` protection using the `.htpasswd` file generated from `.env`. |
| **`nginx.schema`** | `"http"` \| `"https"` | `"http"` | Sets the upstream proxy protocol used by NGINX in `proxy_pass` (e.g., `proxy_pass https://portainer:9443;`). |
| **`nginx.port`** | `"<port_number>"` | `"80"` | Specifies the internal container port that NGINX routes traffic to. |

---

### Example Configuration

```yaml
    portainer:
        container_name: vps-portainer
        image: portainer/portainer-ce:sts
        # Resolves to: portainer.vps-wp.localhost
        hostname: ${PORTAINER_HOST:-portainer}
        domainname: ${PORTAINER_DOMAIN:-${CORE_DOMAIN:-localhost}}
        labels:
            nginx.auth: "true"     # Protect with Basic Auth (.htpasswd)
            nginx.schema: "https"  # Talk to Portainer via HTTPS upstream
            nginx.port: "9443"     # Forward traffic to internal port 9443
        restart: always
```