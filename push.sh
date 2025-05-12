#!/bin/bash

# Minimal Error Handling function
die() { echo -e "\033[1;31mError:\033[0m $*" >&2; exit 1; }

# Detect VSCodium configs and plugins
if [[ ! -d VSCodium ]]; then
    die "Missing required directories: VSCodium and/or .vscode-oss"
fi

# Generate Default-Apps-VSCodium.sh
echo '#!/bin/bash

# Source Code - VSCodium
xdg-mime default codium.desktop application/javascript
xdg-mime default codium.desktop application/x-httpd-php3
xdg-mime default codium.desktop application/x-httpd-php4
xdg-mime default codium.desktop application/x-httpd-php5
xdg-mime default codium.desktop application/x-m4
xdg-mime default codium.desktop application/x-php
xdg-mime default codium.desktop application/x-ruby
xdg-mime default codium.desktop application/x-shellscript
xdg-mime default codium.desktop application/xml
xdg-mime default codium.desktop text/css
xdg-mime default codium.desktop text/turtle
xdg-mime default codium.desktop text/x-c++hdr
xdg-mime default codium.desktop text/x-c++src
xdg-mime default codium.desktop text/x-chdr
xdg-mime default codium.desktop text/x-csharp
xdg-mime default codium.desktop text/x-csrc
xdg-mime default codium.desktop text/x-diff
xdg-mime default codium.desktop text/x-dsrc
xdg-mime default codium.desktop text/x-fortran
xdg-mime default codium.desktop text/x-java
xdg-mime default codium.desktop text/x-makefile
xdg-mime default codium.desktop text/x-pascal
xdg-mime default codium.desktop text/x-perl
xdg-mime default codium.desktop text/x-python
xdg-mime default codium.desktop text/x-sql
xdg-mime default codium.desktop text/x-vb
xdg-mime default codium.desktop text/yaml

# Plain Text - VSCodium
xdg-mime default codium.desktop text/plain' > Default-Apps-VSCodium.sh

# Make script executable
chmod +x Default-Apps-VSCodium.sh || die "Failed to make Default-Apps-VSCodium.sh executable."

# Go to remove git history
rm -rf .git || die "Failed to remove git history."

# Initialize
git init || die "Failed to initialize repo."
git remote add origin https://github.com/SpreadiesInSpace/codium || die "Failed to set git remote."
git add . || die "Failed to add files."
git commit -m 'update VSCodium dots' || die "Commit failed."

# Set branch name from master to main then force push
git branch -m main  || die "Failed to set branch name to main."
git push -f -u origin main || die "Failed to push to repo."
