# SecureKnock: Advanced Port Knocking & Server Protection

A stealthy server security solution that uses port knocking techniques to protect your servers from unauthorized access while providing legitimate users with seamless access to protected services.

[![GitHub license](https://img.shields.io/github/license/ugurakcil/secureknock)](https://github.com/ugurakcil/secureknock/blob/main/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/ugurakcil/secureknock)](https://github.com/ugurakcil/secureknock/stargazers)

## What the

SecureKnock is a high-performance, minimal-overhead port knocking implementation that adds an extra layer of security to your servers. By requiring a specific sequence of connection attempts with a secret authentication flag, it keeps your services invisible to port scanners and potential attackers while allowing authorized users easy access. It is for those looking for simple security solutions for medium-sized teamwork who don't want to deal with proxy/VPN tunneling issues.

**Features:**
- In-memory tracking for high performance with minimal IO operations
- Flagged packet authentication for enhanced security
- Protection against brute force attempts with rate limiting
- Multi-port protection and access control
- Cross-platform clients (Windows, Linux, macOS)
- Easy deployment and configuration

Developed by [Uğur AKÇIL](https://github.com/ugurakcil) | [@datasins](https://instagram.com/datasins)

## How It Works

SecureKnock uses iptables to monitor connection attempts to specific ports. When a client attempts to connect to these ports in the correct sequence while sending a specific authentication flag, SecureKnock temporarily opens access to protected services (like SSH, HTTP, etc.) for that client's IP address.

The system works without modifying your existing firewall rules - it only adds temporary access rules when authorized clients complete the correct knock sequence.

## Prerequisites

- Linux server with iptables
- Bash 4.0 or higher
- Root access for installation
- Already blocked ports in your firewall configuration

## Server Installation

### Step 1: Download the SecureKnock server script

```bash
wget https://raw.githubusercontent.com/ugurakcil/secureknock/main/secureknock.sh
chmod +x secureknock.sh
```

### Step 2: Configure SecureKnock

Edit the script to change the default configuration:

```bash
nano secureknock.sh
```

The main configuration options are at the top of the file:

```bash
# Configuration
KNOCK_PORTS=(7000 8000 9000 6000 5000 4000 3000 2000) # Sequence ports
ALLOWED_PORTS=(22 80 443 8080 8443)  # Ports to open when sequence is completed
FLAG="ChangeThisFlag"  # Special flag for authentication
ACCESS_DURATION=$((8*3600))  # Access duration in seconds (8 hours)
SEQUENCE_TIMEOUT=300   # Knock sequence timeout in seconds (5 minutes)
MAX_REQUESTS=25        # Maximum allowed requests in 15 minutes
BAN_DURATION=86400     # Ban duration in seconds (1 day)
DEBUG=0                # Set to 1 to enable logging
```

**Important Configuration Notes:**
- Change the `FLAG` to a unique secret string
- Modify `KNOCK_PORTS` to your preferred sequence
- Adjust `ALLOWED_PORTS` to include only the services you want to protect
- Set `DEBUG=1` temporarily if you need to troubleshoot

### Step 3: Set up as a System Service

Create a systemd service file:

```bash
sudo nano /etc/systemd/system/secureknock.service
```

Add the following content:

```
[Unit]
Description=SecureKnock Port Knocking Service
After=network.target

[Service]
Type=simple
ExecStart=/path/to/secureknock.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable secureknock
sudo systemctl start secureknock
```

### Step 4: Verify Operation

If you've enabled debug logging (`DEBUG=1`), you can check the logs:

```bash
sudo tail -f /var/log/knocker.log
```

## Client Setup

### Building Clients

The client builder script creates executables for multiple platforms.

#### Requirements for Building:
- Linux or macOS system
- Rust and Cargo installed
- Docker (for Windows builds)
- The Cross tool (will be installed automatically)

#### Step 1: Download the client builder

```bash
wget https://raw.githubusercontent.com/ugurakcil/secureknock/main/client-builder.sh
chmod +x client-builder.sh
```

#### Step 2: Build clients

```bash
./client-builder.sh --flag "YourSecretFlag" \
                   --ports "7000,8000,9000,6000,5000,4000,3000,2000" \
                   --allowed-ports "22,80,443,8080,8443" \
                   --server "your-server-ip-or-domain.com"
```

**Note:** Make sure the configuration matches your server settings exactly!

#### Step 3: Distribute clients

After building, you'll find the compiled clients in the `knocker-binaries` directory:

- `knocker-linux`: For Linux users
- `knocker-windows.exe`: For Windows users
- `knocker-macos`: For macOS users

Distribute these executables to your authorized users.

## Using the Client

Users simply need to:

1. Double-click the executable
2. The client will automatically:
   - Check if they already have access
   - If not, perform the knock sequence
   - Verify successful access
   - Close automatically after completion

The client shows a message confirming when access has been activated for 8 hours.

## Security Recommendations

To maintain optimal security:

1. **Change the Knock Sequence and Flag Regularly**
   - Update both server and client configurations monthly
   - Distribute new clients to authorized users

2. **Use Non-Standard Ports**
   - Avoid commonly scanned ports for your knock sequence
   - Choose random, high-numbered ports (above 10000)

3. **Implement Strong SSH Security**
   - Even with SecureKnock, maintain strong SSH passwords or key-based authentication
   - Consider disabling password authentication entirely

4. **Monitor Logs**
   - Periodically check logs for unusual access patterns
   - Enable `DEBUG=1` during initial setup to confirm everything works as expected

5. **Keep the Flag Secret**
   - Treat the FLAG value like a password
   - Never share it in plain text communications

## Troubleshooting

### Server-side Issues

- **Check if the service is running:**
  ```bash
  sudo systemctl status secureknock
  ```

- **Enable debugging:**
  Set `DEBUG=1` in the script and restart the service:
  ```bash
  sudo systemctl restart secureknock
  ```

- **Verify iptables rules:**
  ```bash
  sudo iptables -L
  ```

### Client-side Issues

- **Connection problems:** Make sure the server domain/IP is correct
- **Access not granted:** Verify the flag and port sequence matches the server
- **Clients won't build:** Make sure Rust and Docker are properly installed

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

For questions and support, please open an issue on GitHub or contact [Uğur AKÇIL](https://github.com/ugurakcil).