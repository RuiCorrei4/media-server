#!/bin/bash
# install.sh - Main installation script for Media Server
# Version: 3.1.0 - Added Cockpit GPU metrics support

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Please do not run this script as root"
        log_info "Run as your regular user with sudo privileges"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check available disk space
    available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -lt 20 ]]; then
        log_warning "Less than 20GB free space available (${available_space}GB)"
        log_warning "Media server may require more space for downloads"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check RAM
    total_ram=$(free -g | awk 'NR==2 {print $2}')
    if [[ $total_ram -lt 4 ]]; then
        log_warning "System has ${total_ram}GB RAM (4GB minimum recommended)"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        log_error "No internet connection detected"
        exit 1
    fi
    
    log_success "System requirements check passed"
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    log_success "System packages updated"
}

# Install essential packages
install_packages() {
    log_info "Installing essential packages..."
    
    # Core packages
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git \
        ufw \
        fail2ban \
        htop \
        net-tools \
        wget \
        nano \
        jq \
        openssh-server \
        build-essential \
        dkms \
        gcc \
        make \
        pkg-config \
        linux-headers-$(uname -r) \
        pcp \
        pcp-import-collectl2pcp
    
    log_success "Core packages installed"
}

# Install Cockpit (Fixed for Debian 13)
install_cockpit() {
    log_info "Installing Cockpit..."
    
    # Install cockpit base package
    sudo apt install -y cockpit
    
    # Install cockpit modules
    if sudo apt install -y cockpit-docker 2>/dev/null; then
        log_success "cockpit-docker installed"
    else
        log_warning "cockpit-docker not found, trying alternatives..."
        if sudo apt install -y cockpit-podman 2>/dev/null; then
            log_success "cockpit-podman installed (Docker replacement)"
        else
            log_warning "No Docker module available for Cockpit"
            log_info "You can manage Docker via Portainer instead"
        fi
    fi
    
    sudo apt install -y \
        cockpit-networkmanager \
        cockpit-storaged \
        cockpit-packagekit \
        cockpit-system \
        2>/dev/null || log_warning "Some cockpit modules not available"
    
    log_success "Cockpit installation completed"
}

# Setup Cockpit GPU Metrics
setup_cockpit_gpu_metrics() {
    log_info "Setting up Cockpit GPU metrics..."
    
    # Check if NVIDIA PMDA exists
    if [ -d "/var/lib/pcp/pmdas/nvidia" ]; then
        log_info "Installing NVIDIA PMDA for PCP..."
        cd /var/lib/pcp/pmdas/nvidia
        
        # Install as daemon (default)
        echo "daemon" | sudo ./Install
        
        # Restart PCP services
        sudo systemctl restart pmcd
        
        # Verify NVIDIA metrics are available
        if pminfo nvidia &> /dev/null; then
            log_success "NVIDIA GPU metrics installed successfully!"
            log_info "GPU metrics will appear in Cockpit Performance dashboard"
        else
            log_warning "NVIDIA PMDA installed but metrics not detected"
        fi
        
        cd - > /dev/null
    else
        log_warning "NVIDIA PMDA not found. Installing from source..."
        cd /tmp
        git clone https://github.com/NVIDIA/nvidia-pcp.git
        cd nvidia-pcp
        make
        sudo make install
        
        # Register the PMDA
        echo "daemon" | sudo ./Install || true
        
        sudo systemctl restart pmcd
        cd - > /dev/null
    fi
    
    # Restart Cockpit to detect new metrics
    sudo systemctl restart cockpit
    
    log_success "Cockpit GPU metrics setup complete"
}

# Install NVIDIA Driver for GTX 1050 Ti
install_nvidia_driver() {
    log_info "Installing NVIDIA driver for GTX 1050 Ti..."
    
    # Check if already installed
    if command -v nvidia-smi &> /dev/null; then
        log_warning "NVIDIA driver is already installed:"
        nvidia-smi --query-gpu=driver_version --format=csv,noheader
        return 0
    fi
    
    log_info "Downloading NVIDIA driver 570.86.16..."
    cd ~
    wget -N https://us.download.nvidia.com/XFree86/Linux-x86_64/570.86.16/NVIDIA-Linux-x86_64-570.86.16.run
    chmod +x NVIDIA-Linux-x86_64-570.86.16.run
    
    log_info "Blacklisting nouveau driver (prevents loading on next boot)..."
    sudo bash -c "echo 'blacklist nouveau' > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
    sudo bash -c "echo 'options nouveau modeset=0' >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
    sudo update-initramfs -u
    
    log_info "Checking if nouveau driver is currently loaded in the running kernel..."
    if lsmod | grep -q nouveau; then
        log_warning "Nouveau driver is currently loaded. Attempting to unload it now..."
        
        # Stop any graphical display managers that might hold the GPU
        sudo systemctl stop gdm3 2>/dev/null || true
        sudo systemctl stop lightdm 2>/dev/null || true
        sudo systemctl stop sddm 2>/dev/null || true
        sudo systemctl stop display-manager 2>/dev/null || true
        
        # Try to remove the nouveau module
        if sudo modprobe -r nouveau 2>/dev/null || sudo rmmod nouveau 2>/dev/null; then
            log_success "Nouveau driver unloaded successfully."
        else
            log_error "Failed to unload nouveau driver. It may be in use by another process."
            log_error "Since the blacklist is configured, please reboot your system and re-run this script."
            log_error "After reboot, nouveau will be gone and the installation will proceed cleanly."
            exit 1
        fi
    else
        log_success "Nouveau driver is not loaded."
    fi    
    log_info "Installing NVIDIA driver (this may take a few minutes)..."
    # --no-nouveau-check added as a safety net in case unloading left a trace
    sudo ./NVIDIA-Linux-x86_64-570.86.16.run --dkms --silent --no-x-check --no-nouveau-check
    
    log_success "NVIDIA driver installed successfully!"
    log_warning "A system reboot is required to complete the driver installation."
}

