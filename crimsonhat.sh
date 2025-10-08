#!/usr/bin/env bash
# author: somniasum
# description: Automated Fedora tweaks for post-installation
# version: 0.1

set -u

# Script configuration
readonly LOG_FILE="/tmp/crimsonhat_$(date +%Y%m%d_%H%M%S).log"

# Color definitions
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [BLUE]='\033[0;34m'
    [PURPLE]='\033[0;35m'
    [YELLOW]='\033[1;33m'
    [CYAN]='\033[0;36m'
    [BOLD]='\033[1m'
    [NC]='\033[0m'
)

# Log level configurations
declare -A LOG_LEVELS=(
    [INFO]="${COLORS[BLUE]}[ - ]${COLORS[NC]}"
    [SUCCESS]="${COLORS[GREEN]}[ + ]${COLORS[NC]}"
    [NOTICE]="${COLORS[PURPLE]}[ # ]${COLORS[NC]}"
    [ERROR]="${COLORS[RED]}[ ! ]${COLORS[NC]}"
    [WARN]="${COLORS[YELLOW]}[ * ]${COLORS[NC]}"
    [PROMPT]="${COLORS[PURPLE]}[ ? ]${COLORS[NC]}"
)

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    echo -e "${LOG_LEVELS[$level]} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

log_error() {
    local message="$*"
    echo -e "${LOG_LEVELS[ERROR]} $message" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" >> "$LOG_FILE"
}

# Progress indicator for operations
run_with_progress() {
    local message="$1"
    shift

    log INFO "$message"
    if "$@" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Banner
show_banner() {
    echo -e "${COLORS[PURPLE]}"
    cat << 'EOF'
╔════════════════════════════════════════╗
║              CRIMS0NH4T                ║
║                 v.0.1                  ║
╚════════════════════════════════════════╝
EOF
    echo -e "${COLORS[NC]}"
    log NOTICE "Log file: $LOG_FILE"
    echo
}

# Check prerequisites
check_prerequisites() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run as root."
        exit 1
    fi

    if ! sudo -v; then
        log_error "Use sudo."
        exit 1
    fi

    if ! command -v dnf &>/dev/null; then
        log_error "DNF not found. Are you running Fedora?"
        exit 1
    fi
    log SUCCESS "Prerequisites checked."
}

# System update
update_system() {
    log INFO "Updating system."
    echo

    if sudo dnf update -y; then
        echo
        log INFO "Cleaning system."
        sudo dnf autoremove -y
        echo
        log SUCCESS "System updated successfully."
    else
        echo
        log_error "System update failed."
        return 1
    fi
}

# DNF configuration
configure_dnf() {
    local dnf_conf="/etc/dnf/dnf.conf"
    local needs_update=false

    # Backup original config
    sudo cp "$dnf_conf" "${dnf_conf}.backup.$(date +%s)" 2>/dev/null || true

    # Check each setting
    if ! grep -q "^max_parallel_downloads=" "$dnf_conf" 2>/dev/null; then
        needs_update=true
    fi

    if ! grep -q "^fastestmirror=" "$dnf_conf" 2>/dev/null; then
        needs_update=true
    fi

    if [[ "$needs_update" == false ]]; then
        log SUCCESS "DNF already optimized."
        return 0
    fi

    log INFO "Optimizing DNF."

    # Add settings if they don't exist
    if ! grep -q "^max_parallel_downloads=" "$dnf_conf" 2>/dev/null; then
        echo "max_parallel_downloads=10" | sudo tee -a "$dnf_conf" >/dev/null
    fi

    if ! grep -q "^fastestmirror=" "$dnf_conf" 2>/dev/null; then
        echo "fastestmirror=True" | sudo tee -a "$dnf_conf" >/dev/null
    fi

    log SUCCESS "DNF config optimized."
}

# RPM Fusion repositories
install_rpm_fusion() {
    if rpm -q rpmfusion-free-release >/dev/null 2>&1 && \
       rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
        log SUCCESS "RPM Fusion already installed."
        return 0
    fi

    log INFO "Installing RPM Fusion."
    echo

    local fedora_version
    fedora_version=$(rpm -E %fedora)

    local free_url="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm"
    local nonfree_url="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"

    if sudo dnf install -y "$free_url" "$nonfree_url"; then
        echo
        log SUCCESS "RPM Fusion installed."
    else
        echo
        log_error "Failed to install RPM Fusion."
        return 1
    fi
}

