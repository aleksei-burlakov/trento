#!/bin/bash
# The script requires root permissions

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit
fi

function print_help() {
    cat <<END
This is a trento-agent installer. Trento is a web-based graphical user interface
that can help you deploy, provision and operate infrastructure for SAP Applications

Usage:

  sudo ./install-agent.sh --agent-bind-ip <192.168.122.10> --server-ip <192.168.122.5>

Arguments:
  --agent-bind-ip   The private address to which the trento-agent should be bound for internal communications.
                    This is an IP address that should be reachable by the other hosts, including the trento server.
  --server-ip       The trento server ip.
  --rolling         Use the factory/rolling-release version instead of the stable one.
  --help            Print this help.
END
}

case "$1" in
--help)
    print_help
    exit 0
    ;;
esac

ARGUMENT_LIST=(
    "agent-bind-ip:"
    "server-ip:"
    "rolling"
)



opts=$(
    getopt \
        --longoptions "$(printf "%s," "${ARGUMENT_LIST[@]}")" \
        --name "$(basename "$0")" \
        --options "" \
        -- "$@"
)

eval set "--$opts"

while [[ $# -gt 0 ]]; do
    case "$1" in
    --agent-bind-ip)
        AGENT_BIND_IP=$2
        shift 2
        ;;

    --server-ip)
        SERVER_IP=$2
        shift 2
        ;;

    --rolling)
        USE_ROLLING="true"
        shift 1
        ;;

    --use-tgz)
        USE_TGZ="true"
        shift 1
        ;;

    --install-from)
        INSTALL_FROM=$2
        shift 2
        ;;

    *)
        break
        ;;
    esac
done

if [[ -z "$USE_TGZ " && -z "$USE_ROLLING" ]] ; then
    # The default
    TRENTO_REPO=${TRENTO_REPO:-"https://download.opensuse.org/repositories/devel:/sap:/trento/15.3/devel:sap:trento.repo"}
    TRENTO_REPO_KEY=${TRENTO_REPO_KEY:-"https://download.opensuse.org/repositories/devel:/sap:/trento/15.3/repodata/repomd.xml.key"}
elif [[ -z "$USE_TGZ " && -n "$USE_ROLLING" ]] ; then
    TRENTO_REPO=${TRENTO_REPO:-"https://download.opensuse.org/repositories/devel:/sap:/trento:/factory/15.3/devel:sap:trento:factory.repo"}
    TRENTO_REPO_KEY=${TRENTO_REPO_KEY:-"https://download.opensuse.org/repositories/devel:/sap:/trento:/factory/15.3/repodata/repomd.xml.key"}
elif [[ -n "$USE_TGZ " && -z "$USE_ROLLING" ]] ; then
    TRENTO_REPO=
    TRENTO_REPO_KEY=
elif [[ -n "$USE_TGZ " && -n "$USE_ROLLING" ]] ; then
    TRENTO_REPO=
    TRENTO_REPO_KEY=
fi    

# Download and install the stable RPM
    

# Download and install the rolling RPM
if [[ -z "$USE_TGZ" && -n "$USE_ROLLING" ]] ; then
    
fi

# Download and install the rolling tgz

# Download and install the stable tgz

CONSUL_VERSION=1.9.6
CONSUL_PATH=/srv/consul
CONFIG_PATH="$CONSUL_PATH/consul.d"
CONSUL_HCL_TEMPLATE='data_dir = "/srv/consul/data/"
log_level = "DEBUG"
datacenter = "dc1"
ui = true
bind_addr = "@BIND_ADDR@"
client_addr = "0.0.0.0"
retry_join = ["@JOIN_ADDR@"]'

CONSUL_SERVICE_NAME="consul.service"
CONSUL_SERVICE_TEMPLATE='[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/srv/consul/consul.d/consul.hcl
PartOf=trento-agent.service

[Service]
ExecStart=/srv/consul/consul agent -config-dir=/srv/consul/consul.d
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
Type=notify


[Install]
WantedBy=multi-user.target'

. /etc/os-release
if [[ ! $PRETTY_NAME =~ "SUSE" ]]; then
    echo "Operating system is not supported. Exiting."
    exit 1
fi

echo "Installing trento-agent..."

function check_installer_deps() {
    if ! which unzip >/dev/null 2>&1; then
        echo "unzip is required by this script. Please install it with: zypper in -y unzip"
        exit 1
    fi
    if ! which curl >/dev/null 2>&1; then
        echo "curl is required by this script. Please install it with: zypper in -y curl"
        exit 1
    fi
}