# Install NVIDIA Container Toolkit
install_nvidia_container_toolkit() {
    log_info "Installing NVIDIA Container Toolkit..."
    
    if command -v nvidia-ctk &> /dev/null; then
        log_warning "NVIDIA Container Toolkit already installed."
        return 0
    fi
    
    log_info "Downloading NVIDIA Container Toolkit v1.20.0..."
    cd ~
    wget -N https://github.com/NVIDIA/nvidia-container-toolkit/releases/download/v1.20.0/nvidia-container-toolkit_1.20.0_deb_amd64.tar.gz
    
    log_info "Extracting archive..."
    tar -xzf nvidia-container-toolkit_1.20.0_deb_amd64.tar.gz
    
    DEB_DIR=$(find . -path "*/ubuntu18.04/amd64" -type d | head -1)
    
    if [ -d "$DEB_DIR" ]; then
        cd "$DEB_DIR"
        log_info "Installing NVIDIA Container Toolkit packages..."
        sudo dpkg -i *.deb 2>/dev/null || sudo apt --fix-broken install -y
        cd ~
    else
        log_error "Could not find extracted .deb files. Installing from apt repository..."
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/debian12 /" | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        sudo apt update
        sudo apt install -y nvidia-container-toolkit
    fi
    
    log_info "Configuring NVIDIA Container Runtime for Docker..."
    sudo nvidia-ctk runtime configure --runtime=docker
    
    # Restart Docker
    sudo systemctl restart docker
    
    log_success "NVIDIA Container Toolkit installed and configured."
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        log_warning "Docker is already installed"
        docker --version
    else
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sudo sh /tmp/get-docker.sh
        rm /tmp/get-docker.sh
        
        sudo usermod -aG docker "$USER"
        log_success "Docker installed successfully"
    fi
    
    if command -v docker-compose &> /dev/null; then
        log_warning "Docker Compose is already installed"
        docker-compose --version
    else
        log_info "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        log_success "Docker Compose installed successfully"
    fi
}

# Enable and start Cockpit
setup_cockpit() {
    log_info "Setting up Cockpit..."
    sudo systemctl enable --now cockpit.socket
    sudo systemctl start cockpit
    sudo ufw allow 9090/tcp
    log_success "Cockpit enabled and running"
    log_info "Access Cockpit at: https://$(hostname -I | awk '{print $1}'):9090"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    
    mkdir -p config data downloads media
    mkdir -p data/{torrents,usenet}
    mkdir -p downloads/{complete,incomplete}
    mkdir -p media/{movies,tv,music}
    mkdir -p config/{portainer,homarr,qbittorrent,sonarr,radarr,prowlarr,jellyfin}
    
    chmod -R 755 config data downloads media
    log_success "Directory structure created"
}

# Configure firewall for local access only
configure_firewall() {
    log_info "Configuring firewall for local network access..."
    
    sudo ufw --force enable
    sudo ufw allow OpenSSH
    sudo ufw allow 9090/tcp
    
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    if [[ $LOCAL_IP == 192.168.* ]]; then
        LOCAL_SUBNET="192.168.0.0/16"
    elif [[ $LOCAL_IP == 10.* ]]; then
        LOCAL_SUBNET="10.0.0.0/8"
    elif [[ $LOCAL_IP == 172.* ]]; then
        LOCAL_SUBNET="172.16.0.0/12"
    else
        LOCAL_SUBNET="192.168.1.0/24"
    fi
    
    log_info "Using local subnet: $LOCAL_SUBNET"
    
    # Allow service ports from local network
    for port in 9443 7575 8080 8989 7878 9696 8096 8191; do
        sudo ufw allow from $LOCAL_SUBNET to any port $port proto tcp
    done
    
    sudo ufw reload
    log_success "Firewall configured for local access only"
}

