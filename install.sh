#!/bin/bash
# The script requires root permissions

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi

function print_help() {
    cat <<END
This is a trento-agent installer. Trento is a web-based graphical user interface
that can help you deploy, provision and operate infrastructure for SAP Applications

Usage:

  sudo ./install.sh --bind-ip <127.0.0.1> --server-ip <192.168.122.1>

Arguments:
  --bind-ip    The consul bind ip.
  --server-ip  The consul server ip.
  --name       The node name.
  --help       Print this help.
END
}

# Treat the "--help" specially
# It neither requires a value
# nor is compatible with other arguments
case "$1" in
   --help)
        print_help
        exit 0;;
esac

ARGUMENT_LIST=(
    "bind-ip"
    "server-ip"
    "name"
)

# read arguments
opts=$(getopt \
    --longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
    --name "$(basename "$0")" \
    --options "" \
    -- "$@"
)

eval set --$opts

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bind-ip)
            CONSUL_BIND_IP=$2
            shift 2
            ;;

        --server-ip)
            CONSUL_SERVER_IP=$2
            shift 2
            ;;

        --name)
            NODE_NAME=$2
            shift 2
            ;;

        *)
            break
            ;;
    esac
done

if [ -z "$CONSUL_BIND_IP" ]; then
    read -p "Please provide the consul bind IP: "   CONSUL_BIND_IP
fi
if [ -z "$CONSUL_SERVER_IP" ]; then
    read -p "Please provide the consul server IP: " CONSUL_SERVER_IP
fi
if [ -z "$NODE_NAME" ]; then
    NODE_NAME="$(hostname)"
fi

TRENTO_REPO_KEY=${REPO_KEY:-"https://download.opensuse.org/repositories/devel:/sap:/trento/15.3/repodata/repomd.xml.key"}
TRENTO_REPO=${REPO:-"https://download.opensuse.org/repositories/devel:/sap:/trento/15.3/devel:sap:trento.repo"}

CONSUL_VERSION=1.9.6
CONSUL_HOME=/srv/consul
CONSUL_CONFIG_PATH="$CONSUL_HOME/consul.d"
CONSUL_HCL_TEMPLATE='data_dir = "/srv/consul/data/"
node_name = "@NODE_NAME@"
log_level = "DEBUG"
datacenter = "dc1"
ui = true
bind_addr = "@BIND_ADDR@"
client_addr = "0.0.0.0"
retry_join = ["@JOIN_ADDR@"]'

CONSUL_SERVICE_FILE_NAME="consul.service"
CONSUL_SERVICE_FILE='[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/srv/consul/consul.d/consul.hcl

[Service]
ExecStart=/srv/consul/consul agent -config-dir=/srv/consul/consul.d
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
Type=notify

[Install]
WantedBy=multi-user.target'

# Check if it's SUSE
. /etc/os-release
if [[ ! $PRETTY_NAME =~ "SUSE" ]]; then
    echo "Operating system is not supported. Exiting."
    exit -1
fi

echo "Installing trento-agent..."

function install_consul() {
    if ! which which  >/dev/null 2>/dev/null; then
        echo "* Installing which"
        zypper in -y which
    fi
    if ! which unzip  >/dev/null 2>/dev/null; then
        echo "* Installing unzip"
        zypper in -y unzip
    fi
    if ! which curl  >/dev/null 2>/dev/null; then
        echo "* Installing curl"
        zypper in -y curl
    fi

    echo "* Installing Consul"
    mkdir -p $CONSUL_CONFIG_PATH
    pushd -- "$CONSUL_HOME" >/dev/null
    curl -f -sS -O -L "https://releases.hashicorp.com/consul/$CONSUL_VERSION/consul_${CONSUL_VERSION}_linux_amd64.zip" >/dev/null
    unzip -o "consul_${CONSUL_VERSION}_linux_amd64".zip >/dev/null
    rm "consul_${CONSUL_VERSION}_linux_amd64".zip
    popd >/dev/null
    echo "  Consul is installed in $CONSUL_HOME"
}

function setup_consul() {
    echo "* Setting up Consul"
    echo "$CONSUL_HCL_TEMPLATE" \
        | sed "s|@JOIN_ADDR@|${CONSUL_SERVER_IP}|g" \
        | sed "s|@BIND_ADDR@|${CONSUL_BIND_IP}|g" \
        | sed "s|@NODE_NAME@|${NODE_NAME}|g" \
        > ${CONSUL_CONFIG_PATH}/consul.hcl
    echo "  Consul configuration is saved in ${CONSUL_CONFIG_PATH}/consul.hcl"

    if [ -f "/etc/systemd/system/$CONSUL_SERVICE_FILE_NAME" ]; then
        echo "  Warning: Systemd unit already installed. Removing..."
        systemctl stop "$CONSUL_SERVICE_FILE_NAME"
        rm "/etc/systemd/system/$CONSUL_SERVICE_FILE_NAME"
    fi

    echo "$CONSUL_SERVICE_FILE" > /etc/systemd/system/$CONSUL_SERVICE_FILE_NAME
    echo "  ${CONSUL_SERVICE_FILE_NAME} is installed in /etc/systemd/system/"
    systemctl daemon-reload
    systemctl enable --now $CONSUL_SERVICE_FILE_NAME
}

function install_trento() {
    if ! which which  >/dev/null 2>/dev/null; then
	echo "* Installing \"which\""
        zypper in -y which >/dev/null
    fi
    if ! which curl >/dev/null 2>/dev/null; then
	echo "* Installing curl"
        zypper in -y curl >/dev/null
    fi
    rpm --import ${TRENTO_REPO_KEY} >/dev/null
    path=${TRENTO_REPO%/*}/
    if zypper lr --details | cut -d'|' -f9 | grep $path  >/dev/null 2>/dev/null; then
        echo "* $path repository already exists. Skipping."
    else
        zypper ar $TRENTO_REPO >/dev/null
    fi
    zypper ref >/dev/null
    if which trento  >/dev/null 2>/dev/null; then
        echo "* Trento is already installed. Updating trento"
        zypper up -y trento >/dev/null
    else
	echo "* Installing trento"
        zypper in -y trento >/dev/null
    fi
}

function setup_trento() {
    # All setting are done by the rpm package
    # If it doesn't automatically start, let's start it here
    # Pay attention, the service is called -----> trento-agent <-------
    echo "* Starting trento"
    systemctl enable --now trento-agent
}

install_consul
setup_consul
install_trento
setup_trento
echo -e "\e[92mDone.\e[97m"