# Multimedia codecs
install_multimedia_codecs() {
    local -a packages=(
        "gstreamer1-plugins-base"
        "gstreamer1-plugins-good"
        "gstreamer1-plugin-openh264"
    )

    local missing=false
    local -a missing_packages=()

    for pkg in "${packages[@]}"; do
        if ! rpm -q "$pkg" >/dev/null 2>&1; then
            missing=true
            missing_packages+=("$pkg")
        fi
    done

    if [[ "$missing" == false ]]; then
        log SUCCESS "Multimedia codecs already installed."
        return 0
    fi

    log INFO "Installing multimedia codecs."
    log NOTICE "Packages to install: ${missing_packages[*]}"
    echo

    if sudo dnf install -y \
        gstreamer1-plugins-{good,bad-free,base} \
        gstreamer1-plugin-openh264 \
        gstreamer1-libav \
        --exclude=gstreamer1-plugins-bad-free-devel \
        --allowerasing; then
        echo
        log SUCCESS "Multimedia codecs installed."
    else
        echo
        log_error "Failed to install multimedia codecs."
        return 1
    fi
}

# GPU drivers
install_gpu_drivers() {
    local gpu_info
    gpu_info=$(lspci | grep -iE "vga|3d|display")

    if [[ -z "$gpu_info" ]]; then
        log WARN "No GPU detected. Skipping driver installation."
        return 0
    fi

    log NOTICE "Detected GPU(s):"
    echo "$gpu_info" | while read -r line; do
        echo "  • $line"
    done
    echo

    # Intel GPU
    if echo "$gpu_info" | grep -qi intel; then
        log NOTICE "Intel GPU detected."

        if rpm -q intel-media-driver >/dev/null 2>&1; then
            log SUCCESS "Intel drivers already installed."
        else
            log INFO "Installing Intel drivers."
            if run_with_progress "Installing Intel drivers." sudo dnf install -y intel-media-driver; then
                log SUCCESS "Intel drivers installed."
            else
                log WARN "Failed to install Intel drivers."
            fi
        fi
    fi

    # NVIDIA GPU
    if echo "$gpu_info" | grep -qi nvidia; then
        log NOTICE "NVIDIA GPU detected."

        if rpm -q akmod-nvidia >/dev/null 2>&1; then
            log SUCCESS "NVIDIA drivers already installed."
        else
            log INFO "Installing NVIDIA drivers."
            echo
            if sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda; then
                echo
                log SUCCESS "NVIDIA drivers installed."
                log WARN "Reboot required for NVIDIA drivers to take effect."
            else
                echo
                log WARN "Failed to install NVIDIA drivers."
            fi
        fi
    fi

    # AMD GPU
    if echo "$gpu_info" | grep -qi "amd\|radeon"; then
        log NOTICE "AMD GPU detected."

        local -a amd_packages=(
            "mesa-vulkan-drivers"
            "mesa-vdpau-drivers"
            "mesa-va-drivers"
            "vulkan-tools"
        )

        local missing=false
        for pkg in "${amd_packages[@]}"; do
            if ! rpm -q "$pkg" >/dev/null 2>&1; then
                missing=true
                break
            fi
        done

        if [[ "$missing" == false ]]; then
            log SUCCESS "AMD drivers already installed."
        else
            log INFO "Installing AMD drivers."
            if run_with_progress "Installing AMD Mesa drivers." sudo dnf install -y "${amd_packages[@]}"; then
                log SUCCESS "AMD drivers installed."
            else
                log WARN "Failed to install AMD drivers."
            fi
        fi
    fi
}

