#!/bin/bash
# install.sh - Main installation script for Media Server
# Version: 2.0.0

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
        cockpit \
        cockpit-docker \
        cockpit-networkmanager \
        cockpit-storaged \
        cockpit-packagekit
    log_success "Essential packages installed"
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

# Configure firewall
configure_firewall() {
    log_info "Configuring firewall..."
    
    # Enable UFW
    sudo ufw --force enable
    
    # Allow SSH
    sudo ufw allow OpenSSH
    
    # Allow HTTP/HTTPS
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    
    # Allow Cockpit
    sudo ufw allow 9090/tcp
    
    # Allow service ports
    sudo ufw allow "${PORTAINER_PORT:-9443}/tcp"
    sudo ufw allow "${HOMARR_PORT:-7575}/tcp"
    sudo ufw allow "${QBITTORRENT_PORT:-8080}/tcp"
    sudo ufw allow "${SONARR_PORT:-8989}/tcp"
    sudo ufw allow "${RADARR_PORT:-7878}/tcp"
    sudo ufw allow "${PROWLARR_PORT:-9696}/tcp"
    sudo ufw allow "${JELLYFIN_PORT:-8096}/tcp"
    
    # Reload firewall
    sudo ufw reload
    
    log_success "Firewall configured"
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
