#!/bin/bash

# Port Knocking Client Builder
# Creates a cross-platform Rust client for port knocking with multi-architecture support

# Default values
FLAG="ChangeThisFlag"
PORTS=(7000 8000 9000 6000 5000 4000 3000 2000)
ALLOWED_PORTS=(22 80 443 8080 8443)  # Should match server configuration
SERVER_IP="111.111.11.11"
BUILD_ARM=0  # Default: don't build ARM targets unless specified
BUILD_LINUX=1
BUILD_WINDOWS=1
BUILD_MACOS=0  # Default: don't build macOS unless on a Mac

# Check and install dependencies
check_dependencies() {
    echo "Checking dependencies..."
    
    # Check if Rust is installed
    if ! command -v rustc &> /dev/null; then
        echo "Rust not found. Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    else
        echo "Rust is already installed."
    fi
    
    # Check if cargo is installed
    if ! command -v cargo &> /dev/null; then
        echo "Cargo not found. Please reinstall Rust."
        exit 1
    else
        echo "Cargo is already installed."
    fi
    
    # Check if cross is installed
    if ! command -v cross &> /dev/null; then
        echo "Cross not found. Installing cross..."
        cargo install cross
    else
        echo "Cross is already installed."
    fi
    
    # Check if Docker is installed (required for cross)
    if ! command -v docker &> /dev/null; then
        echo "Warning: Docker not found. Docker is required for cross-compilation."
        echo "ARM, Windows, and other non-native targets will be skipped."
        BUILD_WINDOWS=0
        BUILD_ARM=0
    else
        echo "Docker is already installed."
        # Test if Docker daemon is running
        if ! docker info &> /dev/null; then
            echo "Warning: Docker daemon is not running. Please start Docker service."
            echo "ARM, Windows, and other non-native targets will be skipped."
            BUILD_WINDOWS=0
            BUILD_ARM=0
        fi
    fi
    
    echo "All dependencies checked."
}

# Add Rust targets
add_rust_targets() {
    echo "Adding required Rust targets..."
    
    # Add x86_64 Windows target
    if [ $BUILD_WINDOWS -eq 1 ]; then
        rustup target add x86_64-pc-windows-gnu
    fi
    
    # Add ARM targets
    if [ $BUILD_ARM -eq 1 ]; then
        rustup target add aarch64-unknown-linux-gnu  # 64-bit ARM (most modern phones/SBCs)
        rustup target add armv7-unknown-linux-gnueabihf  # 32-bit ARM (older devices)
        echo "ARM targets added."
    fi
    
    echo "Target setup completed."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --flag)
      FLAG="$2"
      shift 2
      ;;
    --ports)
      IFS=',' read -ra PORTS <<< "$2"
      shift 2
      ;;
    --allowed-ports)
      IFS=',' read -ra ALLOWED_PORTS <<< "$2"
      shift 2
      ;;
    --server)
      SERVER_IP="$2"
      shift 2
      ;;
    --build-arm)
      BUILD_ARM=1
      shift
      ;;
    --no-windows)
      BUILD_WINDOWS=0
      shift
      ;;
    --no-linux)
      BUILD_LINUX=0
      shift
      ;;
    --build-all)
      BUILD_ARM=1
      BUILD_LINUX=1
      BUILD_WINDOWS=1
      if [[ "$OSTYPE" == "darwin"* ]]; then
        BUILD_MACOS=1
      fi
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --flag FLAG                   Set the authentication flag"
      echo "  --ports P1,P2,...             Set the knock port sequence"
      echo "  --allowed-ports P1,P2,...     Set the allowed ports to check for access"
      echo "  --server SERVER_IP            Set the server IP or hostname"
      echo "  --build-arm                   Build for ARM architectures (for Android/Raspberry Pi)"
      echo "  --no-windows                  Skip Windows build"
      echo "  --no-linux                    Skip Linux build (x86_64)"
      echo "  --build-all                   Build for all supported platforms"
      echo "  --help                        Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo "Port Knocking Client Builder"
echo "==========================="
echo "This script will build a port knocking client for multiple platforms."
echo ""
echo "Configuration:"
echo "Flag: $FLAG"
echo "Knock Ports: ${PORTS[*]}"
echo "Allowed Ports: ${ALLOWED_PORTS[*]}"
echo "Server: $SERVER_IP"
echo ""
echo "Target Platforms:"
if [ $BUILD_LINUX -eq 1 ]; then echo "- Linux (x86_64)"; fi
if [ $BUILD_WINDOWS -eq 1 ]; then echo "- Windows (x86_64)"; fi
if [ $BUILD_ARM -eq 1 ]; then 
  echo "- ARM 64-bit (aarch64) for modern Android/Raspberry Pi"
  echo "- ARM 32-bit (armv7) for older devices"
