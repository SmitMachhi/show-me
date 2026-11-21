#!/bin/sh
# Installs show-me on Linux and macOS with one command:
#   curl -fsSL https://raw.githubusercontent.com/SmitMachhi/show-me/master/install.sh | sh
# Downloads the program for this system, puts it on the PATH, writes the agent skill
# and installs Graphviz when it is missing. Set SHOW_ME_INSTALL_DIR to pick the folder.
set -eu

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) file=show-me-linux-x86_64 ;;
    Darwin-arm64) file=show-me-macos-arm64 ;;
    *)
        echo "show-me has no download for $(uname -s) $(uname -m). Build it from source: see the README." >&2
        exit 1
        ;;
esac

dir="${SHOW_ME_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$dir"
echo "Downloading show-me to $dir"
curl -fsSL -o "$dir/show-me.new" "https://github.com/SmitMachhi/show-me/releases/latest/download/$file"
chmod +x "$dir/show-me.new"
mv -f "$dir/show-me.new" "$dir/show-me"
"$dir/show-me" setup

# Graphviz draws the diagrams. A failure here leaves show-me installed and says what to run.
if ! command -v dot >/dev/null 2>&1; then
    echo "Installing Graphviz"
    if command -v brew >/dev/null 2>&1; then brew install graphviz
    elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update -qq && sudo apt-get install -y -qq graphviz
    elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y graphviz
    elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm graphviz
    elif command -v zypper >/dev/null 2>&1; then sudo zypper install -y graphviz
    elif command -v apk >/dev/null 2>&1; then sudo apk add graphviz
    else false
    fi || echo "Graphviz was not installed. Diagrams need it: install the graphviz package." >&2
fi

# A new terminal finds show-me only if its folder is on the PATH.
# SHOW_ME_KEEP_PATH=1 leaves the shell files alone (tests use it).
if [ -z "${SHOW_ME_KEEP_PATH:-}" ]; then
    case ":$PATH:" in
        *":$dir:"*) ;;
        *)
            case "${SHELL:-}" in
                */zsh) rc="$HOME/.zshrc" ;;
                */bash) rc="$HOME/.bashrc" ;;
                *) rc="$HOME/.profile" ;;
            esac
            printf '\nexport PATH="%s:$PATH"\n' "$dir" >>"$rc"
            echo "Added $dir to the PATH in $rc. Open one new terminal to use it."
            ;;
    esac
fi

echo "show-me $("$dir/show-me" --version) is installed."
