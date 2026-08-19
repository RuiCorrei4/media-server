#!/bin/bash
# install.sh - Main installation script for Media Server
# Version: 2.1.0 - Fixed cockpit package names for Debian 13

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
        openssh-server
    
    log_success "Core packages installed"
}

# Install Cockpit (Fixed for Debian 13)
install_cockpit() {
    log_info "Installing Cockpit..."
    
    # Install cockpit base package
    sudo apt install -y cockpit
    
    # Install cockpit modules (correct package names for Debian 13)
    # cockpit-docker is now included in cockpit-podman or cockpit itself
    # For Docker management, we need cockpit-docker which might be named differently
    
    # Try to install cockpit-docker, if it fails, try alternatives
    if sudo apt install -y cockpit-docker 2>/dev/null; then
        log_success "cockpit-docker installed"
    else
        log_warning "cockpit-docker not found, trying alternatives..."
        
        # Try cockpit-podman (replacement for docker module)
        if sudo apt install -y cockpit-podman 2>/dev/null; then
            log_success "cockpit-podman installed (Docker replacement)"
        else
            log_warning "No Docker module available for Cockpit"
            log_info "You can manage Docker via Portainer instead"
        fi
    fi
    
    # Install other cockpit modules
    sudo apt install -y \
        cockpit-networkmanager \
        cockpit-storaged \
        cockpit-packagekit \
        cockpit-system \
        2>/dev/null || log_warning "Some cockpit modules not available"
    
    log_success "Cockpit installation completed"
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
        
        # Add user to docker group
        sudo usermod -aG docker "$USER"
        log_success "Docker installed successfully"
    fi
    
    # Install Docker Compose
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
    
    # Enable Cockpit service
    sudo systemctl enable --now cockpit.socket
    sudo systemctl start cockpit
    
    # Allow Cockpit through firewall
    sudo ufw allow 9090/tcp
    
    log_success "Cockpit enabled and running"
    log_info "Access Cockpit at: https://$(hostname -I | awk '{print $1}'):9090"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    
    # Base directories
    mkdir -p config data downloads media
    mkdir -p data/{torrents,usenet}
    mkdir -p downloads/{complete,incomplete}
    mkdir -p media/{movies,tv,music}
    
    # Config directories for each service
    mkdir -p config/{portainer,homarr,qbittorrent,sonarr,radarr,prowlarr,jellyfin}
    
    # Set proper permissions
    chmod -R 755 config data downloads media
    
    log_success "Directory structure created"
}

# Configure firewall for local access only
configure_firewall() {
    log_info "Configuring firewall for local network access..."
    
    # Enable UFW
    sudo ufw --force enable
    
    # Allow SSH
    sudo ufw allow OpenSSH
    
    # Allow Cockpit
    sudo ufw allow 9090/tcp
    
    # Allow services on local network only
    # Get local network subnet
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
    sudo ufw allow from $LOCAL_SUBNET to any port 9443 proto tcp
    sudo ufw allow from $LOCAL_SUBNET to any port 7575 proto tcp
    sudo ufw allow from $LOCAL_SUBNET to any port 8080 proto tcp
    sudo ufw allow from $LOCAL_SUBNET to any port 8989 proto tcp
    sudo ufw allow from $LOCAL_SUBNET to any port 7878 proto tcp
    sudo ufw allow from $LOCAL_SUBNET to any port 9696 proto tcp
    sudo ufw allow from $LOCAL_SUBNET to any port 8096 proto tcp
    
    # Reload firewall
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
            log_warning "Please edit .env with your settings before starting services"
        else
            log_error ".env.example not found"
            exit 1
        fi
    else
        log_info ".env file already exists"
    fi
}

# Test Docker installation
test_docker() {
    log_info "Testing Docker installation..."
    
    # Test Docker
    if ! docker info &> /dev/null; then
        log_error "Docker is not running or user not in docker group"
        log_info "Please log out and log back in, then run: docker info"
        exit 1
    fi
    
    # Test Docker Compose
    if ! docker-compose version &> /dev/null; then
        log_error "Docker Compose is not working"
        exit 1
    fi
    
    log_success "Docker is working correctly"
}

# Create backup script
create_backup_script() {
    log_info "Creating backup script..."
    
    cat > scripts/backup.sh << 'EOF'
#!/bin/bash
# backup.sh - Backup script for Media Server configurations

BACKUP_DIR="../backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="media-server-backup_${TIMESTAMP}.tar.gz"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Backup configuration files and docker-compose.yml
tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" \
    docker-compose.yml \
    .env \
    config/ \
    2>/dev/null

# Remove backups older than 30 days
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
    echo "========================================="
    echo
    
    # Run installation steps
    check_root
    check_requirements
    update_system
    install_packages
    install_cockpit
    install_docker
    setup_cockpit
    create_directories
    configure_firewall
    setup_env_file
    test_docker
    create_backup_script
    
    # Get server IP
    server_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo "========================================="
    echo "   Installation Complete!"
    echo "========================================="
    echo
    log_success "Next steps:"
    echo "1. Edit .env file with your settings:"
    echo "   nano .env"
    echo
    echo "2. (Optional) Setup SSH key authentication:"
    echo "   ./scripts/setup-ssh.sh"
    echo
    echo "3. Start your services:"
    echo "   docker-compose up -d"
    echo
    echo "4. Access your services:"
    echo "   - Cockpit: https://${server_ip}:9090"
    echo "   - Portainer: https://${server_ip}:9443"
    echo "   - Homarr: http://${server_ip}:7575"
    echo "   - QBittorrent: http://${server_ip}:8080"
    echo "   - Sonarr: http://${server_ip}:8989"
    echo "   - Radarr: http://${server_ip}:7878"
    echo "   - Prowlarr: http://${server_ip}:9696"
    echo "   - Jellyfin: http://${server_ip}:8096"
    echo
    log_warning "Important: Log out and log back in for Docker group changes to take effect"
    echo
}

# Run main function
main "$@"