function configure_installation() {
    if [ -z "$AGENT_BIND_IP" ]; then
        read -rp "Please provide a bind IP for the agent: " AGENT_BIND_IP </dev/tty
    fi
    if [ -z "$SERVER_IP" ]; then
        read -rp "Please provide the server IP: " SERVER_IP </dev/tty
    fi
    if [ -z "$INSTALL_FROM" ]; then
        INSTALL_FROM=${INSTALL_STABLE}
        read -rp "Please provide the server IP: " SERVER_IP </dev/tty
    else
    fi
}

function install_consul() {
    mkdir -p $CONFIG_PATH
    pushd -- "$CONSUL_PATH" >/dev/null
    curl -f -sS -O -L "https://releases.hashicorp.com/consul/$CONSUL_VERSION/consul_${CONSUL_VERSION}_linux_amd64.zip" >/dev/null
    unzip -o "consul_${CONSUL_VERSION}_linux_amd64".zip >/dev/null
    rm "consul_${CONSUL_VERSION}_linux_amd64".zip
    popd >/dev/null
}

function setup_consul() {
    echo "$CONSUL_HCL_TEMPLATE" |
        sed "s|@JOIN_ADDR@|${SERVER_IP}|g" |
        sed "s|@BIND_ADDR@|${AGENT_BIND_IP}|g" \
            >${CONFIG_PATH}/consul.hcl

    if [ -f "/usr/lib/systemd/system/$CONSUL_SERVICE_NAME" ]; then
        echo "  Warning: Consul systemd unit already installed. Removing..."
        systemctl stop "$CONSUL_SERVICE_NAME"
        rm "/usr/lib/systemd/system/$CONSUL_SERVICE_NAME"
    fi

    echo "$CONSUL_SERVICE_TEMPLATE" >/usr/lib/systemd/system/$CONSUL_SERVICE_NAME
    systemctl daemon-reload
}

function install_trento() {
    if [ -z "$USE_TGZ" ] ; then
        install_trento_tgz
    else
        install_trento_rpm
    fi
}

function install_trento_rpm() {
    if [[ -z "$USE_ROLLING" ]] ; then
        # The default
        TRENTO_REPO=${TRENTO_REPO:-"https://download.opensuse.org/repositories/devel:/sap:/trento/15.3/devel:sap:trento.repo"}
        TRENTO_REPO_KEY=${TRENTO_REPO_KEY:-"https://download.opensuse.org/repositories/devel:/sap:/trento/15.3/repodata/repomd.xml.key"}
    elif [[ -n "$USE_ROLLING" ]] ; then
        TRENTO_REPO=${TRENTO_REPO:-"https://download.opensuse.org/repositories/devel:/sap:/trento:/factory/15.3/devel:sap:trento:factory.repo"}
        TRENTO_REPO_KEY=${TRENTO_REPO_KEY:-"https://download.opensuse.org/repositories/devel:/sap:/trento:/factory/15.3/repodata/repomd.xml.key"}
    fi

    rpm --import "${TRENTO_REPO_KEY}" >/dev/null
    path=${TRENTO_REPO%/*}/
    if zypper lr --details | cut -d'|' -f9 | grep "$path" >/dev/null 2>&1; then
        echo "* $path repository already exists. Skipping."
    else
        echo "* Adding Trento repository: $path."
        zypper ar "$TRENTO_REPO" >/dev/null
    fi
    zypper ref >/dev/null
    if which trento >/dev/null 2>&1; then
        echo "* Trento is already installed. Updating trento"
        zypper up -y trento >/dev/null
    else
        echo "* Installing trento"
        zypper in -y trento >/dev/null
    fi
}

function install_trento_tgz() {
    if [[ -z "$USE_ROLLING" ]] ; then
        # The default
        TRENTO_TGZ_URL=https://github.com/trento-project/trento/releases/download/stable/trento-amd64.gz
        TRENTO_TGZ_URL=https://github.com/trento-project/trento/releases/download/rolling/trento-amd64.gz
    elif [[ -n "$USE_ROLLING" ]] ; then
        TRENTO_TGZ_URL=https://github.com/trento-project/trento/releases/download/latest/trento-amd64.gz
    fi
    TRENTO_TGZ_URL = blabla-release.tgz
    if USE_ROLLING
        TRENTO_TGZ_URL = blabla-rolling.tgz
    fi
}

check_installer_deps
configure_installation
install_consul
setup_consul
install_trento

echo -e "\e[92mDone.\e[97m"
echo -e "Now you can start trento-agent with: \033[1msystemctl start trento-agent\033[0m"
echo -e "Please make sure the \033[1mserver\033[0m is running before starting the agent."
