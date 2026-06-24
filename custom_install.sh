#!/usr/bin/env bash
set -euo pipefail

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

ECHO_TYPE="echo -e"

TP_DATA="${TP_DATA:-/tpdata}"
WEB_PATH="${WEB_PATH:-${TP_DATA}/web}"
STATIC_HTML="${STATIC_HTML:-https://github.com/trojanpanel/install-script/releases/download/v1.0/html.tar.gz}"

MARIADB_CONTAINER="${MARIADB_CONTAINER:-trojan-panel-mariadb}"
REDIS_CONTAINER="${REDIS_CONTAINER:-trojan-panel-redis}"
PANEL_CONTAINER="${PANEL_CONTAINER:-trojan-panel}"
UI_CONTAINER="${UI_CONTAINER:-trojan-panel-ui}"
CORE_CONTAINER="${CORE_CONTAINER:-trojan-panel-core}"
WEB_CADDY_CONTAINER="${WEB_CADDY_CONTAINER:-trojan-panel-web-caddy}"
NODE_CADDY_CONTAINER="${NODE_CADDY_CONTAINER:-trojan-panel-node-caddy}"

CADDY_IMAGE="${CADDY_IMAGE:-caddy:2.8.4}"
MARIADB_IMAGE="${MARIADB_IMAGE:-mariadb:10.7.3}"
REDIS_IMAGE="${REDIS_IMAGE:-redis:6.2.7}"
PANEL_IMAGE="${PANEL_IMAGE:-jonssonyan/trojan-panel}"
UI_IMAGE="${UI_IMAGE:-jonssonyan/trojan-panel-ui}"
CORE_IMAGE="${CORE_IMAGE:-jonssonyan/trojan-panel-core}"

MARIADB_PORT="${MARIADB_PORT:-9507}"
MARIADB_USER="${MARIADB_USER:-root}"
MARIADB_DATABASE="${MARIADB_DATABASE:-trojan_panel_db}"
ACCOUNT_TABLE="${ACCOUNT_TABLE:-account}"
REDIS_PORT="${REDIS_PORT:-6378}"
PANEL_PORT="${PANEL_PORT:-8081}"
UI_PORT="${UI_PORT:-8888}"
CORE_PORT="${CORE_PORT:-8082}"
GRPC_PORT="${GRPC_PORT:-8100}"
NODE_CADDY_HTTP_PORT="${NODE_CADDY_HTTP_PORT:-80}"
NODE_CADDY_HTTPS_PORT="${NODE_CADDY_HTTPS_PORT:-8863}"

TP_FORCE="${TP_FORCE:-0}"
TP_PURGE_DATA="${TP_PURGE_DATA:-0}"

echo_content() {
  case $1 in
  "red") ${ECHO_TYPE} "\033[31m$2\033[0m" ;;
  "green") ${ECHO_TYPE} "\033[32m$2\033[0m" ;;
  "yellow") ${ECHO_TYPE} "\033[33m$2\033[0m" ;;
  "skyBlue") ${ECHO_TYPE} "\033[36m$2\033[0m" ;;
  *) ${ECHO_TYPE} "$2" ;;
  esac
}

usage() {
  cat <<EOF
Usage:
  $0 web
  $0 node
  $0 remove-web
  $0 remove-node

Required for web:
  env.yaml keys:
    trojan_panel.web_hostname

Optional for web:
  env.yaml keys:
    trojan_panel.web_mail
    trojan_panel.mariadb_password
    trojan_panel.redis_password
    trojan_panel.panel_image
    trojan_panel.ui_image

Required for node:
  env.yaml keys:
    trojan_panel.node_hostname
    trojan_panel.mariadb_host
    trojan_panel.mariadb_password
    trojan_panel.redis_host
    trojan_panel.redis_password

Optional for node:
  env.yaml keys:
    trojan_panel.node_mail
    trojan_panel.core_image
    trojan_panel.mariadb_user
    trojan_panel.mariadb_port
    trojan_panel.redis_port
    trojan_panel.node_caddy_http_port
    trojan_panel.node_caddy_https_port

Examples:
  $0 web ./env.yaml
  $0 node ./env.yaml
  $0 remove-web ./env.yaml
  $0 remove-node ./env.yaml
EOF
}

require_root() {
  if [[ "$(id -u)" != "0" ]]; then
    echo_content red "Please run as root"
    exit 1
  fi
}