# Performance optimization
optimize_performance() {
    local disk_type
    local primary_disk

    # Get the first disk info
    disk_type=$(lsblk -d -o name,rota | awk 'NR==2 {print $2}')
    primary_disk=$(lsblk -d -o name,rota | awk 'NR==2 {print $1}')

    if [[ -z "$disk_type" ]]; then
        log WARN "Failed to detect disk type. Skipping disk optimization."
        return 0
    fi

    # SSD optimization
    if [[ "$disk_type" == "0" ]]; then
        log NOTICE "SSD detected ($primary_disk)."

        if grep -q "^vm.swappiness=10" /etc/sysctl.conf 2>/dev/null; then
            log SUCCESS "SSD already optimized."
        else
            log INFO "Optimizing SSD."

            # Backup sysctl.conf
            sudo cp /etc/sysctl.conf "/etc/sysctl.conf.backup.$(date +%s)" 2>/dev/null || true

            echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf >/dev/null
            sudo sysctl -p >/dev/null 2>&1
            log SUCCESS "SSD optimized."
        fi

    # HDD optimization
    elif [[ "$disk_type" == "1" ]]; then
        log NOTICE "HDD detected ($primary_disk)."

        local scheduler_path="/sys/block/${primary_disk}/queue/scheduler"

        if [[ -f "$scheduler_path" ]]; then
            local current_scheduler
            current_scheduler=$(cmd < "$scheduler_path" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')

            if [[ "$current_scheduler" == "bfq" ]]; then
                log SUCCESS "HDD already optimized."
            else
                log INFO "Optimizing HDD."
                if echo "bfq" | sudo tee "$scheduler_path" >/dev/null 2>&1; then
                    log SUCCESS "HDD optimized."
                else
                    log WARN "Failed to optimize HDD."
                fi
            fi
        else
            log WARN "Scheduler configuration not available for $primary_disk."
        fi
    fi
}

# GNOME optimization
optimize_gnome() {
    if ! pgrep -x "gnome-shell" >/dev/null 2>&1; then
        log NOTICE "GNOME not detected. Skipping desktop optimization."
        return 0
    fi

    log NOTICE "GNOME desktop environment detected."

    echo -ne "${LOG_LEVELS[PROMPT]} Optimize GNOME? [${COLORS[GREEN]}Y${COLORS[NC]}/${COLORS[RED]}n${COLORS[NC]}]: "
    read -r response

    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        log INFO "Optimizing GNOME."

        # Disable animations
        if gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null; then
            log SUCCESS "Animations disabled for better performance."
        else
            log WARN "Failed to disable animations."
        fi

        log SUCCESS "GNOME optimized."
    else
        log INFO "Skipping GNOME optimization."
    fi
}

# Summary report
show_summary() {
    echo
    echo -e "${COLORS[CYAN]}╔════════════════════════════════════════╗${COLORS[NC]}"
    echo -e "${COLORS[CYAN]}║                SUMM4RY                 ║${COLORS[NC]}"
    echo -e "${COLORS[CYAN]}╚════════════════════════════════════════╝${COLORS[NC]}"
    echo
    log SUCCESS "System optimization successfull."
    echo
    log NOTICE "Changes made:"
    echo "  • System packages updated"
    echo "  • DNF optimized"
    echo "  • RPM Fusion configured"
    echo "  • Multimedia codecs installed"
    echo "  • GPU drivers configured"
    echo "  • System performance optimized"
    echo "  • Desktop environment optimized"
    echo
    log NOTICE "System Information:"
    echo "  • Fedora $(rpm -E %fedora)"
    echo "  • Kernel $(uname -r)"
    echo "  • Desktop: ${XDG_CURRENT_DESKTOP:-Unknown}"
    echo
    log INFO "Log file saved: $LOG_FILE"
    echo

    # Check if reboot is needed
    if needs-restarting -r &>/dev/null; then
        log WARN "System reboot is ${COLORS[BOLD]}REQUIRED${COLORS[NC]} to apply all changes."
    else
        log NOTICE "No reboot needed, but recommended for best results."
    fi
}

# Cleanup and final touches
cleanup() {
    log INFO "Cleaning up."

    # Clean DNF cache
    sudo dnf clean packages >/dev/null 2>&1 || true

    # Remove old kernels (keep last 3)
    local kernel_count
    kernel_count=$(rpm -q kernel | wc -l)

    if [[ $kernel_count -gt 3 ]]; then
        log INFO "Removing old kernels. Keeping latest 3."
        sudo dnf remove -y "$(dnf repoquery --installonly --latest-limit=-3 -q)" >/dev/null 2>&1 || true
        log SUCCESS "Old kernels removed."
    fi
}

# Main execution
main() {
    show_banner

    check_prerequisites
    update_system || true
    configure_dnf || true
    install_rpm_fusion || true
    install_multimedia_codecs || true
    install_gpu_drivers || true
    optimize_performance || true
    optimize_gnome || true

    show_summary
}

# Trap errors
trap 'log_error "Script failed at line $LINENO. Check the error above."' ERR

main "$@"
