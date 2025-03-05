#!/bin/bash

# SecureKnock | Advanced Port Knocking & Server Protection
# Uses in-memory tracking and minimal IO operations

# Configuration
KNOCK_PORTS=(7000 8000 9000 6000 5000 4000 3000 2000) # Change ports
ALLOWED_PORTS=(22 80 443 8080 8443)  # Ports to open when knock sequence is completed
FLAG="ChangeThisFlag"  # Special flag for all knocks
ACCESS_DURATION=$((8*3600))   # Access duration in seconds (8 hours)
SEQUENCE_TIMEOUT=300   # Knock sequence timeout in seconds (5 minutes)
MAX_REQUESTS=25        # Maximum allowed requests in 15 minutes
BAN_DURATION=86400     # Ban duration in seconds (1 day)
DEBUG=0                # Set to 1 to enable logging

# Log file - only used when DEBUG=1
LOG_FILE="/var/log/knocker.log"

# In-memory tracking using associative arrays
declare -A ip_sequence      # Track sequence position for each IP
declare -A ip_last_time     # Track last request time for each IP
declare -A ip_request_count # Track request count for each IP
declare -A ip_first_time    # Track first request time in the period

# Conditional logging
log_message() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    fi
}

# Open ports for specific IP
# Adds temporary rules to allow access to specified ports
open_ports() {
    local ip=$1

    # Add temporary allow rules for all allowed ports
    for port in "${ALLOWED_PORTS[@]}"; do
        iptables -I INPUT -p tcp --dport $port -s $ip -j ACCEPT
    done

    # Reset tracking for this IP
    ip_sequence[$ip]=0
    ip_request_count[$ip]=0

    # Schedule closing after duration period
    (
        sleep $ACCESS_DURATION
        for port in "${ALLOWED_PORTS[@]}"; do
            iptables -D INPUT -p tcp --dport $port -s $ip -j ACCEPT 2>/dev/null
        done
    ) &

    log_message "Opened ports ${ALLOWED_PORTS[*]} for IP $ip (for 8 hours)"
}

# Ban an IP address
ban_ip() {
    local ip=$1
    log_message "Banning IP $ip for 24 hours due to excessive requests"
    
    # Remove any existing allow rules
    for port in "${ALLOWED_PORTS[@]}"; do
        iptables -D INPUT -p tcp --dport $port -s $ip -j ACCEPT 2>/dev/null
    done
    
    # Add drop rule
    if ! iptables -C INPUT -s $ip -j DROP 2>/dev/null; then
        iptables -I INPUT -s $ip -j DROP
        
        # Reset tracking for this IP
        ip_sequence[$ip]=0
        ip_request_count[$ip]=0
        
        # Schedule unban after ban duration
        (
            sleep $BAN_DURATION
            iptables -D INPUT -s $ip -j DROP 2>/dev/null
            log_message "Ban expired for IP $ip"
        ) &
    fi
}

# Check if IP is banned
is_ip_banned() {
    local ip=$1
    
    # Check iptables for DROP rule
    if iptables -C INPUT -s $ip -j DROP 2>/dev/null; then
        return 0  # IP is banned
    fi
    
    return 1  # IP is not banned
}