require_value() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "${value}" ]]; then
    echo_content red "${name} is required"
    usage
    exit 1
  fi
}

random_password() {
  od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

container_exists() {
  docker ps -a -q -f "name=^$1$" | grep -q .
}

container_running() {
  docker ps -q -f "name=^$1$" -f "status=running" | grep -q .
}

remove_container_if_force() {
  local name="$1"
  if container_exists "${name}" && [[ "${TP_FORCE}" == "1" ]]; then
    docker rm -f "${name}" >/dev/null 2>&1 || true
  fi
}

install_packages() {
  local packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
  elif command -v apt >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt install -y "${packages[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "${packages[@]}"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "${packages[@]}"
  else
    echo_content red "No supported package manager found"
    exit 1
  fi
}

install_base_tools() {
  command -v curl >/dev/null 2>&1 || install_packages curl
  command -v tar >/dev/null 2>&1 || install_packages tar
  command -v od >/dev/null 2>&1 || install_packages coreutils
}

install_yq() {
  if command -v yq >/dev/null 2>&1; then
    return
  fi

  install_base_tools
  local arch
  case "$(uname -m)" in
  x86_64 | amd64)
    arch="amd64"
    ;;
  aarch64 | arm64)
    arch="arm64"
    ;;
  armv7l | armv7)
    arch="arm"
    ;;
  *)
    echo_content red "Unsupported architecture for yq: $(uname -m)"
    exit 1
    ;;
  esac

  echo_content green "---> Install yq"
  curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}" -o /usr/local/bin/yq
  chmod +x /usr/local/bin/yq
}

yaml_read_raw() {
  local file="$1"
  local key="$2"
  local value
  value="$(yq -r ".trojan_panel.${key} // \"\"" "${file}")"
  if command -v envsubst >/dev/null 2>&1; then
    value="$(printf '%s' "${value}" | envsubst)"
  fi
  printf '%s' "${value}"
}

cfg_first() {
  local file="$1"
  shift
  local key value
  for key in "$@"; do
    value="$(yaml_read_raw "${file}" "${key}")"
    if [[ -n "${value}" && "${value}" != "null" ]]; then
      printf '%s' "${value}"
      return
    fi
  done
}

cfg_apply() {
  local file="$1"
  local var_name="$2"
  shift 2
  local value
  value="$(cfg_first "${file}" "$@")"
  if [[ -n "${value}" ]]; then
    printf -v "${var_name}" '%s' "${value}"
  fi
}

