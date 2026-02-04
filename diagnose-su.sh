#!/bin/bash
#
# Diagnostic script for slow 'su - openclaw' issue
# Run this on your Linux VPS to identify the cause
#

echo "╶════════════════════════════════════════════════════════════════════════════"
echo "  Diagnosing slow 'su - openclaw' issue"
echo "╶════════════════════════════════════════════════════════════════════════════"
echo ""

# 1. Time the actual su command
echo "1. Timing the su command (this will take a moment)..."
echo "   Running: time su - openclaw -c 'echo Success'"
echo ""
time su - openclaw -c "echo 'Success'" 2>&1 || echo "(If this failed, try with sudo)"
echo ""

# 2. Check PAM configuration
echo "2. Checking PAM configuration for su..."
echo "   Looking for pam_systemd.so (common cause of slow su)..."
echo ""
grep -E "pam_systemd|session.*required|session.*optional" /etc/pam.d/su 2>/dev/null || echo "Could not read /etc/pam.d/su"
echo ""

# 3. Check DNS resolution
echo "3. Checking DNS configuration..."
echo "   Contents of /etc/resolv.conf:"
cat /etc/resolv.conf
echo ""

# 4. Check NSSwitch configuration
echo "4. Checking NSSwitch (can cause slow lookups)..."
echo "   Relevant lines from /etc/nsswitch.conf:"
grep -E "^passwd|^group|^hosts" /etc/nsswitch.conf 2>/dev/null || echo "Could not read /etc/nsswitch.conf"
echo ""

# 5. Check openclaw's .bashrc size
echo "5. Checking openclaw's shell startup files..."
if [ -d /home/openclaw ]; then
    echo "   .bashrc: $(wc -l < /home/openclaw/.bashrc 2>/dev/null || echo '0') lines"
    echo "   .profile: $(wc -l < /home/openclaw/.profile 2>/dev/null || echo '0') lines"
    echo ""
    echo "   First 20 lines of .bashrc (looking for slow commands):"
    head -20 /home/openclaw/.bashrc 2>/dev/null | grep -n "^[^#]" || echo "   No non-commented lines in first 20"
else
    echo "   /home/openclaw not found"
fi
echo ""

# 6. Check systemd journal for errors
echo "6. Checking systemd journal for recent errors..."
echo "   Recent error logs (pam/systemd related):"
journalctl -xe --no-pager 2>/dev/null | grep -iE "error|fail" | grep -iE "pam|systemd|user.*openclaw" | tail -5 || echo "   No errors found or journalctl failed"
echo ""

# 7. Check user lingering status
echo "7. Checking systemd user lingering..."
if command -v loginctl >/dev/null 2>&1; then
    loginctl show-user openclaw 2>/dev/null || echo "   openclaw not found in loginctl"
    echo ""
    echo "   Linger status:"
    loginctl list-sessions 2>/dev/null | grep openclaw || echo "   No active sessions for openclaw"
else
    echo "   loginctl not found"
fi
echo ""

# 8. Quick test - bash without loading .bashrc
echo "8. Quick test - bash --noprofile (skips .bashrc/.profile)..."
echo "   Running: time su - openclaw -c 'bash --noprofile --norc -c echo'"
time su - openclaw -c 'bash --noprofile --norc -c echo' 2>&1 || echo "   Test failed"
echo ""

# 9. Suggest fix
echo "╶════════════════════════════════════════════════════════════════════════════"
echo "  SUMMARY & SUGGESTIONS"
echo "╶════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Compare the times from steps 1 and 8:"
echo "  - If step 8 is much faster → .bashrc/.profile is the problem"
echo "  - If both are slow → PAM or systemd is the problem"
echo ""
echo "Common fixes:"
echo ""
echo "1. If PAM/systemd is slow, edit /etc/pam.d/su and comment out:"
echo "   # session   optional   pam_systemd.so"
echo ""
echo "2. Use sudo instead (faster, openclaw has passwordless sudo):"
echo "   sudo -u openclaw -i"
echo ""
echo "3. If .bashrc is the issue, move slow commands to background or remove them"
echo ""
