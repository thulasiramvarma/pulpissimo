#!/bin/bash
# install_bender.sh — Install bender on systems without sudo/root access
#
# Tested on: CentOS 7 (glibc 2.17), Ubuntu 20.04+
# Installs to: ~/.cargo/bin/bender
#
# Usage:
#   chmod +x install_bender.sh
#   ./install_bender.sh
#   export PATH="$HOME/.cargo/bin:$PATH"
#   bender --version

set -e

BENDER_VERSION="0.28.1"

echo ""
echo "=== PULPissimo bender installer ==="
echo "    Target: ~/.cargo/bin/bender v${BENDER_VERSION}"
echo ""

# ------------------------------------------------------------------ #
# Step 1 — Install Rust/cargo if not present                         #
# ------------------------------------------------------------------ #
if command -v cargo >/dev/null 2>&1; then
    echo "[1/3] cargo already installed: $(cargo --version)"
else
    echo "[1/3] Installing Rust (no-modify-path, no root required)..."
    curl https://sh.rustup.rs -sSf | sh -s -- --no-modify-path -y
    # Activate cargo for the rest of this script
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
    echo "      Rust installed: $(rustc --version)"
fi

# Ensure cargo is on PATH for the rest of the script
export PATH="$HOME/.cargo/bin:$PATH"

# ------------------------------------------------------------------ #
# Step 2 — Build and install bender                                  #
# ------------------------------------------------------------------ #
echo "[2/3] Building bender v${BENDER_VERSION} from source..."
echo "      (first build takes 5-10 min)"
cargo install bender

echo ""
echo "[3/3] Verifying installation..."
BENDER_BIN="$HOME/.cargo/bin/bender"
if [ ! -x "$BENDER_BIN" ]; then
    echo "ERROR: bender binary not found at $BENDER_BIN"
    exit 1
fi
"$BENDER_BIN" --version

# ------------------------------------------------------------------ #
# Step 3 — PATH instructions (no .bashrc write attempted)            #
# ------------------------------------------------------------------ #
echo ""
echo "=== Installation complete ==="
echo ""
echo "Add cargo to PATH for your current shell:"
echo ""
echo "    export PATH=\"\$HOME/.cargo/bin:\$PATH\""
echo ""
echo "To make it permanent, add the above line to whichever"
echo "of these files is writable in your home directory:"
echo ""
for f in "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.bashrc"; do
    if [ -w "$f" ]; then
        echo "    WRITABLE: $f"
    elif [ -e "$f" ]; then
        echo "    locked  : $f"
    fi
done
echo ""
echo "Or pass bender explicitly to make (no PATH change needed):"
echo ""
echo "    cd target/synth"
echo "    make bender_sources BENDER=\$HOME/.cargo/bin/bender"
echo "    make synth BLOCK=fc  GENUS=/path/to/genus"
echo ""