load_config() {
  local action="$1"
  local file="${2:-}"
  if [[ -z "${file}" ]]; then
    echo_content red "Config file is required"
    usage
    exit 1
  fi
  if [[ ! -f "${file}" ]]; then
    echo_content red "Config file not found: ${file}"
    exit 1
  fi

  install_yq

  cfg_apply "${file}" CADDY_IMAGE caddy_image
  cfg_apply "${file}" MARIADB_IMAGE mariadb_image
  cfg_apply "${file}" REDIS_IMAGE redis_image
  cfg_apply "${file}" PANEL_IMAGE panel_image
  cfg_apply "${file}" UI_IMAGE ui_image
  cfg_apply "${file}" CORE_IMAGE core_image

  cfg_apply "${file}" MARIADB_PORT mariadb_port
  cfg_apply "${file}" MARIADB_USER mariadb_user
  cfg_apply "${file}" MARIADB_DATABASE database mariadb_database
  cfg_apply "${file}" ACCOUNT_TABLE account_table
  cfg_apply "${file}" REDIS_PORT redis_port
  cfg_apply "${file}" PANEL_PORT panel_port
  cfg_apply "${file}" UI_PORT ui_port
  cfg_apply "${file}" CORE_PORT core_port
  cfg_apply "${file}" GRPC_PORT grpc_port
  cfg_apply "${file}" NODE_CADDY_HTTP_PORT node_caddy_http_port caddy_port
  cfg_apply "${file}" NODE_CADDY_HTTPS_PORT node_caddy_https_port caddy_remote_port
  cfg_apply "${file}" TP_FORCE force
  cfg_apply "${file}" TP_PURGE_DATA purge_data

  case "${action}" in
  web | deploy-web)
    cfg_apply "${file}" TP_WEB_DOMAIN web_hostname web_domain hostname domain
    cfg_apply "${file}" TP_EMAIL web_mail web_email email mail
    cfg_apply "${file}" MARIADB_PASSWORD mariadb_password
    cfg_apply "${file}" REDIS_PASSWORD redis_password
    ;;
  node | deploy-node)
    cfg_apply "${file}" TP_NODE_DOMAIN node_hostname node_domain hostname domain
    cfg_apply "${file}" TP_EMAIL node_mail node_email email mail
    cfg_apply "${file}" MARIADB_HOST mariadb_host
    cfg_apply "${file}" MARIADB_PASSWORD mariadb_password
    cfg_apply "${file}" REDIS_HOST redis_host
    cfg_apply "${file}" REDIS_PASSWORD redis_password
    ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo_content skyBlue "---> Docker already installed"
    return
  fi

  echo_content green "---> Install Docker"
  if [[ "${DOCKER_INSTALL_MIRROR:-}" == "aliyun" ]]; then
    sh <(curl -fsSL https://get.docker.com) --mirror Aliyun
  else
    sh <(curl -fsSL https://get.docker.com)
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl restart docker >/dev/null 2>&1 || true
  fi
}

prepare_dirs() {
  mkdir -p \
    "${TP_DATA}" \
    "${WEB_PATH}" \
    "${TP_DATA}/trojan-panel/webfile" \
    "${TP_DATA}/trojan-panel/logs" \
    "${TP_DATA}/trojan-panel/config" \
    "${TP_DATA}/trojan-panel-ui/nginx" \
    "${TP_DATA}/trojan-panel-core/bin/xray/config" \
    "${TP_DATA}/trojan-panel-core/bin/trojango/config" \
    "${TP_DATA}/trojan-panel-core/bin/hysteria/config" \
    "${TP_DATA}/trojan-panel-core/bin/naiveproxy/config" \
    "${TP_DATA}/trojan-panel-core/bin/hysteria2/config" \
    "${TP_DATA}/trojan-panel-core/logs" \
    "${TP_DATA}/trojan-panel-core/config" \
    "${TP_DATA}/custom/web-caddy" \
    "${TP_DATA}/custom/node-caddy"
}

prepare_static_web() {
  if [[ -f "${WEB_PATH}/index.html" ]]; then
    return
  fi
  echo_content green "---> Prepare camouflage web files"
  curl -fsSL "${STATIC_HTML}" -o "${WEB_PATH}/html.tar.gz"
  tar -zxvf "${WEB_PATH}/html.tar.gz" -C "${WEB_PATH}" >/dev/null
}

write_web_caddyfile() {
  local domain="$1"
  local caddyfile="${TP_DATA}/custom/web-caddy/Caddyfile"
  if [[ -n "${TP_EMAIL:-}" ]]; then
    cat >"${caddyfile}" <<EOF
{
    email ${TP_EMAIL}
    http_port ${NODE_CADDY_HTTP_PORT}
    https_port ${NODE_CADDY_HTTPS_PORT}
}

${domain} {
    reverse_proxy 127.0.0.1:${UI_PORT}
}
EOF
  else
    cat >"${caddyfile}" <<EOF
${domain} {
    reverse_proxy 127.0.0.1:${UI_PORT}
}
EOF
  fi
}

write_node_caddyfile() {
  local domain="$1"
  local caddyfile="${TP_DATA}/custom/node-caddy/Caddyfile"
  if [[ -n "${TP_EMAIL:-}" ]]; then
    cat >"${caddyfile}" <<EOF
{
    email ${TP_EMAIL}
}

${domain} {
    root * /srv
    file_server
}
EOF
  else
    cat >"${caddyfile}" <<EOF
{
    http_port ${NODE_CADDY_HTTP_PORT}
    https_port ${NODE_CADDY_HTTPS_PORT}
}

${domain} {
    root * /srv
    file_server
}
EOF
  fi
}

start_caddy() {
  local name="$1"
  local config_dir="$2"
  local data_dir="$3"
  local web_dir="$4"

  remove_container_if_force "${name}"
  if container_running "${name}"; then
    echo_content skyBlue "---> ${name} already running"
    return
  fi
  if container_exists "${name}"; then
    docker start "${name}" >/dev/null
    return
  fi

  docker pull "${CADDY_IMAGE}"
  docker run -d --name "${name}" --restart always \
    --network=host \
    -v "${config_dir}/Caddyfile:/etc/caddy/Caddyfile" \
    -v "${data_dir}:/data" \
    -v "${config_dir}:/config" \
    -v "${web_dir}:/srv" \
    "${CADDY_IMAGE}"
}

wait_for_cert() {
  local domain="$1"
  local data_dir="$2"
  local cert_file="${data_dir}/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${domain}/${domain}.crt"
  local key_file="${data_dir}/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${domain}/${domain}.key"

  echo_content green "---> Wait for certificate: ${domain}"
  for _ in $(seq 1 60); do
    if [[ -s "${cert_file}" && -s "${key_file}" ]]; then
      echo_content skyBlue "---> Certificate ready: ${cert_file}"
      return
    fi
    sleep 3
  done

  echo_content red "---> Certificate is not ready. Check DNS, firewall, and Caddy logs."
  exit 1
}

wait_for_container() {
  local name="$1"
  for _ in $(seq 1 60); do
    if container_running "${name}"; then
      return
    fi
    sleep 2
  done
  echo_content red "---> ${name} is not running"
  docker logs "${name}" 2>/dev/null || true
  exit 1
}

wait_for_mariadb() {
  for _ in $(seq 1 60); do
    if docker exec "${MARIADB_CONTAINER}" sh -c "mariadb -uroot -p\"${MARIADB_PASSWORD}\" -e 'select 1' >/dev/null 2>&1 || mysql -uroot -p\"${MARIADB_PASSWORD}\" -e 'select 1' >/dev/null 2>&1"; then
      return
    fi
    sleep 2
  done
  echo_content red "---> MariaDB is not ready"
  docker logs "${MARIADB_CONTAINER}" 2>/dev/null || true
  exit 1
}

create_database() {
  docker exec "${MARIADB_CONTAINER}" sh -c "mariadb -uroot -p\"${MARIADB_PASSWORD}\" -e 'create database if not exists ${MARIADB_DATABASE} default character set utf8mb4;' >/dev/null 2>&1 || mysql -uroot -p\"${MARIADB_PASSWORD}\" -e 'create database if not exists ${MARIADB_DATABASE} default character set utf8mb4;' >/dev/null 2>&1"
}

write_ui_nginx_config() {
  cat >"${TP_DATA}/trojan-panel-ui/nginx/default.conf" <<EOF
server {
    listen       ${UI_PORT};
    server_name  localhost;

    location / {
        root   /tpdata/trojan-panel-ui;
        index  index.html index.htm;
    }

    location /api {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
    }
}
EOF
}

deploy_mariadb() {
  remove_container_if_force "${MARIADB_CONTAINER}"
  if container_running "${MARIADB_CONTAINER}"; then
    echo_content skyBlue "---> MariaDB already running"
    return
  fi
  if container_exists "${MARIADB_CONTAINER}"; then
    docker start "${MARIADB_CONTAINER}" >/dev/null
    wait_for_mariadb
    return
  fi

  docker pull "${MARIADB_IMAGE}"
  docker run -d --name "${MARIADB_CONTAINER}" --restart always \
    --network=host \
    -e MYSQL_DATABASE="${MARIADB_DATABASE}" \
    -e MYSQL_ROOT_PASSWORD="${MARIADB_PASSWORD}" \
    -e TZ=Asia/Shanghai \
    "${MARIADB_IMAGE}" \
    --port "${MARIADB_PORT}" \
    --character-set-server=utf8mb4 \
    --collation-server=utf8mb4_unicode_ci
  wait_for_mariadb
  create_database
}

deploy_redis() {
  remove_container_if_force "${REDIS_CONTAINER}"
  if container_running "${REDIS_CONTAINER}"; then
    echo_content skyBlue "---> Redis already running"
    return
  fi
  if container_exists "${REDIS_CONTAINER}"; then
    docker start "${REDIS_CONTAINER}" >/dev/null
    return
  fi

  docker pull "${REDIS_IMAGE}"
  docker run -d --name "${REDIS_CONTAINER}" --restart always \
    --network=host \
    "${REDIS_IMAGE}" redis-server --requirepass "${REDIS_PASSWORD}" --port "${REDIS_PORT}"
  wait_for_container "${REDIS_CONTAINER}"
}

deploy_panel_backend() {
  remove_container_if_force "${PANEL_CONTAINER}"
  if container_running "${PANEL_CONTAINER}"; then
    echo_content skyBlue "---> Trojan Panel backend already running"
    return
  fi
  if container_exists "${PANEL_CONTAINER}"; then
    docker start "${PANEL_CONTAINER}" >/dev/null
    return
  fi

  docker pull "${PANEL_IMAGE}"
  docker run -d --name "${PANEL_CONTAINER}" --restart always \
    --network=host \
    -v "${WEB_PATH}:${TP_DATA}/trojan-panel/webfile/" \
    -v "${TP_DATA}/trojan-panel/logs/:${TP_DATA}/trojan-panel/logs/" \
    -v "${TP_DATA}/trojan-panel/config/:${TP_DATA}/trojan-panel/config/" \
    -v /etc/localtime:/etc/localtime \
    -e GIN_MODE=release \
    -e "mariadb_ip=127.0.0.1" \
    -e "mariadb_port=${MARIADB_PORT}" \
    -e "mariadb_user=${MARIADB_USER}" \
    -e "mariadb_pas=${MARIADB_PASSWORD}" \
    -e "redis_host=127.0.0.1" \
    -e "redis_port=${REDIS_PORT}" \
    -e "redis_pass=${REDIS_PASSWORD}" \
    -e "server_port=${PANEL_PORT}" \
    "${PANEL_IMAGE}"
  wait_for_container "${PANEL_CONTAINER}"
}

deploy_panel_ui() {
  remove_container_if_force "${UI_CONTAINER}"
  write_ui_nginx_config
  if container_running "${UI_CONTAINER}"; then
    echo_content skyBlue "---> Trojan Panel UI already running"
    return
  fi
  if container_exists "${UI_CONTAINER}"; then
    docker start "${UI_CONTAINER}" >/dev/null
    return
  fi

  docker pull "${UI_IMAGE}"
  docker run -d --name "${UI_CONTAINER}" --restart always \
    --network=host \
    -v "${TP_DATA}/trojan-panel-ui/nginx/default.conf:/etc/nginx/conf.d/default.conf" \
    "${UI_IMAGE}"
  wait_for_container "${UI_CONTAINER}"
}

deploy_core() {
  local domain="$1"
  local cert_data="${TP_DATA}/custom/node-caddy/data"
  local crt_path="${cert_data}/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${domain}/${domain}.crt"
  local key_path="${cert_data}/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${domain}/${domain}.key"

  remove_container_if_force "${CORE_CONTAINER}"
  if container_running "${CORE_CONTAINER}"; then
    echo_content skyBlue "---> Trojan Panel Core already running"
    return
  fi
  if container_exists "${CORE_CONTAINER}"; then
    docker start "${CORE_CONTAINER}" >/dev/null
    return
  fi

  docker pull "${CORE_IMAGE}"
  docker run -d --name "${CORE_CONTAINER}" --restart always \
    --network=host \
    -v "${TP_DATA}/trojan-panel-core/bin/xray/config/:${TP_DATA}/trojan-panel-core/bin/xray/config/" \
    -v "${TP_DATA}/trojan-panel-core/bin/trojango/config/:${TP_DATA}/trojan-panel-core/bin/trojango/config/" \
    -v "${TP_DATA}/trojan-panel-core/bin/hysteria/config/:${TP_DATA}/trojan-panel-core/bin/hysteria/config/" \
    -v "${TP_DATA}/trojan-panel-core/bin/naiveproxy/config/:${TP_DATA}/trojan-panel-core/bin/naiveproxy/config/" \
    -v "${TP_DATA}/trojan-panel-core/bin/hysteria2/config/:${TP_DATA}/trojan-panel-core/bin/hysteria2/config/" \
    -v "${TP_DATA}/trojan-panel-core/logs/:${TP_DATA}/trojan-panel-core/logs/" \
    -v "${TP_DATA}/trojan-panel-core/config/:${TP_DATA}/trojan-panel-core/config/" \
    -v "${cert_data}:${cert_data}" \
    -v "${WEB_PATH}:${WEB_PATH}" \
    -v /etc/localtime:/etc/localtime \
    -e GIN_MODE=release \
    -e "mariadb_ip=${MARIADB_HOST}" \
    -e "mariadb_port=${MARIADB_PORT}" \
    -e "mariadb_user=${MARIADB_USER}" \
    -e "mariadb_pas=${MARIADB_PASSWORD}" \
    -e "database=${MARIADB_DATABASE}" \
    -e "account_table=${ACCOUNT_TABLE}" \
    -e "redis_host=${REDIS_HOST}" \
    -e "redis_port=${REDIS_PORT}" \
    -e "redis_pass=${REDIS_PASSWORD}" \
    -e "crt_path=${crt_path}" \
    -e "key_path=${key_path}" \
    -e "grpc_port=${GRPC_PORT}" \
    -e "server_port=${CORE_PORT}" \
    "${CORE_IMAGE}"
  wait_for_container "${CORE_CONTAINER}"
}

deploy_web() {
  require_value TP_WEB_DOMAIN
  MARIADB_PASSWORD="${MARIADB_PASSWORD:-$(random_password)}"
  REDIS_PASSWORD="${REDIS_PASSWORD:-$(random_password)}"
  export MARIADB_PASSWORD REDIS_PASSWORD

  install_base_tools
  install_docker
  prepare_dirs
  deploy_mariadb
  deploy_redis
  deploy_panel_backend
  deploy_panel_ui
  write_web_caddyfile "${TP_WEB_DOMAIN}"
  start_caddy "${WEB_CADDY_CONTAINER}" "${TP_DATA}/custom/web-caddy" "${TP_DATA}/custom/web-caddy/data" "${WEB_PATH}"

  echo_content red "\n=============================================================="
  echo_content skyBlue "Trojan Panel web side deployed"
  echo_content yellow "URL: https://${TP_WEB_DOMAIN}"
  echo_content yellow "Default username: sysadmin"
  echo_content yellow "Default password: 123456"
  echo_content yellow "MariaDB root password: ${MARIADB_PASSWORD}"
  echo_content yellow "Redis password: ${REDIS_PASSWORD}"
  echo_content red "==============================================================\n"
}

deploy_node() {
  require_value TP_NODE_DOMAIN
  require_value MARIADB_HOST
  require_value MARIADB_PASSWORD
  require_value REDIS_HOST
  require_value REDIS_PASSWORD

  install_base_tools
  install_docker
  prepare_dirs
  prepare_static_web
  write_node_caddyfile "${TP_NODE_DOMAIN}"
  start_caddy "${NODE_CADDY_CONTAINER}" "${TP_DATA}/custom/node-caddy" "${TP_DATA}/custom/node-caddy/data" "${WEB_PATH}"
  wait_for_cert "${TP_NODE_DOMAIN}" "${TP_DATA}/custom/node-caddy/data"
  deploy_core "${TP_NODE_DOMAIN}"

  echo_content red "\n=============================================================="
  echo_content skyBlue "Trojan Panel node side deployed"
  echo_content yellow "Node domain: ${TP_NODE_DOMAIN}"
  echo_content yellow "Core gRPC port: ${GRPC_PORT}"
  echo_content yellow "Core API port: ${CORE_PORT}"
  echo_content red "==============================================================\n"
}

remove_web() {
  docker rm -f "${WEB_CADDY_CONTAINER}" "${UI_CONTAINER}" "${PANEL_CONTAINER}" "${REDIS_CONTAINER}" "${MARIADB_CONTAINER}" >/dev/null 2>&1 || true
  if [[ "${TP_PURGE_DATA}" == "1" ]]; then
    rm -rf "${TP_DATA}/custom/web-caddy" "${TP_DATA}/trojan-panel" "${TP_DATA}/trojan-panel-ui" "${TP_DATA}/mariadb" "${TP_DATA}/redis"
  fi
  echo_content skyBlue "---> Trojan Panel web side removed"
}

remove_node() {
  docker rm -f "${CORE_CONTAINER}" "${NODE_CADDY_CONTAINER}" >/dev/null 2>&1 || true
  if [[ "${TP_PURGE_DATA}" == "1" ]]; then
    rm -rf "${TP_DATA}/custom/node-caddy" "${TP_DATA}/trojan-panel-core"
  fi
  echo_content skyBlue "---> Trojan Panel node side removed"
}

main() {
  local action="${1:-}"
  case "${action}" in
  -h | --help | help | "")
    usage
    ;;
  web | deploy-web)
    require_root
    load_config "${action}" "${2:-}"
    deploy_web
    ;;
  node | deploy-node)
    require_root
    load_config "${action}" "${2:-}"
    deploy_node
    ;;
  remove-web)
    require_root
    [[ -n "${2:-}" ]] && load_config "${action}" "${2:-}"
    remove_web
    ;;
  remove-node)
    require_root
    [[ -n "${2:-}" ]] && load_config "${action}" "${2:-}"
    remove_node
    ;;
  *)
    echo_content red "Unknown action: ${action}"
    usage
    exit 1
    ;;
  esac
}

main "$@"
