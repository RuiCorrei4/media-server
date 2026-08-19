# Home Media Server Setup

A complete home media server solution with automated downloads, media management, and streaming capabilities. Includes web-based server management via Cockpit.

## 🚀 Features

### Media Services
- **Jellyfin** - Media streaming server
- **Sonarr/Radarr** - Automated TV show and movie downloading
- **Prowlarr** - Indexer management
- **QBittorrent** - Torrent client with VPN protection
- **Homarr** - Beautiful dashboard
- **LunaSea** - Mobile app for remote management

### Server Management
- **Cockpit** - Web-based server administration
- **Portainer** - Docker container management
- **SSH** - Secure remote access
- **Firewall** - UFW pre-configured

## 📋 Prerequisites

- Debian 13 (or any Debian-based Linux distribution)
- Minimum 4GB RAM (8GB recommended)
- At least 100GB storage for media
- Internet connection
- Optional: VPN subscription for anonymous downloading

## 🛠️ Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/RuiCorrei4/media-server.git
cd media-server****

chmod +x scripts/*.sh

./scripts/install.sh
