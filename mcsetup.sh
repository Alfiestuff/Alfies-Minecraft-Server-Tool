#!/bin/bash

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${BLUE}=== Alfies Minecraft Server Tool ===${RESET}"
echo ""

# Detect package manager
echo -e "${YELLOW}Detecting package manager...${RESET}"

if command -v apt >/dev/null 2>&1; then
    PKG="apt"
elif command -v pacman >/dev/null 2>&1; then
    PKG="pacman"
elif command -v dnf >/dev/null 2>&1; then
    PKG="dnf"
elif command -v zypper >/dev/null 2>&1; then
    PKG="zypper"
else
    echo -e "${RED}No supported package manager found!${RESET}"
    exit 1
fi

echo -e "${GREEN}Using package manager: $PKG${RESET}"
echo ""

# Spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spin='-\|/'

    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r${CYAN}[ %c ] Working...${RESET}" "${spin:$i:1}"
            sleep $delay
        done
    done
    printf "\r"
}

# Install Java if missing
echo -e "${YELLOW}Checking Java installation...${RESET}"

if command -v java >/dev/null 2>&1; then
    echo -e "${GREEN}Java already installed!${RESET}"
    java -version
else
    echo -e "${RED}Java not found. Installing...${RESET}"
    echo ""

    case $PKG in
        apt)
            sudo apt update >/dev/null 2>&1 &
            spinner $!
            wait

            sudo apt install -y default-jdk >/dev/null 2>&1 &
            spinner $!
            wait
            ;;

        pacman)
            sudo pacman -Sy --noconfirm jdk-openjdk >/dev/null 2>&1 &
            spinner $!
            wait
            ;;

        dnf)
            sudo dnf install -y java-latest-openjdk >/dev/null 2>&1 &
            spinner $!
            wait
            ;;

        zypper)
            sudo zypper install -y java-21-openjdk >/dev/null 2>&1 &
            spinner $!
            wait
            ;;
    esac

    echo ""
    echo -e "${GREEN}Java installed successfully!${RESET}"
fi

echo ""
echo -e "${CYAN}System ready for Minecraft server setup.${RESET}"