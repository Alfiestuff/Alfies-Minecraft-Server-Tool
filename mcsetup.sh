#!/bin/bash

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"
BOLD="\e[1m"

echo -e "${BLUE}=== Alfies Minecraft Server Tool ===${RESET}"
echo ""

if command -v apt >/dev/null 2>&1; then PKG="apt"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v zypper >/dev/null 2>&1; then PKG="zypper"
else
    echo -e "${RED}No supported package manager${RESET}"
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
    echo -e "${GREEN}Java installed${RESET}"
fi

safe_download() {
    url="$1"
    if ! curl -f -L -o server.jar "$url"; then
        echo -e "${RED}Download failed: server.jar${RESET}"
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
    version_json=$(curl -s "$version_url")
    url=$(echo "$version_json" | grep -oP '"server":"[^"]+"' | cut -d'"' -f4)
    [ -z "$url" ] && echo -e "${RED}Vanilla URL fail${RESET}" && exit 1
    safe_download "$url"
}

create_systemd_service() {
    service_name=$(basename "$server_folder")
    sudo bash -c "cat > /etc/systemd/system/${service_name}.service" <<EOF
[Unit]
Description=Minecraft Server $service_name
After=network.target

[Service]
WorkingDirectory=$server_folder
ExecStart=/usr/bin/bash $server_folder/start.sh
Restart=always
RestartSec=10
User=$USER

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$service_name"
    echo -e "${GREEN}systemd installed${RESET}"
}

remove_server() {
    clear
    echo -e "${RED}Remove Server${RESET}"
    read -p "Name: " name
    read -p "Dir: " dir
    path="$dir/$name"
    [ ! -d "$path" ] && echo "Not found" && sleep 2 && return
    read -p "Delete systemd? (yes/no): " sys
    rm -rf "$path"
    if [ "$sys" == "yes" ]; then
        sudo systemctl stop "$name" 2>/dev/null
        sudo systemctl disable "$name" 2>/dev/null
        sudo rm -f "/etc/systemd/system/$name.service"
        sudo systemctl daemon-reload
    fi
    echo -e "${GREEN}Deleted${RESET}"
    sleep 2
}

create_server() {
    clear

    types=("Vanilla" "Paper" "Velocity")
    t_selected=0

    tput civis
    while true; do
        clear
        echo -e "${BLUE}Server Type${RESET}"
        for i in "${!types[@]}"; do
            [ "$i" -eq "$t_selected" ] && echo -e "${GREEN}➤ ${types[$i]}${RESET}" || echo "  ${types[$i]}"
        done
        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            case $key in
                "[A") ((t_selected--)) ;;
                "[B") ((t_selected++)) ;;
            esac
        elif [[ $key == "" ]]; then
            break
        fi
        ((t_selected < 0)) && t_selected=$((${#types[@]} - 1))
        ((t_selected >= ${#types[@]})) && t_selected=0
    done
    tput cnorm

    server_type=${types[$t_selected]}

    read -p "Version: " version
    read -p "Name: " name
    read -p "Dir: " dir
    dir=${dir:-$(pwd)}
    read -p "Port (25565): " port
    port=${port:-25565}
    read -p "Max players (20): " maxplayers
    maxplayers=${maxplayers:-20}
    read -p "Whitelist (yes/no): " whitelist
    whitelist=${whitelist:-no}
    read -p "Seed: " seed
    read -p "OP (enter none): " op

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
motd=$name
max-players=$maxplayers
white-list=$whitelist
level-seed=$seed
EOF

    [ ! -z "$op" ] && echo "$op" > ops.txt

    cat > start.sh <<EOF
#!/bin/bash
java -Xms2G -Xmx2G -jar server.jar nogui
EOF

    chmod +x start.sh

    options=("Start Server" "Copy Command" "Systemd Service" "Exit")
    selected=0

    while true; do
        clear
        echo -e "${BLUE}Action${RESET}"
        for i in "${!options[@]}"; do
            [ "$i" -eq "$selected" ] && echo -e "${GREEN}➤ ${options[$i]}${RESET}" || echo "  ${options[$i]}"
        done

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            case $key in
                "[A") ((selected--)) ;;
                "[B") ((selected++)) ;;
            esac
        elif [[ $key == "" ]]; then
            break
        fi
        ((selected < 0)) && selected=$((${#options[@]} - 1))
        ((selected >= ${#options[@]})) && selected=0
    done

    clear
    case $selected in
        0) bash start.sh ;;
        1) echo "cd \"$server_folder\" && bash start.sh" ;;
        2) create_systemd_service ;;
        3) exit 0 ;;
    esac
}

options=("Create Server" "Remove Server" "Exit")
selected=0

tput civis
while true; do
    clear
    echo -e "${BLUE}Menu${RESET}"
    for i in "${!options[@]}"; do
        [ "$i" -eq "$selected" ] && echo -e "${GREEN}➤ ${options[$i]}${RESET}" || echo "  ${options[$i]}"
    done

    read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
        read -rsn2 key
        case $key in
            "[A") ((selected--)) ;;
            "[B") ((selected++)) ;;
        esac
    elif [[ $key == "" ]]; then
        break
    fi
    ((selected < 0)) && selected=$((${#options[@]} - 1))
    ((selected >= ${#options[@]})) && selected=0
done
tput cnorm

case $selected in
    0) create_server ;;
    1) remove_server ;;
    2) exit 0 ;;
esac