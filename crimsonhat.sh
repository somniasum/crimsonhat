#!/usr/bin/env bash
# author: somniasum
# description: Automated Fedora tweaks for post-installation

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Make sure system is up-to-date
clear
echo -e "${BLUE}[ - ]${NC} Updating system."
sudo dnf update -y -q && \
sudo dnf autoremove -y -q && \
echo -e "${GREEN}[ + ]${NC} System updated."

# Functions
# DNF configuration
dnf_configuration(){

if grep -q "max_parallel_downloads" /etc/dnf/dnf.conf && \
   grep -q "fastestmirror" /etc/dnf/dnf.conf; then
    echo -e "${GREEN}[ + ]${NC} DNF configuration already optimized."
else
    echo -e "${BLUE}[ - ]${NC} Configuring DNF."
    echo -e 'max_parallel_downloads=10\nfastestmirror=True' | sudo tee -a /etc/dnf/dnf.conf > /dev/null && \
    echo -e "${GREEN}[ + ]${NC} DNF configuration optimized."
fi

}

# RPM Fusion configuration for multimedia codecs
rpm_fusion(){
    if rpm -q rpmfusion-free-release > /dev/null && \
       rpm -q rpmfusion-nonfree-release > /dev/null; then
    echo -e "${GREEN}[ + ]${NC} RPM Fusion already installed."
    else
    echo -e "${BLUE}[ - ]${NC} Installing RPM Fusion."
    sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm && \
    sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm > /dev/null && \
    echo -e "${GREEN}[ + ]${NC} RPM Fusion installed."
    fi
}

#Multimedia codecs
multimedia_codecs(){
    if
       rpm -q gstreamer1-plugin-openh264 > /dev/null && \
       rpm -q gstreamer1-plugins-{good-*,base} > /dev/null;then
           echo -e "${GREEN}[ + ]${NC} Multimedia codecs already installed."
    else
        echo -e "${BLUE}[ - ]${NC} Installing multimedia codecs."
        sudo dnf install gstreamer1-plugins-{good-*,base} gstreamer1-plugin-openh264 gstreamer1-libav --exclude=gstreamer1-plugins-bad-free-devel --allowerasing > /dev/null && \
        echo -e "${GREEN}[ + ]${NC} Multimedia codecs installed."
    fi
}

# GPU Drivers

gpu_drivers(){
    local gpu_check=$(lspci | grep -i vga)
    if echo $gpu_check | grep Intel > /dev/null; then
        echo -e "${PURPLE}[ # ]${NC} Intel GPU identified."
        if rpm -q intel-media-driver > /dev/null; then
            echo -e "${GREEN}[ + ]${NC} Intel drivers already installed."
        else
            echo -e "${BLUE}[ - ]${NC} Installing Intel drivers."
            sudo dnf install intel-media-driver > /dev/null && \
            echo -e "${GREEN}[ + ]${NC} Intel drivers installed."
        fi
    elif echo $gpu_check | grep NVIDIA > /dev/null; then
        echo -e "${PURPLE}[ # ] NVIDIA GPU identified.${NC}"
        if rpm -q akmod-nvidia > /dev/null; then
            echo -e "${GREEN}[ + ]${NC} NVIDIA drivers already installed."
        else
            echo -e "${BLUE}[ - ]${NC} Installing NVIDIA drivers."
            sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda > /dev/null && \
            echo -e "${GREEN}[ + ]${NC} NVIDIA drivers installed."
        fi
    elif echo $gpu_check | grep AMD > /dev/null; then
        echo -e "${PURPLE}[ # ] AMD GPU identified.${NC}"
        if rpm -q mesa-dri-drivers > /dev/null; then
            echo -e "${GREEN}[ + ]${NC} AMD drivers already installed."
        else
            echo -e "${BLUE}[ - ]${NC} Installing AMD drivers."
            sudo dnf install -y mesa-dri-drivers mesa-vulkan-drivers mesa-vdpau-drivers mesa-va-drivers vulkan-tools > /dev/null && \
            echo -e "${GREEN}[ + ]${NC} AMD drivers installed."
        fi
    else
        echo -e "${RED}[ - ]${NC} Unknown GPU."
        exit 1
    fi
}

#Performance optimization

performance_optimization(){
    local disk_type=$(lsblk -d -o name,rota | awk 'NR==2 {print $2}')
    if [ "$disk_type" = "0" ]; then
        echo -e "${PURPLE}[ # ]${NC} SSD identified."
        if rpm -q util-linux > /dev/null && \
           sudo cat /etc/sysctl.conf | grep -q swappiness > /dev/null; then
               echo -e "${GREEN}[ + ]${NC} SSD performance already optimized."
        else
            echo -e "${BLUE}[ - ]${NC} Optimizing system performance for SSD." && \
            echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf > /dev/null && \
            sudo sysctl -p > /dev/null && \
            echo -e "${GREEN}[ + ]${NC} SSD performance optimized."
        fi
    elif [ "disk_type" = "1" ]; then
        echo -e "${PURPLE}[ # ]${NC} HDD identified." && \
        echo -e "${BLUE} [ - ]${NC} Optimizing system performance for HDD."
        echo bfq | sudo tee /sys/block/sda/queue/scheduler > /dev/null && \
        echo -e "${GREEN}[ + ]${NC} HDD performance optimized."
    fi
}

#GNOME Optimization
desktop_environment=$(echo $XDG_CURRENT_DESKTOP)
gnome_optimization(){
    if pgrep -x "gnome-shell" > /dev/null; then
        echo -e "${PURPLE}[ # ]${NC} GNOME identified."
        read -p  "$( echo -e ${PURPLE}[ ? ]${NC} Would you like to optimize GNOME? [ ${GREEN}Y${NC} / ${RED}N${NC} ])" -n 1 -r > /dev/null &&
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}[ - ]${NC} Optimizing GNOME."
            gsettings set org.gnome.desktop.interface enable-animations false > /dev/null && \
            sudo sudo sh -c 'echo full > /sys/kernel/debug/sched/preempt' > /dev/null && \
            echo -e "${GREEN}[ + ]${NC} GNOME optimized."
        else
            echo -e "${BLUE}[ - ]${NC} Skipping GNOME optimization."
        fi
    else
        echo -e "${BLUE}[ - ]${NC} GNOME not detected. Skipping Desktop Environment."
    fi
}

# Main
dnf_configuration && \
rpm_fusion && \
multimedia_codecs && \
gpu_drivers && \
performance_optimization && \
gnome_optimization && \
echo -e "${GREEN}[ + ]${NC} Success. System optimized."
