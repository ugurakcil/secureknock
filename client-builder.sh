#!/bin/bash

# Port Knocking Client Builder
# Creates a cross-platform Rust client for port knocking

# Default values
FLAG="ChangeThisFlag"
PORTS=(7000 8000 9000 6000 5000 4000 3000 2000)
ALLOWED_PORTS=(22 80 443 8080 8443)  # Should match server configuration
SERVER_IP="111.111.11.11"

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
        echo "Please install Docker to compile for Windows."
        echo "Continue anyway? (y/n)"
        read answer
        if [ "$answer" != "y" ]; then
            exit 1
        fi
    else
        echo "Docker is already installed."
    fi
    
    echo "All dependencies checked."
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
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 --flag <flag> --ports <port1,port2,...> --allowed-ports <port1,port2,...> --server <server_ip>"
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

# Check dependencies
check_dependencies

# Generate Rust project
mkdir -p knocker-client
cd knocker-client
cargo init --bin

# Generate Rust source code with parameters
cat > src/main.rs << EOF
use std::io::{self, Write};
use std::net::{TcpStream, ToSocketAddrs};
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

# Build for multiple platforms
echo "Building port knocking client for multiple platforms..."

# Linux
echo "Building for Linux..."
cargo build --release

# Windows (only if Docker is available)
if command -v docker &> /dev/null; then
    echo "Building for Windows..."
    cross build --release --target x86_64-pc-windows-gnu
else
    echo "Skipping Windows build (Docker not available)"
fi

# macOS (requires macOS host)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Building for macOS..."
    cargo build --release
else
    echo "Skipping macOS build (requires macOS host)"
fi

# Create output directory
mkdir -p ../knocker-binaries

# Copy Linux binary
if [ -f "target/release/knocker-client" ]; then
    cp target/release/knocker-client ../knocker-binaries/knocker-linux
    echo "Linux binary created: knocker-binaries/knocker-linux"
fi

# Copy Windows binary
if [ -f "target/x86_64-pc-windows-gnu/release/knocker-client.exe" ]; then
    cp target/x86_64-pc-windows-gnu/release/knocker-client.exe ../knocker-binaries/knocker-windows.exe
    echo "Windows binary created: knocker-binaries/knocker-windows.exe"
fi

# Copy macOS binary if built
if [[ "$OSTYPE" == "darwin"* ]] && [ -f "target/release/knocker-client" ]; then
    cp target/release/knocker-client ../knocker-binaries/knocker-macos
    echo "macOS binary created: knocker-binaries/knocker-macos"
fi

echo "Build completed!"
echo "Executables can be found in knocker-binaries/ directory"