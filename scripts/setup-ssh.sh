#!/bin/bash
# setup-ssh.sh - SSH Configuration Script for Media Server
# Version: 1.0.0

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Configure SSH
configure_ssh() {
    log_info "Configuring SSH..."
    
    # Backup original SSH config
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Configure SSH settings
    sudo tee /etc/ssh/sshd_config.d/media-server.conf << EOF
# Media Server SSH Configuration
Port 22
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers $USER
EOF
    
    # Restart SSH service
    sudo systemctl restart sshd
    
    log_success "SSH configured successfully"
}

# Generate SSH key pair
generate_ssh_keys() {
    log_info "Setting up SSH keys..."
    
    # Create .ssh directory
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    # Generate SSH key if it doesn't exist
    if [[ ! -f ~/.ssh/id_ed25519 ]]; then
        log_info "Generating SSH key pair..."
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "$USER@$(hostname)"
        log_success "SSH key pair generated"
    else
        log_info "SSH key already exists"
    fi
    
    # Add public key to authorized_keys
    cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    
    log_success "SSH keys configured"
}

# Create SSH config file for easy access
create_ssh_config() {
    log_info "Creating SSH client config..."
    
    cat > ~/.ssh/config << EOF
Host media-server
    HostName $(hostname -I | awk '{print $1}')
    User $USER
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 3
    Compression yes
EOF
    
    chmod 600 ~/.ssh/config
    log_success "SSH client config created"
    log_info "You can now connect using: ssh media-server"
}

# Setup fail2ban for SSH
setup_fail2ban() {
    log_info "Configuring fail2ban for SSH..."
    
    # Install fail2ban if not already installed
    if ! command -v fail2ban-client &> /dev/null; then
        sudo apt install -y fail2ban
    fi
    
    # Create jail.local
    sudo tee /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
EOF
    
    # Restart fail2ban
    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban
    
    log_success "fail2ban configured"
}

# Create SSH helper scripts
create_ssh_helpers() {
    log_info "Creating SSH helper scripts..."
    
    # Create SSH status script
    cat > scripts/ssh-status.sh << 'EOF'
#!/bin/bash
# ssh-status.sh - Check SSH connection status

echo "SSH Service Status:"
sudo systemctl status sshd --no-pager

echo -e "\nActive SSH Connections:"
who

echo -e "\nFailed Login Attempts:"
sudo journalctl -u sshd --since "1 hour ago" | grep "Failed password" | tail -5

echo -e "\nFail2ban Status:"
sudo fail2ban-client status sshd

echo -e "\nServer IP Address:"
hostname -I | awk '{print $1}'
EOF
    
    chmod +x scripts/ssh-status.sh
    
    # Create SSH tunnel script
    cat > scripts/ssh-tunnel.sh << 'EOF'
#!/bin/bash
# ssh-tunnel.sh - Create SSH tunnel for remote access

LOCAL_PORT=${1:-8096}
REMOTE_HOST="localhost"
REMOTE_PORT=${2:-8096}
SSH_HOST="media-server"

echo "Creating SSH tunnel:"
echo "Local: localhost:${LOCAL_PORT}"
echo "Remote: ${REMOTE_HOST}:${REMOTE_PORT}"
echo "SSH Host: ${SSH_HOST}"
echo ""
echo "Press Ctrl+C to stop the tunnel"

ssh -N -L ${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT} ${SSH_HOST}
EOF
    
    chmod +x scripts/ssh-tunnel.sh
    
    log_success "SSH helper scripts created"
}

# Display SSH key for copying
display_ssh_key() {
    log_info "Your SSH public key:"
    echo "----------------------------------------"
    cat ~/.ssh/id_ed25519.pub
    echo "----------------------------------------"
    echo
    log_info "Copy this key to your client machines for passwordless access"
}

# Main function
main() {
    clear
    echo "========================================="
    echo "   SSH Setup for Media Server"
    echo "========================================="
    echo
    
    check_root
    configure_ssh
    generate_ssh_keys
    create_ssh_config
    setup_fail2ban
    create_ssh_helpers
    display_ssh_key
    
    echo
    log_success "SSH setup complete!"
    echo
    echo "To connect to your server:"
    echo "  ssh media-server"
    echo
    echo "To check SSH status:"
    echo "  ./scripts/ssh-status.sh"
    echo
    echo "To create SSH tunnel:"
    echo "  ./scripts/ssh-tunnel.sh [local_port] [remote_port]"
    echo
}

# Run main function
main "$@"
