#!/bin/bash
set -euo pipefail

# tput needs a terminal type; some launchers/IDE terminals run scripts
# without exporting one, which made `tput civis` fail and (under set -e)
# kill the script immediately.
export TERM="${TERM:-xterm-256color}"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

info()  { echo -e "${BLUE}$*${RESET}"; }
ok()    { echo -e "${GREEN}$*${RESET}"; }
warn()  { echo -e "${YELLOW}$*${RESET}"; }
error() { echo -e "${RED}$*${RESET}" >&2; }

trap 'tput cnorm 2>/dev/null || true' EXIT
trap 'tput cnorm 2>/dev/null || true; exit 130' INT

info "=== Alfies Minecraft Server Tool ==="

if command -v apt >/dev/null 2>&1; then PKG="apt"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v zypper >/dev/null 2>&1; then PKG="zypper"
else
    error "No supported package manager found (apt/pacman/dnf/zypper)"
    exit 1
fi

ok "Using package manager: $PKG"

# Installs $1 via the detected package manager if it isn't already on PATH.
# $2/$3/$4/$5 are the package names for apt/pacman/dnf/zypper respectively.
ensure_installed() {
    local bin="$1" apt_pkg="$2" pacman_pkg="$3" dnf_pkg="$4" zypper_pkg="$5"
    command -v "$bin" >/dev/null 2>&1 && return 0

    warn "Installing $bin..."
    case "$PKG" in
        apt)     sudo apt update -qq && sudo apt install -y "$apt_pkg" ;;
        pacman)  sudo pacman -Sy --noconfirm "$pacman_pkg" ;;
        dnf)     sudo dnf install -y "$dnf_pkg" ;;
        zypper)  sudo zypper install -y "$zypper_pkg" ;;
    esac || { error "Failed to install $bin"; exit 1; }
}

ensure_installed curl curl curl curl curl
ensure_installed jq jq jq jq jq

if ! command -v java >/dev/null 2>&1; then
    warn "Installing Java..."
    case "$PKG" in
        apt)    sudo apt update -qq && sudo apt install -y default-jdk ;;
        pacman) sudo pacman -Sy --noconfirm jdk-openjdk ;;
        dnf)    sudo dnf install -y java-latest-openjdk ;;
        zypper) sudo zypper install -y java-21-openjdk ;;
    esac || { error "Failed to install Java"; exit 1; }
fi

# Fetches a URL and fails loudly (with the URL) instead of silently continuing.
api_get() {
    local url="$1" response
    if ! response=$(curl -fsS "$url"); then
        error "Request failed: $url"
        return 1
    fi
    echo "$response"
}

safe_download() {
    local url="$1"
    if [ -z "$url" ]; then
        error "Download URL empty"
        exit 1
    fi

    info "Downloading server.jar..."
    if ! curl -fL --progress-bar -o server.jar "$url"; then
        error "Download failed: $url"
        exit 1
    fi

    if [ ! -s server.jar ]; then
        error "Downloaded file is empty/corrupt"
        exit 1
    fi
}

# Shared by Paper and Velocity: both are served from PaperMC's v3 API
# (fill.papermc.io) with an identical projects/<project>/versions/<version>/builds
# layout. The old v2 API (api.papermc.io) was retired and now returns 410 Gone.
# Builds are listed newest-first, so the first entry is the latest build.
download_papermc_project() {
    local project="$1" version="$2"
    local builds_json url

    builds_json=$(api_get "https://fill.papermc.io/v3/projects/$project/versions/$version/builds") || exit 1
    url=$(jq -r '.[0].downloads["server:default"].url // empty' <<<"$builds_json")

    if [ -z "$url" ]; then
        error "No builds found for $project version '$version' (check the version is valid)"
        exit 1
    fi

    safe_download "$url"
}

download_vanilla() {
    local version="$1"
    local manifest version_url version_json url

    manifest=$(api_get "https://launchermeta.mojang.com/mc/game/version_manifest.json") || exit 1
    version_url=$(jq -r --arg v "$version" '.versions[] | select(.id == $v) | .url' <<<"$manifest")

    if [ -z "$version_url" ]; then
        error "Vanilla version '$version' not found in Mojang's manifest"
        exit 1
    fi

    version_json=$(api_get "$version_url") || exit 1
    url=$(jq -r '.downloads.server.url // empty' <<<"$version_json")

    if [ -z "$url" ]; then
        error "No server jar available for vanilla version '$version'"
        exit 1
    fi

    safe_download "$url"
}