# Process knock with in-memory tracking
process_knock() {
    local ip=$1
    local port=$2
    local current_time=$(date +%s)

    # Skip if IP is banned
    if is_ip_banned "$ip"; then
        return
    fi
    
    # Initialize tracking if first request from this IP
    if [ -z "${ip_first_time[$ip]}" ]; then
        ip_first_time[$ip]=$current_time
        ip_request_count[$ip]=1
        ip_sequence[$ip]=0
    else
        # Increment request counter
        ip_request_count[$ip]=$((ip_request_count[$ip] + 1))
        
        # Check if we need to reset the counter (15 minutes passed)
        if [ $((current_time - ip_first_time[$ip])) -gt 900 ]; then
            ip_first_time[$ip]=$current_time
            ip_request_count[$ip]=1
        fi
        
        # Check if rate limit exceeded
        if [ ${ip_request_count[$ip]} -gt $MAX_REQUESTS ]; then
            ban_ip "$ip"
            return
        fi
    fi
    
    # Store last request time
    ip_last_time[$ip]=$current_time
    
    # Handle first port in sequence
    if [ $port -eq ${KNOCK_PORTS[0]} ]; then
        ip_sequence[$ip]=1
        log_message "New sequence for IP $ip (port: $port)"
        return
    fi
    
    # No sequence started
    if [ -z "${ip_sequence[$ip]}" ] || [ ${ip_sequence[$ip]} -eq 0 ]; then
        log_message "Invalid knock sequence from IP $ip (sequence not started)"
        return
    fi
    
    # Check for sequence timeout
    if [ $((current_time - ip_last_time[$ip])) -gt $SEQUENCE_TIMEOUT ]; then
        ip_sequence[$ip]=0
        log_message "Sequence timeout for IP $ip"
        return
    fi
    
    # Calculate expected next port
    local next_step=$((ip_sequence[$ip] + 1))
    local expected_port=${KNOCK_PORTS[$((next_step - 1))]}
    
    # Verify correct sequence
    if [ $port -eq $expected_port ]; then
        ip_sequence[$ip]=$next_step
        log_message "Correct knock from IP $ip: step $next_step / ${#KNOCK_PORTS[@]}"
        
        # Check if sequence completed
        if [ $next_step -eq ${#KNOCK_PORTS[@]} ]; then
            log_message "Sequence completed for IP $ip!"
            open_ports "$ip"
        fi
    else
        # Wrong port - reset sequence
        ip_sequence[$ip]=0
        log_message "Invalid sequence from IP $ip (expected: $expected_port, got: $port)"
    fi
}

# Set up knock monitoring
setup_knock_monitoring() {
    log_message "Starting in-memory port knock monitoring"

    # Set up iptables rules for flagged knocks only
    for port in "${KNOCK_PORTS[@]}"; do
        # Only create the rule if it doesn't already exist
        if ! iptables -C INPUT -p tcp --dport $port -m string --string "$FLAG" --algo bm -j LOG --log-prefix "FLAGGED_KNOCK:" --log-level 4 2>/dev/null; then
            iptables -A INPUT -p tcp --dport $port -m string --string "$FLAG" --algo bm -j LOG --log-prefix "FLAGGED_KNOCK:" --log-level 4
        fi
    done

    # Periodically clean up tracking for inactive IPs (every 15 minutes)
    (
        while true; do
            current_time=$(date +%s)
            
            # Loop through all tracked IPs
            for ip in "${!ip_last_time[@]}"; do
                # Remove tracking data for IPs inactive for more than 15 minutes
                if [ $((current_time - ip_last_time[$ip])) -gt 900 ]; then
                    unset ip_sequence[$ip]
                    unset ip_last_time[$ip]
                    unset ip_request_count[$ip]
                    unset ip_first_time[$ip]
                fi
            done
            
            sleep 900
        done
    ) &

    # Monitor kernel logs for flagged knocks only
    tail -n0 -F /var/log/kern.log | grep --line-buffered "FLAGGED_KNOCK:" | while read line; do
        # Extract IP and port
        ip=$(echo "$line" | grep -oP 'SRC=\K[0-9.]+')
        port=$(echo "$line" | grep -oP 'DPT=\K[0-9]+')

        # Process the knock
        process_knock "$ip" "$port"
    done
}

# Trap for graceful shutdown
cleanup() {
    log_message "Shutting down port knocking service"
    kill $(jobs -p) 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

# Main function
main() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "Starting Minimal Port Knocking System" > "$LOG_FILE"
    fi

    # Start knock monitoring
    setup_knock_monitoring
}

# Start the script
main