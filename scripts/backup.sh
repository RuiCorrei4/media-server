#!/bin/bash
# backup.sh - Backup script for Media Server configurations

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BACKUP_DIR="../backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="media-server-backup_${TIMESTAMP}.tar.gz"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Backup configuration files
echo -e "${YELLOW}Creating backup...${NC}"

tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" \
    docker-compose.yml \
    .env \
    config/ \
    scripts/ \
    2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Backup created: ${BACKUP_DIR}/${BACKUP_FILE}${NC}"
    
    # Remove backups older than 30 days
    find "${BACKUP_DIR}" -type f -name "media-server-backup_*.tar.gz" -mtime +30 -delete
    echo -e "${GREEN}Old backups cleaned up${NC}"
else
    echo -e "${RED}Backup failed${NC}"
    exit 1
fi

# Optional: Copy backup to remote location
# rsync -av "${BACKUP_DIR}/${BACKUP_FILE}" user@remote-server:/path/to/backups/
