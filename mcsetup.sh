#!/bin/bash

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"
BOLD="\e[1m"

echo -e "${BLUE}=== Alfies Minecraft Server Tool ===${RESET}"
echo ""

# ---------------- PACKAGE MANAGER ---------------- #

if command -v apt >/dev/null 2>&1; then PKG="apt"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v zypper >/dev/null 2>&1; then PKG="zypper"
else
    echo -e "${RED}No supported package manager found${RESET}"
    exit 1
fi

echo -e "${GREEN}Using: $PKG${RESET}"

# ---------------- JAVA ---------------- #

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

# ---------------- DOWNLOADERS ---------------- #

download_paper() {
    version=$1

    build=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$version" \
        | grep -oP '"builds":\[\K[0-9,]+' | tr ',' '\n' | tail -n 1)

    url="https://api.papermc.io/v2/projects/paper/versions/$version/builds/$build/downloads/paper-$version-$build.jar"
    curl -s -o server.jar "$url"
}

download_velocity() {
    version=$1

    build=$(curl -s "https://api.papermc.io/v2/projects/velocity/versions/$version" \
        | grep -oP '"builds":\[\K[0-9,]+' | tr ',' '\n' | tail -n 1)

    url="https://api.papermc.io/v2/projects/velocity/versions/$version/builds/$build/downloads/velocity-$version-$build.jar"
    curl -s -o server.jar "$url"
}

download_vanilla() {
    manifest=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)

    version_url=$(echo "$manifest" | grep -oP '"url":"[^"]+"' | head -n 1 | cut -d'"' -f4)

    version_json=$(curl -s "$version_url")
    jar_url=$(echo "$version_json" | grep -oP '"server":"[^"]+"' | cut -d'"' -f4)

    curl -s -o server.jar "$jar_url"
}

# ---------------- CREATE SERVER ---------------- #

create_server() {
    clear

    types=("Vanilla" "Paper" "Velocity")
    t_selected=0

    tput civis

    while true; do
        clear
        echo -e "${BLUE}Select server type:${RESET}"
        echo ""

        for i in "${!types[@]}"; do
            if [ $i -eq $t_selected ]; then
                echo -e "${GREEN}➤ ${types[$i]}${RESET}"
            else
                echo -e "  ${types[$i]}"
            fi
        done

        echo ""
        echo -e "${YELLOW}↑ ↓ ENTER${RESET}"

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

        if [ $t_selected -lt 0 ]; then t_selected=$((${#types[@]} - 1)); fi
        if [ $t_selected -ge ${#types[@]} ]; then t_selected=0; fi
    done

    tput cnorm

    server_type=${types[$t_selected]}

    read -p "Minecraft version: " version
    read -p "Server name: " name
    read -p "Directory (default current): " dir
    dir=${dir:-$(pwd)}

    read -p "Port (default 25565): " port
    port=${port:-25565}

    read -p "Operator username (ENTER for none): " op

    server_folder="$dir/$name"
    mkdir -p "$server_folder"
    cd "$server_folder"

    echo -e "${CYAN}Downloading server...${RESET}"

    case "$server_type" in
        "Paper") download_paper "$version" ;;
        "Vanilla") download_vanilla "$version" ;;
        "Velocity") download_velocity "$version" ;;
    esac

    echo "eula=true" > eula.txt

    cat > server.properties <<EOF
server-port=$port
motd=$name
EOF

    if [ ! -z "$op" ]; then
        echo "$op" > ops.txt
    fi

    cat > start.sh <<EOF
#!/bin/bash
java -Xms2G -Xmx2G -jar server.jar nogui
EOF

    chmod +x start.sh

    echo ""
    echo -e "${GREEN}Server ready!${RESET}"
    sleep 1

    # ---------------- POST MENU ---------------- #

    options=("Start Server" "Copy Start Command" "Exit")
    selected=0

    while true; do
        clear
        echo -e "${BLUE}What would you like to do?${RESET}"
        echo ""

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                echo -e "${GREEN}➤ ${options[$i]}${RESET}"
            else
                echo -e "  ${options[$i]}"
            fi
        done

        echo ""
        echo -e "${YELLOW}↑ ↓ ENTER${RESET}"

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

        if [ $selected -lt 0 ]; then selected=$((${#options[@]} - 1)); fi
        if [ $selected -ge ${#options[@]} ]; then selected=0; fi
    done

    clear

    case $selected in
        0) bash start.sh ;;
        1)
            echo "cd \"$server_folder\" && bash start.sh"
            ;;
        2) exit 0 ;;
    esac
}

# ---------------- MAIN MENU ---------------- #

options=("Create New Server" "Remove Server" "Edit Server" "Exit")
selected=0

tput civis

while true; do
    clear
    echo -e "${BLUE}=== Alfies Minecraft Server Tool ===${RESET}"
    echo ""

    for i in "${!options[@]}"; do
        if [ $i -eq $selected ]; then
            echo -e "${CYAN}➤ ${options[$i]}${RESET}"
        else
            echo -e "  ${options[$i]}"
        fi
    done

    echo ""
    echo -e "${YELLOW}↑ ↓ ENTER${RESET}"

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

    if [ $selected -lt 0 ]; then selected=$((${#options[@]} - 1)); fi
    if [ $selected -ge ${#options[@]} ]; then selected=0; fi
done

tput cnorm

case $selected in
    0) create_server ;;
    1) echo "Not implemented yet" ;;
    2) echo "Not implemented yet" ;;
    3) exit 0 ;;
esac