fi
if [ $BUILD_MACOS -eq 1 ]; then echo "- macOS"; fi
echo ""

# Check dependencies
check_dependencies

# Add required Rust targets
add_rust_targets

# Generate Rust project
mkdir -p knocker-client
cd knocker-client
cargo init --bin

# Generate Rust source code with parameters
cat > src/main.rs << EOF
use std::io::{self, Write};
use std::net::TcpStream;
use std::time::Duration;
use std::thread;

const FLAG: &str = "$FLAG";
const PORTS: [u16; ${#PORTS[@]}] = [$(IFS=,; echo "${PORTS[*]}")];
const SERVER_IP: &str = "$SERVER_IP";
const ALLOWED_PORTS: [u16; ${#ALLOWED_PORTS[@]}] = [$(IFS=,; echo "${ALLOWED_PORTS[*]}")]; // Ports to check for access

fn main() {
    println!("Port Knocking Client");
    println!("--------------------");
    println!("Checking connection to server: {}", SERVER_IP);
    
    // Check if we already have access by trying all ports
    let mut has_access = false;
    for port in ALLOWED_PORTS.iter() {
        match TcpStream::connect_timeout(
            &format!("{}:{}", SERVER_IP, port).parse().unwrap(),
            Duration::from_secs(3)
        ) {
            Ok(_) => {
                has_access = true;
                println!("You already have access to port {} on the server.", port);
                break;
            },
            Err(_) => {}
        }
    }
    
    if has_access {
        println!("No need to send a new knock sequence.");
        println!("\nThis window will close in 5 seconds...");
        thread::sleep(Duration::from_secs(5));
        return;
    } else {
        println!("No active connection. Starting knock sequence...");
    }
    
    // Perform knocking sequence
    for (i, port) in PORTS.iter().enumerate() {
        print!("Knocking on port {} ({}/{})... ", port, i+1, PORTS.len());
        io::stdout().flush().unwrap();
        
        match TcpStream::connect_timeout(
            &format!("{}:{}", SERVER_IP, port).parse().unwrap(),
            Duration::from_secs(2)
        ) {
            Ok(mut stream) => {
                // Send the FLAG for authentication
                stream.write_all(FLAG.as_bytes()).unwrap_or_else(|_| {
                    // Ignore write errors, connection itself is enough
                });
                println!("Done");
            },
            Err(_) => {
                // Expected behavior for closed ports
                println!("Done (port closed)");
            }
        }
        
        // Wait between knocks
        thread::sleep(Duration::from_millis(500));
    }
    
    println!("\nPort knocking sequence completed!");
    println!("Access to server ports has been activated for 8 hours.");
    
    // Wait a moment, then verify access
    println!("\nVerifying access...");
    thread::sleep(Duration::from_secs(2));
    
    let mut verified = false;
    for port in ALLOWED_PORTS.iter() {
        match TcpStream::connect_timeout(
            &format!("{}:{}", SERVER_IP, port).parse().unwrap(),
            Duration::from_secs(3)
        ) {
            Ok(_) => {
                println!("Access to port {} verified successfully!", port);
                verified = true;
                break;
            },
            Err(_) => {}
        }
    }
    
    if !verified {
        println!("Warning: Could not verify access to any port. You may need to try again.");
    }
    
    // Keep the window open for a few seconds
    println!("\nThis window will close in 5 seconds...");
    thread::sleep(Duration::from_secs(5));
}
EOF

# Update Cargo.toml to include dependencies
cat > Cargo.toml << EOF
[package]
name = "knocker-client"
version = "0.1.0"
edition = "2021"

[dependencies]

[profile.release]
opt-level = 3
strip = true
lto = true
codegen-units = 1
panic = 'abort'
EOF

# Create output directory
mkdir -p ../knocker-binaries

# Build for each target platform
echo "Building port knocking client for selected platforms..."

# Linux (x86_64)
if [ $BUILD_LINUX -eq 1 ]; then
    echo "Building for Linux (x86_64)..."
    cargo build --release
    
    if [ -f "target/release/knocker-client" ]; then
        cp target/release/knocker-client ../knocker-binaries/knocker-linux-x86_64
        echo "Linux (x86_64) binary created: knocker-binaries/knocker-linux-x86_64"
    fi
fi

# Windows (x86_64)
if [ $BUILD_WINDOWS -eq 1 ]; then
    echo "Building for Windows..."
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        cross build --release --target x86_64-pc-windows-gnu
        
        if [ -f "target/x86_64-pc-windows-gnu/release/knocker-client.exe" ]; then
            cp target/x86_64-pc-windows-gnu/release/knocker-client.exe ../knocker-binaries/knocker-windows-x86_64.exe
            echo "Windows binary created: knocker-binaries/knocker-windows-x86_64.exe"
        fi
    else
        echo "Skipping Windows build (Docker not available or not running)"
    fi
fi

# ARM 64-bit (aarch64)
if [ $BUILD_ARM -eq 1 ]; then
    echo "Building for ARM 64-bit (aarch64)..."
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        cross build --release --target aarch64-unknown-linux-gnu
        
        if [ -f "target/aarch64-unknown-linux-gnu/release/knocker-client" ]; then
            cp target/aarch64-unknown-linux-gnu/release/knocker-client ../knocker-binaries/knocker-linux-aarch64
            echo "ARM 64-bit binary created: knocker-binaries/knocker-linux-aarch64"
        fi
        
        # ARM 32-bit (armv7)
        echo "Building for ARM 32-bit (armv7)..."
        cross build --release --target armv7-unknown-linux-gnueabihf
        
        if [ -f "target/armv7-unknown-linux-gnueabihf/release/knocker-client" ]; then
            cp target/armv7-unknown-linux-gnueabihf/release/knocker-client ../knocker-binaries/knocker-linux-armv7
            echo "ARM 32-bit binary created: knocker-binaries/knocker-linux-armv7"
        fi
    else
        echo "Skipping ARM builds (Docker not available or not running)"
    fi
fi

# macOS (when running on macOS)
if [ $BUILD_MACOS -eq 1 ] && [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Building for macOS..."
    cargo build --release
    
    if [ -f "target/release/knocker-client" ]; then
        cp target/release/knocker-client ../knocker-binaries/knocker-macos
        echo "macOS binary created: knocker-binaries/knocker-macos"
    fi
fi

# Generate a simple bash client for Termux (Android) and other environments
cat > ../knocker-binaries/knocker-bash.sh << EOF
#!/bin/bash

# SecureKnock - Simple Bash Client
# For use in Termux (Android) and other environments

# Configuration (same as compiled clients)
SERVER="$SERVER_IP"
FLAG="$FLAG"
PORTS=($(IFS=" "; echo "${PORTS[*]}"))
ALLOWED_PORTS=($(IFS=" "; echo "${ALLOWED_PORTS[*]}"))

# Check if netcat is installed
if ! command -v nc &> /dev/null; then
    echo "Error: netcat (nc) is not installed."
    echo "Please install it with: pkg install netcat-openbsd (Termux)"
    echo "or: apt install netcat (Debian/Ubuntu)"
    exit 1
fi

# Check if we already have access
echo "Port Knocking Client (Bash version)"
echo "------------------------------------"
echo "Checking connection to server: \$SERVER"

HAS_ACCESS=0
for PORT in "\${ALLOWED_PORTS[@]}"; do
    if nc -z -w 3 \$SERVER \$PORT 2>/dev/null; then
        echo "You already have access to port \$PORT on the server."
        HAS_ACCESS=1
        break
    fi
done

if [ \$HAS_ACCESS -eq 1 ]; then
    echo "No need to send a new knock sequence."
    echo "Press Enter to exit..."
    read
    exit 0
else
    echo "No active connection. Starting knock sequence..."
fi

# Perform knocking sequence
TOTAL=\${#PORTS[@]}
COUNT=1
for PORT in "\${PORTS[@]}"; do
    echo "Knocking on port \$PORT (\$COUNT/\$TOTAL)..."
    echo -n "\$FLAG" | nc -w 1 \$SERVER \$PORT 2>/dev/null
    COUNT=\$((COUNT + 1))
    sleep 1
done

echo
echo "Port knocking sequence completed!"
echo "Access to server ports has been activated for 8 hours."

# Verify access
echo
echo "Verifying access..."
sleep 2

VERIFIED=0
for PORT in "\${ALLOWED_PORTS[@]}"; do
    if nc -z -w 3 \$SERVER \$PORT 2>/dev/null; then
        echo "Access to port \$PORT verified successfully!"
        VERIFIED=1
        break
    fi
done

if [ \$VERIFIED -eq 0 ]; then
    echo "Warning: Could not verify access to any port. You may need to try again."
fi

echo
echo "Press Enter to exit..."
read
EOF

chmod +x ../knocker-binaries/knocker-bash.sh
echo "Bash script client created: knocker-binaries/knocker-bash.sh"

echo
echo "Build completed!"
echo "Executables can be found in knocker-binaries/ directory"
echo
echo "For Android (Termux) users, use the knocker-bash.sh script or knocker-linux-aarch64 binary."