# Setup environment file
setup_env_file() {
    log_info "Setting up environment file..."
    
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            log_warning "Created .env file from template"
        else
            log_info "Creating .env file directly..."
            cat > .env << EOF
# Media Server Environment Configuration
PUID=1000
PGID=1000
TZ=$(timedatectl show --property=Timezone --value)
SERVER_URL=http://$(hostname -I | awk '{print $1}')
PORTAINER_PORT=9443
HOMARR_PORT=7575
QBITTORRENT_PORT=8080
SONARR_PORT=8989
RADARR_PORT=7878
PROWLARR_PORT=9696
FLARESOLVERR_PORT=8191
JELLYFIN_PORT=8096
JELLYFIN_HTTPS_PORT=8920
EOF
        fi
        log_warning "Please review .env file before starting services"
    else
        log_info ".env file already exists"
    fi
}

# Test Docker installation
test_docker() {
    log_info "Testing Docker installation..."
    
    if ! docker info &> /dev/null; then
        log_error "Docker is not running or user not in docker group"
        log_info "Please log out and log back in, then run: docker info"
        exit 1
    fi
    
    if ! docker-compose version &> /dev/null; then
        log_error "Docker Compose is not working"
        exit 1
    fi
    
    log_success "Docker is working correctly"
}

# Test NVIDIA GPU access
test_nvidia_docker() {
    log_info "Testing NVIDIA GPU access in Docker..."
    
    # Check if nvidia-smi works
    if command -v nvidia-smi &> /dev/null; then
        log_info "NVIDIA driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
        log_info "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"
    fi
    
    # Test Docker GPU access
    if docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        log_success "GPU is accessible in Docker containers!"
    else
        log_warning "GPU not accessible in Docker. You may need to reboot or check the runtime."
    fi
}

# Create backup script
create_backup_script() {
    log_info "Creating backup script..."
    
    mkdir -p scripts
    
    cat > scripts/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="../backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="media-server-backup_${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"

tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" \
    docker-compose.yml \
    .env \
    config/ \
    2>/dev/null

find "${BACKUP_DIR}" -type f -name "media-server-backup_*.tar.gz" -mtime +30 -delete

echo "Backup created: ${BACKUP_DIR}/${BACKUP_FILE}"
EOF
    
    chmod +x scripts/backup.sh
    log_success "Backup script created"
}

# Main installation function
main() {
    clear
    echo "========================================="
    echo "   Media Server Installation Script"
    echo "   Version 3.1.0 (Cockpit GPU Metrics)"
    echo "========================================="
    echo
    
    check_root
    check_requirements
    update_system
    install_packages
    install_nvidia_driver
    install_nvidia_container_toolkit
    install_docker
    install_cockpit
    setup_cockpit
    setup_cockpit_gpu_metrics
    create_directories
    configure_firewall
    setup_env_file
    test_docker
    test_nvidia_docker
    create_backup_script
    
    server_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo "========================================="
    echo "   Installation Complete!"
    echo "========================================="
    echo
    log_success "Next steps:"
    echo "1. Reboot your system to complete NVIDIA driver setup:"
    echo "   sudo reboot"
    echo
    echo "2. After reboot, navigate to the media-server directory:"
    echo "   cd ~/media-server"
    echo
    echo "3. Edit .env file with your settings (if needed):"
    echo "   nano .env"
    echo
    echo "4. Start your services:"
    echo "   docker-compose up -d"
    echo
    echo "5. Access your services:"
    echo "   - Cockpit:      https://${server_ip}:9090 (GPU metrics available!)"
    echo "   - Portainer:    https://${server_ip}:9443"
    echo "   - Homarr:       http://${server_ip}:7575"
    echo "   - QBittorrent:  http://${server_ip}:8080 (admin/adminadmin)"
    echo "   - Sonarr:       http://${server_ip}:8989"
    echo "   - Radarr:       http://${server_ip}:7878"
    echo "   - Prowlarr:     http://${server_ip}:9696"
    echo "   - Flaresolverr: http://${server_ip}:8191"
    echo "   - Jellyfin:     http://${server_ip}:8096"
    echo
    echo "6. Configure Prowlarr to use Flaresolverr:"
    echo "   Settings > Indexers > Flaresolverr URL: http://flaresolverr:8191"
    echo
    echo "7. GPU metrics in Cockpit:"
    echo "   Cockpit > Performance dashboard > GPU metrics"
    echo
    log_warning "Important: Log out and log back in for Docker group changes to take effect"
    log_warning "Important: Change default passwords especially for QBittorrent!"
    echo
}

main "$@"
