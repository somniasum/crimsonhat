#!/usr/bin/env bash
# author: somniasum
# description: script to optimize Fedora
# version: 0.6

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
  [NOTICE]="${COLORS[CYAN]}[ # ]${COLORS[NC]}"
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
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >>"$LOG_FILE"
}

log_error() {
  local message="$*"
  echo -e "${LOG_LEVELS[ERROR]} $message" >&2
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" >>"$LOG_FILE"
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
  cat <<'EOF'
╔════════════════════════════════════════╗
║              CRIMS0NH4T                ║
║                 v.0.6                  ║
╚════════════════════════════════════════╝
EOF
  echo -e "${COLORS[NC]}"
  log NOTICE "Log file: $LOG_FILE"
  echo
}

# Prompt function to handle user input
prompt() {
  local prompt_text="${1:-}"
  local response
  echo -ne "${LOG_LEVELS[PROMPT]} ${prompt_text} [${COLORS[GREEN]}Y${COLORS[NC]}/${COLORS[RED]}n${COLORS[NC]}]: "
  read -r response
  #exit code for yes or no
  [[ "$response" =~ ^[Yy]$ || -z "$response" ]]
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
  if prompt "Update system?"; then
    log INFO "Updating system."
    sudo dnf up -y &&
      log SUCCESS "System updated successfully." || log_error "System failed to update."
  else
    log NOTICE "Skipping system update."
  fi
  if prompt "Clean system?"; then
    sudo dnf autoremove -y &&
      log SUCCESS "System cleaned successfully." ||
      {
        log_error "System clean failed."
        return 1
      }
  else
    log NOTICE "Skipping system clean."
  fi
}

# DNF configuration
configure_dnf() {
  if prompt "Configure DNF package manager?"; then

    local dnf_conf="/etc/dnf/dnf.conf"
    local settings=("max_parallel_downloads=10" "fastestmirror=True")

    # Check dnf file configuration
    for dnf_conf_variable in "${settings[@]}"; do

      if ! grep -q "^${dnf_conf_variable%%=*}" "$dnf_conf" 2>/dev/null; then

        log INFO "Optimizing DNF."

        echo "$dnf_conf_variable" | sudo tee -a "$dnf_conf" >/dev/null &&
          log SUCCESS "Added ${dnf_conf_variable} to DNF config." ||
          {
            log_error "DNF configuration error."
            return 1
          }
      else
        log NOTICE "DNF already configured."
        break
      fi

    done

  else
    log NOTICE "Skipping DNF configuration."
  fi
}

# RPM Fusion repositories
install_rpm_fusion() {

  if prompt "Install third-party repos?"; then

    local repos=(
      "rpmfusion-free-release"
      "rpmfusion-nonfree-release"
    )

    for rpm_install in "${repos[@]}"; do
      if ! rpm -q "$rpm_install" 2>/dev/null; then
        log INFO "Installing RPM Fusion."
        sudo dnf install -y $rpm_install 2>/dev/null ||
          {
            log NOTICE "RPM installation failed."
          }
      else
        log SUCCESS "RPM Fusion already installed."
        break
      fi
    done

  else
    log NOTICE "Skipping RPM Fusion third-party repos installation."
  fi

}

# Multimedia codecs
install_multimedia_codecs() {
  if prompt "Install multimedia codecs?"; then
    local packages=(
      "gstreamer1-plugins-base"
      "gstreamer1-plugins-good"
      "gstreamer1-plugin-openh264"
    )

    local missing=false

    local multimedia_codecs=(
      "gstreamer1-plugins-{good,bad-free,base}"
      "gstreamer1-plugin-openh264"
      "gstreamer1-libav"
    )

    for pkg in "${packages[@]}"; do
      if ! rpm -q "$pkg" >/dev/null 2>&1; then
        missing=true
        break
      fi
    done

    if [[ "$missing" == false ]]; then
      log SUCCESS "Multimedia codecs already installed."
    else
      log INFO "Installing multimedia codecs."
      if run_with_progress "Multimedia codecs: " sudo dnf install -y "${multimedia_codecs[@]}" --exclude=gstreamer1-plugins-bad-free-devel --allowerasing; then
        log SUCCESS "Multimedia codecs installed."
      else
        log WARN "Failed to install Multimedia codecs."
      fi
    fi
  else
    log NOTICE "Skipping multimedia codecs."
  fi
}

# GPU drivers
install_gpu_drivers() {
  if prompt "Install GPU drivers?"; then

    local gpu_info=$(lspci | grep -iE "vga|3d|display")

    #GPU checker
    if [[ -z "$gpu_info" ]]; then
      log WARN "No GPU detected. Ensure GPU is connected."
      return 1
    fi

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
        if sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda; then
          log SUCCESS "NVIDIA drivers installed."
          log WARN "Reboot required for NVIDIA drivers to take effect."
        else
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
  else
    log NOTICE "Skipping GPU optimization."
  fi
}

# Performance optimization
optimize_performance() {
  local disk_type
  local primary_disk

  if prompt "Optimize hard drive performance?"; then
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
        current_scheduler=$(cmd <"$scheduler_path" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')

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
  else
    log NOTICE "Skipping hard drive optimization."
  fi
}

# GNOME Desktop Environment optimization
optimize_gnome() {
  if ! pgrep -x "gnome-shell" >/dev/null 2>&1; then
    log NOTICE "GNOME not detected. Skipping desktop optimization."
    return 0
  fi

  log PROMPT "GNOME desktop environment detected."

  if prompt "Optimize GNOME?"; then
    log INFO "Optimizing GNOME."
    # Disable animations
    gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null &&
      log SUCCESS "GNOME optimized." ||
      log WARN "Failed to disable animations."
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
  log SUCCESS "System optimization successfully."
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
  echo "  • OS: Fedora $(rpm -E %fedora)"
  echo "  • Kernel: linux $(uname -r)"
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

# Main execution
main() {
  show_banner

  check_prerequisites &&
    update_system &&
    configure_dnf &&
    install_rpm_fusion &&
    install_multimedia_codecs &&
    install_gpu_drivers &&
    optimize_performance &&
    optimize_gnome &&
    log SUCCESS "System Optimized." &&
    show_summary || log_error "System optimization error."
}

# Trap errors
trap 'log_error "Script failed at line $LINENO. Check the error above."' ERR

main "$@"
