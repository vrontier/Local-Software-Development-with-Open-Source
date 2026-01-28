#!/bin/bash
# Fix DNS resolution for stella and venus by adding to /etc/hosts

set -e

HOSTS_FILE="/etc/hosts"
BACKUP_FILE="/etc/hosts.backup.$(date +%Y%m%d_%H%M%S)"

echo "🔧 Fixing DNS resolution for stella.home.arpa and venus.home.arpa"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run with sudo"
    echo "Usage: sudo $0"
    exit 1
fi

# Create backup
echo "📋 Creating backup at $BACKUP_FILE"
cp "$HOSTS_FILE" "$BACKUP_FILE"

# Check if entries already exist
if grep -q "stella.home.arpa" "$HOSTS_FILE" && grep -q "venus.home.arpa" "$HOSTS_FILE"; then
    echo "✅ Entries already exist in $HOSTS_FILE"
    echo ""
    grep -E "(stella|venus)\.home\.arpa" "$HOSTS_FILE"
    exit 0
fi

# Add entries
echo ""
echo "➕ Adding entries to $HOSTS_FILE"
cat >> "$HOSTS_FILE" << EOF

# LLM Servers - Added by fix-dns.sh on $(date)
10.0.0.64	venus.home.arpa venus
10.0.0.81	stella.home.arpa stella
EOF

echo "✅ DNS entries added successfully!"
echo ""
echo "Contents of $HOSTS_FILE:"
cat "$HOSTS_FILE"
echo ""
echo "🧪 Testing resolution..."
ping -c 1 venus.home.arpa > /dev/null 2>&1 && echo "✅ venus.home.arpa resolves!" || echo "❌ venus.home.arpa still not resolving"
ping -c 1 stella.home.arpa > /dev/null 2>&1 && echo "✅ stella.home.arpa resolves!" || echo "❌ stella.home.arpa still not resolving"
echo ""
echo "✨ Done! You can now use venus.home.arpa and stella.home.arpa"
