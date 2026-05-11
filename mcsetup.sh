#!/bin/bash

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${BLUE}=== Alfies Minecraft Server Tool ===${RESET}"

command -v curl >/dev/null 2>&1 || { echo "curl missing"; exit 1; }

if command -v apt >/dev/null 2>&1; then PKG="apt"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v zypper >/dev/null 2>&1; then PKG="zypper"
else
    echo -e "${RED}No package manager${RESET}"
    exit 1
fi

echo -e "${GREEN}Using: $PKG${RESET}"

if ! command -v java >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing Java...${RESET}"
    case $PKG in
        apt) sudo apt update >/dev/null 2>&1 && sudo apt install -y default-jdk ;;
        pacman) sudo pacman -Sy --noconfirm jdk-openjdk ;;
        dnf) sudo dnf install -y java-latest-openjdk ;;
        zypper) sudo zypper install -y java-21-openjdk ;;
    esac
fi

safe_download() {
    url="$1"
    if [ -z "$url" ]; then
        echo -e "${RED}Download URL empty${RESET}"
        exit 1
    fi

    if ! curl -fL --silent --show-error -o server.jar "$url"; then
        echo -e "${RED}Download failed${RESET}"
        echo "$url"
        exit 1
    fi

    [ ! -s server.jar ] && echo -e "${RED}Corrupt jar${RESET}" && exit 1
}

download_paper() {
    version=$1
    build=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$version" | grep -oP '"builds":\[\K[0-9,]+' | tr ',' '\n' | tail -n 1)
    url="https://api.papermc.io/v2/projects/paper/versions/$version/builds/$build/downloads/paper-$version-$build.jar"
    safe_download "$url"
}

download_velocity() {
    version=$1
    build=$(curl -s "https://api.papermc.io/v2/projects/velocity/versions/$version" | grep -oP '"builds":\[\K[0-9,]+' | tr ',' '\n' | tail -n 1)
    url="https://api.papermc.io/v2/projects/velocity/versions/$version/builds/$build/downloads/velocity-$version-$build.jar"
    safe_download "$url"
}

download_vanilla() {
    manifest=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)
    version_url=$(echo "$manifest" | grep -oP '"url":"[^"]+"' | head -n 1 | cut -d'"' -f4)

    [ -z "$version_url" ] && echo "Vanilla manifest fail" && exit 1

    version_json=$(curl -s "$version_url")
    url=$(echo "$version_json" | grep -oP '"server":"[^"]+"' | cut -d'"' -f4)

    [ -z "$url" ] && echo "Vanilla jar missing" && exit 1

    safe_download "$url"
}

selector() {
    local items=("$@")
    local i=0

    tput civis

    while true; do
        clear
        echo -e "${BLUE}Select:${RESET}"

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
                "[A") ((i--)) ;;
                "[B") ((i++)) ;;
            esac
        elif [[ $key == "" ]]; then
            break
        fi

        ((i < 0)) && i=$((${#items[@]} - 1))
        ((i >= ${#items[@]})) && i=0
    done

    tput cnorm
    return $i
}

systemd_install() {
    name=$(basename "$server_folder")

    sudo bash -c "cat > /etc/systemd/system/$name.service" <<EOF
[Unit]
Description=Minecraft Server $name
After=network.target

[Service]
WorkingDirectory=$server_folder
ExecStart=/usr/bin/bash $server_folder/start.sh
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$name"
    echo "systemd installed"
}

remove_server() {
    read -p "Name: " name
    read -p "Dir: " dir

    path="$dir/$name"

    [ ! -d "$path" ] && echo "Not found" && return

    read -p "Remove systemd? (yes/no): " s

    rm -rf "$path"

    if [ "$s" = "yes" ]; then
        sudo systemctl stop "$name" 2>/dev/null
        sudo systemctl disable "$name" 2>/dev/null
        sudo rm -f "/etc/systemd/system/$name.service"
        sudo systemctl daemon-reload
    fi

    echo "Deleted"
}

create_server() {

    types=("Vanilla" "Paper" "Velocity")
    selector "${types[@]}"
    type=$?

    server_type="${types[$type]}"

    read -p "Version: " version
    read -p "Name: " name
    read -p "Dir: " dir
    dir=${dir:-$(pwd)}

    read -p "Port (25565): " port
    port=${port:-25565}

    read -p "Max players (20): " max
    max=${max:-20}

    read -p "Whitelist (yes/no): " wl
    wl=${wl:-no}

    read -p "Seed: " seed
    read -p "OP: " op

    server_folder="$dir/$name"
    mkdir -p "$server_folder"
    cd "$server_folder"

    case "$server_type" in
        "Paper") download_paper "$version" ;;
        "Vanilla") download_vanilla ;;
        "Velocity") download_velocity "$version" ;;
    esac

    echo "eula=true" > eula.txt

    cat > server.properties <<EOF
server-port=$port
max-players=$max
white-list=$wl
level-seed=$seed
motd=$name
EOF

    [ -n "$op" ] && echo "$op" > ops.txt

    cat > start.sh <<EOF
#!/bin/bash
java -Xms2G -Xmx2G -jar server.jar nogui
EOF

    chmod +x start.sh

    options=("Start Server" "Copy Command" "Systemd" "Exit")
    selector "${options[@]}"
    c=$?

    case "$c" in
        0) bash start.sh ;;
        1) echo "cd \"$server_folder\" && bash start.sh" ;;
        2) systemd_install ;;
        3) exit 0 ;;
    esac
}

main=("Create Server" "Remove Server" "Exit")
selector "${main[@]}"
m=$?

case "$m" in
    0) create_server ;;
    1) remove_server ;;
    2) exit 0 ;;
esac