# Arrow-key menu. Uses i=$((i-1)) rather than ((i--)) because under `set -e`
# a compound-command arithmetic result of 0 is treated as failure and kills
# the script.
selector() {
    local items=("$@")
    local i=0 key

    tput civis 2>/dev/null || true

    while true; do
        clear 2>/dev/null || true
        info "Select:"

        for idx in "${!items[@]}"; do
            if [ "$idx" -eq "$i" ]; then
                echo -e "${GREEN}> ${items[$idx]}${RESET}"
            else
                echo "  ${items[$idx]}"
            fi
        done

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            case $key in
                "[A") i=$((i - 1)) ;;
                "[B") i=$((i + 1)) ;;
            esac
        elif [[ $key == "" ]]; then
            break
        fi

        [ "$i" -lt 0 ] && i=$((${#items[@]} - 1))
        [ "$i" -ge "${#items[@]}" ] && i=0
    done

    tput cnorm 2>/dev/null || true

    # Drain any stray unconsumed bytes (e.g. a partially-read escape sequence)
    # so they can't leak into the next `read -rp` prompt.
    while read -r -t 0.01 -n 1 _ 2>/dev/null; do :; done

    return "$i"
}

# Restricts free-text input to safe filesystem-name characters so it can't
# escape the target directory (e.g. "../../etc") or break quoting.
prompt_safe_name() {
    local label="$1" value
    while true; do
        read -rp "$label: " value
        if [[ "$value" =~ ^[A-Za-z0-9_-]+$ ]]; then
            echo "$value"
            return 0
        fi
        error "Only letters, numbers, - and _ are allowed."
    done
}

prompt_number() {
    local label="$1" default="$2" min="$3" max="$4" value
    while true; do
        read -rp "$label ($default): " value
        value=${value:-$default}
        if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge "$min" ] && [ "$value" -le "$max" ]; then
            echo "$value"
            return 0
        fi
        error "Enter a number between $min and $max."
    done
}

systemd_install() {
    local server_folder="$1"
    local name; name=$(basename "$server_folder")

    sudo bash -c "cat > /etc/systemd/system/$name.service" <<EOF
[Unit]
Description=Minecraft Server $name
After=network.target

[Service]
WorkingDirectory=$server_folder
ExecStart=/bin/bash $server_folder/start.sh
Restart=always
User=$(id -un)

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$name"
    ok "systemd service '$name' installed and enabled"
}

remove_server() {
    local name dir path confirm
    name=$(prompt_safe_name "Name")
    read -rp "Dir: " dir
    dir=${dir:-$(pwd)}

    path="$dir/$name"

    if [ ! -d "$path" ]; then
        error "Not found: $path"
        return
    fi

    warn "This will permanently delete: $(realpath "$path")"
    read -rp "Type DELETE to confirm: " confirm
    if [ "$confirm" != "DELETE" ]; then
        info "Cancelled"
        return
    fi

    read -rp "Remove systemd service too? (yes/no): " s

    rm -rf -- "$path"

    if [ "$s" = "yes" ]; then
        sudo systemctl stop "$name" 2>/dev/null || true
        sudo systemctl disable "$name" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/$name.service"
        sudo systemctl daemon-reload
    fi

    ok "Deleted $path"
}

create_server() {
    local types=("Vanilla" "Paper" "Velocity")
    selector "${types[@]}"
    local server_type="${types[$?]}"

    local version name dir port max wl seed mem server_folder

    if [ "$server_type" != "Velocity" ]; then
        read -rp "Version (e.g. 1.21.1): " version
    else
        read -rp "Velocity version (e.g. 3.3.0-SNAPSHOT): " version
    fi
    [ -z "$version" ] && { error "Version is required"; exit 1; }

    name=$(prompt_safe_name "Name")
    read -rp "Dir ($(pwd)): " dir
    dir=${dir:-$(pwd)}

    server_folder="$dir/$name"
    if [ -e "$server_folder" ]; then
        read -rp "'$server_folder' already exists, overwrite? (yes/no): " overwrite
        [ "$overwrite" != "yes" ] && { info "Cancelled"; return; }
        rm -rf -- "$server_folder"
    fi

    port=$(prompt_number "Port" 25565 1 65535)
    max=$(prompt_number "Max players" 20 1 2000)
    read -rp "Whitelist (yes/no) (no): " wl
    wl=${wl:-no}
    read -rp "Seed (blank for random): " seed
    mem=$(prompt_number "Memory to allocate in GB" 2 1 128)

    mkdir -p "$server_folder"
    cd "$server_folder"

    case "$server_type" in
        "Paper")    download_papermc_project paper "$version" ;;
        "Vanilla")  download_vanilla "$version" ;;
        "Velocity") download_papermc_project velocity "$version" ;;
    esac

    if [ "$server_type" != "Velocity" ]; then
        echo "eula=true" > eula.txt

        cat > server.properties <<EOF
server-port=$port
max-players=$max
white-list=$wl
level-seed=$seed
motd=$name
EOF
        info "Server created. Use the in-game /op command after first launch to grant operator status."
    else
        info "Velocity will generate velocity.toml and forwarding.secret on first launch - edit velocity.toml afterwards."
    fi

    cat > start.sh <<EOF
#!/bin/bash
exec java -Xms${mem}G -Xmx${mem}G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -jar server.jar nogui
EOF
    chmod +x start.sh

    ok "Server '$name' set up at $server_folder"

    local options=("Start Server" "Copy Command" "Install as systemd service" "Exit")
    selector "${options[@]}"
    case "$?" in
        0) bash start.sh ;;
        1) echo "cd \"$server_folder\" && bash start.sh" ;;
        2) systemd_install "$server_folder" ;;
        3) exit 0 ;;
    esac
}

main() {
    local menu=("Create Server" "Remove Server" "Exit")
    selector "${menu[@]}"
    case "$?" in
        0) create_server ;;
        1) remove_server ;;
        2) exit 0 ;;
    esac
}

main
