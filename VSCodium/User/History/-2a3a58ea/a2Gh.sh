#!/bin/bash

# TO DO: 
# - Make Variables for Theme Related Entries (for Light Mode)
# - Suppress Synth Shell Prompt Output

die() {
    # Handle exits on error
    printf "\033[1;31mError:\033[0m %s\n" "$*" >&2
    read -rp "Press Enter to exit..."
    exit 1
}

check_not_root() {
    # Prevents script from being run as root
    if [ "$EUID" -eq 0 ]; then
        die "This script must NOT be run as root. Please run it as a regular user."
    fi
}

check_dependencies() {
  local missing=()
  local deps=(dconf flatpak git gsettings nvim sudo unzip)

  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      if [ "$cmd" = "dconf" ]; then
        missing+=("dconf (Debian-based systems need 'dconf-cli')")
      elif [ "$cmd" = "nvim" ]; then
        missing+=("neovim")
      else
        missing+=("$cmd")
      fi
    fi
  done

  # Ensure DBus session is available for gsettings/dconf
  if ! env | grep -q '^DBUS_SESSION_BUS_ADDRESS='; then
    missing+=("DBus session")
  fi

  # Check if gsettings can actually read schemas
  if command -v gsettings >/dev/null 2>&1 && ! gsettings list-schemas >/dev/null 2>&1; then
    missing+=("functional gsettings")
  fi

  # If anything is missing, display and exit
  if [ "${#missing[@]}" -ne 0 ]; then
    printf '%s\n' "Missing dependencies:"
    for item in "${missing[@]}"; do
      printf '  - %s\n' "$item"
    done
    die "Resolve the above issues before continuing."
  fi
}

install_icons_and_themes() {
    # Download icons and fonts
    sudo echo
    bash icons-and-fonts.sh

    # Set filenames
    ICON_ZIP="gruvbox-dark-icons-gtk-1.0.0.zip"
    ICON_EXTRACTED="gruvbox-dark-icons-gtk-1.0.0"
    ICON_RENAME="gruvbox-dark-icons-gtk"
    CURSOR_ZIP="Capitaine Cursors (Gruvbox) - White.zip"
    CURSOR_DIR="Capitaine Cursors (Gruvbox) - White"
    THEME_ZIP="1670604530-Gruvbox-Dark-BL.zip"
    THEME_DIR="Gruvbox-Dark-BL"

    # Extract icons
    echo "Extracting Icons..."
    mv .icons/*.zip "$PWD"
    unzip -q "$ICON_ZIP"
    unzip -q "$CURSOR_ZIP"
    mv "$ICON_EXTRACTED" ".icons/$ICON_RENAME"
    mv "$CURSOR_DIR" .icons/

    # Extract themes
    echo "Extracting Themes..."
    mv .themes/*.zip "$PWD"
    unzip -q "$THEME_ZIP"
    mv "$THEME_DIR" .themes/

    # Always install to user directories
    echo "Installing Icons and Themes..."
    mkdir -p ~/.icons ~/.themes
    cp -npr .icons/* ~/.icons/
    cp -npr .themes/* ~/.themes/

    # If not NixOS, also install to system-wide directories
    if ! grep -qi "nixos" /etc/os-release; then
        sudo cp -npr .icons/* /usr/share/icons/
        sudo cp -npr .themes/* /usr/share/themes/
    fi

    # Move ZIPs back & clean up
    mv "$CURSOR_ZIP" "$ICON_ZIP" .icons/
    mv "$THEME_ZIP" .themes/
    rm -rf ".icons/$ICON_RENAME" ".icons/$CURSOR_DIR" ".themes/$THEME_DIR"
}

# Only Gentoo/openSUSE/Slackware uses this
disable_polkit_agent() {
    # Disable Cinnamon 6.4's built in polkit
    dconf write /org/cinnamon/enable-polkit-agent "false"
}

override_qt_cursor_theme() {
    # Override Cursor Theme for QT Apps
    local distro="$1"

    echo "Setting Cursor Theme Override for QT Apps..."
    if [ "$distro" = "nixos" ]; then
        mkdir -p ~/.icons/default
        rm -rf ~/.icons/default/*
        ln -sf ~/.icons/"Capitaine Cursors (Gruvbox) - White/"* ~/.icons/default/
        sudo mkdir -p /root/.icons/default
        sudo rm -rf /root/.icons/default/*
        sudo ln -sf ~/.icons/"Capitaine Cursors (Gruvbox) - White/"* /root/.icons/default/
    else
        rm -rf ~/.icons/default
        sudo mkdir -p /usr/share/icons/default
        sudo rm -rf /usr/share/icons/default/*
        sudo ln -sf "/usr/share/icons/Capitaine Cursors (Gruvbox) - White/"* /usr/share/icons/default/
    fi
}

enable_flatpak_theme_override() {
    # Ensure Flathub exists
    flatpak remotes | grep -q flathub || {
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    }
    
    echo "Setting GTK & QT Flatpak Theme Override..."
    # Enable GTK & QT Flatpak Theming Override
    sudo flatpak override --filesystem="$HOME/.themes"
    sudo flatpak override --filesystem="$HOME/.icons"
    sudo flatpak override --env=GTK_THEME=Gruvbox-Dark-BL
    sudo flatpak override --env=ICON_THEME=gruvbox-dark-icons-gtk
    sudo flatpak override --filesystem=xdg-config/Kvantum:ro
    sudo flatpak override --env=QT_STYLE_OVERRIDE=kvantum
}

copy_bleachbit_config() {
    local distro="$1"
    local timestamp=$(date +%s)
    local src_file=".config/bleachbit/bleachbit.ini.$distro"
    local user_target="$HOME/.config/bleachbit/bleachbit.ini"
    local root_target="/root/.config/bleachbit/bleachbit.ini"

    echo "Configuring BleachBit..."
    # Backup and copy BleachBit config to appropriate directories
    if [ -f "$user_target" ]; then
        mv "$user_target" "$user_target.old.$timestamp"
    fi
    mkdir -p "$(dirname "$user_target")"
    cp -npr "$src_file" "$user_target"

    if sudo test -f "$root_target"; then
        sudo mv "$root_target" "$root_target.old.$timestamp"
    fi
    sudo mkdir -p "$(dirname "$root_target")"
    sudo cp -prf "$src_file" "$root_target"
}

copy_vscodium_config() {
    # Creates a timestamp for backup
    local timestamp=$(date +%s)

    echo "Configuring VSCodium..."
    # Backup and copy VSCodium config to appropriate directory
    if [ -d ~/.config/VSCodium ]; then
        mv ~/.config/VSCodium ~/.config/VSCodium.old.$timestamp
    fi
    cp -npr .config/VSCodium/ ~/.config/
}

copy_fonts() {
  # Copies fonts to appropriate directories
  local distro="$1"

  echo "Setting Fonts..."
  # NixOS doesn’t use /usr/share/fonts/ for user fonts
  if [ "$distro" = "nixos" ]; then
    cp -npr .fonts/ ~/
  else
    sudo cp -npr .fonts/* /usr/share/fonts/
    mkdir -p ~/.fonts
    sudo ln -sf /usr/share/fonts/* ~/.fonts/
  fi
}

# Only Slackware/Void uses this
symlink_fonts() {
    # Symlink Fonts for Root
    sudo mkdir -p /root/.fonts
    sudo ln -sf /usr/share/fonts/* /root/.fonts/
}

copy_sounds_and_wallpapers() {
  # Copies sounds and wallpapers to home directory
  cp -npr sounds/ ~/
  cp -npr wallpapers/ ~/
}

copy_applets() {
    # Copies applets to appropriate directories
    local applet_variant=$1
    echo "Configuring Cinnamon Applets..."
    cp -npr .local/share/cinnamon/$applet_variant/* ~/.local/share/cinnamon/applets/
}

copy_kdeglobals() {
  # Creates a timestamp for backup
  local timestamp=$(date +%s)

  echo "Applying Gruvbbox Colors to kdeglobals System-wide..."
  # Backup and copy KDE Global defaults to ~/.config
  if [ -f ~/.config/kdeglobals ]; then
    mv ~/.config/kdeglobals ~/.config/kdeglobals.old.$timestamp
  fi
  cp -npr .config/kdeglobals ~/.config/

  if sudo test -f /root/.config/kdeglobals; then
    sudo mv /root/.config/kdeglobals /root/.config/kdeglobals.old.$timestamp
  fi
  sudo mkdir -p /root/.config/
  sudo ln -sf ~/.config/kdeglobals /root/.config/
}

symlink_kdeglobals() {
  # Symlink kdeglobals to color-schemes for KDE applications like haruna
  local distro="$1"

  if [ "$distro" = "nixos" ]; then
    sudo mkdir -p ~/.local/share/color-schemes/
    sudo ln -sf ~/.config/kdeglobals ~/.local/share/color-schemes/gruvbox-dark.colors
  else
    sudo mkdir -p /usr/share/color-schemes/
    sudo ln -sf ~/.config/kdeglobals /usr/share/color-schemes/gruvbox-dark.colors
  fi
}

# Void doesn't use this
copy_haruna_config() {
    # Creates a timestamp for backup
    local timestamp=$(date +%s)

    echo "Configuring Haruna..."
    # Backup and copy Haruna config to appropriate directory
    if [ -d ~/.config/haruna ]; then
        mv ~/.config/haruna ~/.config/haruna.old.$timestamp
    fi
    cp -npr .config/haruna/ ~/.config/
}

copy_cinnamon_spice_settings() {
    # Backup and copy Cinnamon spice settings
    local distro=$1
    local timestamp=$(date +%s)
    mv ~/.config/cinnamon/spices/ ~/.config/cinnamon/spices.old.$timestamp/
    mkdir -p ~/.config/cinnamon/spices/
    
    echo "Applying Cinnamon Spice Settings..."
    # Copy new settings for the specified distro
    cp -npr .config/cinnamon/spices.$distro/* ~/.config/cinnamon/spices/
}

copy_personal_shortcuts() {
    # Copies My Personal Shortcuts
    local distro=$1
    mkdir -p ~/.local/share/applications
    echo "Setting Shortcuts..."
    cp -npr .local/share/applications/$distro/* ~/.local/share/applications/
}

copy_bashrc_and_etc() {
    # Backup and copy .bashrc and etc to home directory
    local distro=$1
    local timestamp=$(date +%s)

    echo "Backing Up .bashrc and Adding New bash Aliases..."
    if [ "$distro" = "nixos" ]; then
        cd theming/
        cp -npr NixOS/* ~/; rm ~/configuration.nix
        sudo cp /root/.bashrc /root/.bashrc.old.$timestamp >/dev/null 2>&1
        sudo cp NixOS/.bashrc.root /root/.bashrc
        sudo cp NixOS/NixAscii.txt /root/
        cp ~/.bashrc ~/.bashrc.old.$timestamp >/dev/null 2>&1
        cat NixOS/.bashrc > bashrc
        mv bashrc ~/.bashrc
        cd ..
    else
        # Copies distro-specific theming files to home directory
        cp -npr "theming/$distro/"* ~/

        # Preserve old root .bashrc with timestamp
        sudo cp /root/.bashrc /root/.bashrc.old.$timestamp >/dev/null 2>&1

        # Create minimal root .bashrc with tty check and source user .bashrc
        echo "# Skip sourcing user .bashrc if running in tty" | sudo tee /root/.bashrc >/dev/null 2>&1
        echo 'if [[ $(tty) == /dev/tty[0-9]* ]]; then' | sudo tee -a /root/.bashrc >/dev/null 2>&1 
        echo '    return'  | sudo tee -a /root/.bashrc >/dev/null 2>&1
        echo 'fi' | sudo tee -a /root/.bashrc >/dev/null 2>&1
        echo "source $HOME/.bashrc" | sudo tee -a /root/.bashrc >/dev/null 2>&1

        # Preserve and replace user .bashrc with timestamp
        cp ~/.bashrc ~/.bashrc.old.$timestamp >/dev/null 2>&1
        cp "theming/$distro/.bashrc" ~/.bashrc
    fi
}

copy_neofetch_config() {
    local variant=${1:-default}  # Use "default" if no argument is passed
    local timestamp=$(date +%s)

    echo "Configuring neofetch..."
    # Backup and copy neofetch config file to appropriate directory
    neofetch >/dev/null 2>&1
    mv ~/.config/neofetch/config.conf ~/.config/neofetch/config.conf.old.$timestamp

    # Check if the variant-specific config file exists
    if [ "$variant" != "default" ] && [ -f ".config/neofetch/config.conf.$variant" ]; then
        cp -npr ".config/neofetch/config.conf.$variant" ~/.config/neofetch/config.conf
    else
        cp -npr ".config/neofetch/config.conf" ~/.config/neofetch/config.conf
    fi

    # Preserve and replace root's neofetch config
    sudo neofetch >/dev/null 2>&1
    sudo mv /root/.config/neofetch/config.conf /root/.config/neofetch/config.conf.old.$timestamp
    sudo ln -sf ~/.config/neofetch/config.conf /root/.config/neofetch/config.conf
}

copy_kvantum_themes() {
    # Backup and copy Kvantum Themes to appropriate directory
    local theme_variant=$1
    local distro=$2
    local timestamp=$(date +%s)

    echo "Installing Kvantum Themes..."
    if [ "$distro" = "nixos" ]; then
        mv ~/.config/Kvantum ~/.config/Kvantum.old.$timestamp >/dev/null 2>&1
        cp -npr .config/Kvantum/ ~/.config/
        echo "" >> ~/.config/Kvantum/kvantum.kvconfig
        echo "[Applications]
Gruvbox-Dark-Brown=kdeconnect-app, kdeconnect-sms" >> ~/.config/Kvantum/kvantum.kvconfig
        sudo mv /root/.config/Kvantum /root/.config/Kvantum.old.$timestamp >/dev/null 2>&1
        kvantummanager --set gruvbox-fallnn
        sudo ln -sf ~/.config/Kvantum /root/.config/
    else
        mv ~/.config/Kvantum ~/.config/Kvantum.old.$timestamp >/dev/null 2>&1
        cp -npr .config/Kvantum/ ~/.config/
        sudo mv /root/.config/Kvantum /root/.config/Kvantum.old.$timestamp >/dev/null 2>&1
        kvantummanager --set "$theme_variant"
        sudo ln -sf ~/.config/Kvantum /root/.config/
    fi
}

copy_qtct_configs() {
    # Backup and copy qt5ct & qt6ct config to appropriate directories
    local timestamp=$(date +%s)

    echo "Applying Kvantum Themes System-wide..."
    # Handle qt5ct
    mv ~/.config/qt5ct ~/.config/qt5ct.old.$timestamp >/dev/null 2>&1
    cp -npr .config/qt5ct/ ~/.config/
    sudo mv /root/.config/qt5ct /root/.config/qt5ct.old.$timestamp >/dev/null 2>&1
    sudo ln -sf ~/.config/qt5ct/ /root/.config/

    # Handle qt6ct
    mv ~/.config/qt6ct ~/.config/qt6ct.old.$timestamp >/dev/null 2>&1
    cp -npr .config/qt6ct/ ~/.config/
    sudo mv /root/.config/qt6ct /root/.config/qt6ct.old.$timestamp >/dev/null 2>&1
    sudo ln -sf ~/.config/qt6ct/ /root/.config/
}

# Gentoo/LMDE doesn't use this
copy_gedit_theme() {
    # Copies Gedit Theme to appropriate directory

    # User directory
    mkdir -p ~/.local/share/libgedit-gtksourceview-300/styles
    cp -npr gruvbox-dark-gedit46.xml ~/.local/share/libgedit-gtksourceview-300/styles

    # Root directory
    sudo mkdir -p /root/.local/share/libgedit-gtksourceview-300/styles
    sudo cp -prf gruvbox-dark-gedit46.xml /root/.local/share/libgedit-gtksourceview-300/styles
}

# Gentoo/LMDE uses this
copy_gedit_old_theme() {
    # Copies Gedit Theme to appropriate directory

    # User directory
    mkdir -p ~/.local/share/gedit/styles
    cp -npr gruvbox-dark.xml ~/.local/share/gedit/styles/

    # Root directory
    sudo mkdir -p /root/.local/share/gedit/styles
    sudo cp -prf gruvbox-dark.xml /root/.local/share/gedit/styles/
}

copy_menu_preferences() {
    # Backup and copy Menu Preferences to appropriate directory
    local distro=$1
    local timestamp=$(date +%s)

    echo "Applying Cinnamon Menu Preferences..."
    # Create timestamped backup directory and move old menu preferences
    cp -npr ~/.config/menus/ ~/.config/menus.old.$timestamp/
    mkdir -p ~/.config/menus/
    # Copy new menu preferences for the specified distro
    cp -npr .config/menus/$distro/* ~/.config/menus/
}

copy_qbittorrent_config() {
    # Backup and copy Qbittorrent config to appropriate directory
    local distro=$1
    local timestamp=$(date +%s)

    echo "Configuring qBittorrent..."
    # Backup the old config with timestamp
    mv ~/.config/qBittorrent/qBittorrent.conf ~/.config/qBittorrent/qBittorrent.conf.old.$timestamp >/dev/null 2>&1
    mkdir -p ~/.config/qBittorrent/

    # Copy distro-specific config
    cp -npr .config/qBittorrent/qBittorrent.conf.$distro ~/.config/qBittorrent/qBittorrent.conf
    cp -npr .config/qBittorrent/mumble-dark.qbtheme ~/.config/qBittorrent/
}

copy_libreoffice_config() {
    # Backup and copy LibreOffice config to appropriate directory
    local distro=$1
    local timestamp=$(date +%s)

    echo "Configuring LibreOffice..."
    # User-side config
    mkdir -p ~/.config/libreoffice
    mv ~/.config/libreoffice/4 ~/.config/libreoffice/4.old.$timestamp >/dev/null 2>&1
    cp -npr .config/libreoffice/$distro ~/.config/libreoffice/4

    # Root-side config
    sudo mkdir -p /root/.config/libreoffice
    sudo mv /root/.config/libreoffice/4 /root/.config/libreoffice/4.old.$timestamp >/dev/null 2>&1
    sudo cp -prf .config/libreoffice/$distro /root/.config/libreoffice/4
}

copy_filezilla_config() {
    # Backup and copy Filezilla config to appropriate directory
    local timestamp=$(date +%s)

    echo "Configuring FileZilla..."
    # Backup the old config with timestamp
    mv ~/.config/filezilla ~/.config/filezilla.old.$timestamp >/dev/null 2>&1
    cp -npr .config/filezilla/ ~/.config/
}

copy_profile_picture() {
    # Backup and copy Profile Picture to home directory
    local timestamp=$(date +%s)

    echo "Setting Profile Picture..."
    # Create timestamped backup for the old profile picture
    mv ~/.face ~/.face.old.$timestamp >/dev/null 2>&1

    # Copy new profile picture
    cp -npr .face ~/
}

import_desktop_config() {
    local distro=$1
    local timestamp=$(date +%s)

    echo "Applying Proper Look & Feel System-wide..."
    # Backup and Import Entire Desktop Configuration
    cd theming/$distro/
    dconf dump / > Old_Desktop_Configuration_$timestamp.dconf
    mv Old_Desktop_Configuration_$timestamp.dconf ~/
    dconf load / < $distro.dconf
    rm ~/$distro.dconf
    cd ../..
}

apply_gedit_and_gnome_terminal_config() {
    # Apply gedit and gnome-terminal configuration to root
    local distro=$1
    local gedit_config=$2

    cd theming/$distro/
    if [[ "$distro" == "openSUSE" ]]; then
        # Use gnomesu for openSUSE
        gnomesu dconf load / < "gnome-terminal-$distro.dconf"
        rm ~/gnome-terminal-$distro.dconf
        cd ..
        gnomesu dconf load / < "$gedit_config"
    else
        # Use sudo dbus-launch for other distros
        sudo dbus-launch dconf load / < "gnome-terminal-$distro.dconf"
        rm ~/gnome-terminal-$distro.dconf
        cd ..
        sudo dbus-launch dconf load / < "$gedit_config"
    fi
    cd ..
}

set_default_apps() {
    local distro=$1

    echo "Setting Default Apps..."
    # Set default apps for the given distro
    cd theming/$distro/
    chmod +x Default-Apps-$distro.sh
    bash Default-Apps-$distro.sh
    sudo bash Default-Apps-$distro.sh
    rm ~/Default-Apps-$distro.sh
    cd ../..
}

# Only Fedora/LMDE/NixOS uses this
set_cinnamon_menu_icon() {

    echo "Setting Cinnamon Menu Icon..."
    # Replaces hardcoded Cinnamon menu icon path with $HOME-based path
    local icon_file="$1"
    local json_file="${HOME}/.config/cinnamon/spices/menu@cinnamon.org/0.json"
    local original_path="/home/f16poom/${icon_file}"
    local new_path="${HOME}/.icons/${icon_file}"

    # Replace the hardcoded path with $HOME-based path on line 91
    sed -i "91s|\"value\": \"${original_path}\"|\"value\": \"${new_path}\"|g" "$json_file"

    # Move the icon file to .icons
    mv ~/"$icon_file" ~/.icons/
}

set_cinnamon_background_and_sounds() {

    echo "Setting Wallpaper..."
    # Set Wallpaper
    gsettings set org.cinnamon.desktop.background picture-uri file://${HOME}/wallpapers/Desktop_Wallpaper.png
    mkdir -p ~/Pictures
    ln -sf ~/wallpapers/* ~/Pictures
    gsettings set org.cinnamon.desktop.background.slideshow image-source directory://${HOME}/Pictures

    echo "Setting Cinnamon Sound Events..."
    # Set Login Sounds
    gsettings set org.cinnamon.sounds login-enabled true
    gsettings set org.cinnamon.sounds login-file ${HOME}/sounds/login.oga
    gsettings set org.cinnamon.sounds logout-enabled true
    gsettings set org.cinnamon.sounds logout-file ${HOME}/sounds/logout.ogg

    # Set Volume Toggle Sound
    gsettings set org.cinnamon.desktop.sound volume-sound-enabled true
    gsettings set org.cinnamon.desktop.sound volume-sound-file ${HOME}/sounds/volume.oga

    # Disable all other Cinnamon Sound Events
    for key in \
      switch-enabled \
      map-enabled \
      close-enabled \
      minimize-enabled \
      maximize-enabled \
      unmaximize-enabled \
      tile-enabled \
      plug-enabled \
      unplug-enabled \
      notification-enabled; do
        gsettings set org.cinnamon.sounds $key false
    done
}

# NixOS doesn't use this
setup_synth_shell_config() {
    local distro=$1
    local timestamp=$(date +%s)

    echo "Configuring Synth Shell Prompt..."
    # Ensure synth-shell-prompt is removed if script fails
    trap 'rm -rf synth-shell-prompt/' EXIT
    # Clone Synth-Shell and run setup
    git clone --recursive https://github.com/andresgongora/synth-shell-prompt.git >/dev/null 2>&1 || die "Failed to download Synth Shell Prompt."
    yes | synth-shell-prompt/setup.sh >/dev/null 2>&1
    yes | sudo synth-shell-prompt/setup.sh >/dev/null 2>&1
    rm -rf synth-shell-prompt/

    # Place Synth-Shell config, preserving old ones with timestamped backup
    cp -npr ~/.config/synth-shell/ ~/.config/synth-shell.old.$timestamp/
    cp -prf .config/synth-shell/$distro/* ~/.config/synth-shell/

    sudo cp -npr /root/.config/synth-shell/ /root/.config/synth-shell.old.$timestamp/
    sudo cp -prf .config/synth-shell/root-synth-shell-prompt.config /root/.config/synth-shell/synth-shell-prompt.config
}

install_nvchad() {
    # Timestamp for unique backups
    timestamp=$(date +%s)

    echo "Configuring NvChad..."
    # Backup existing NVim configs if they exist
    [ -d ~/.config/nvim ] && mv ~/.config/nvim ~/.config/nvim.old.$timestamp
    [ -d ~/.local/share/nvim ] && mv ~/.local/share/nvim ~/.local/share/nvim.old.$timestamp
    [ -d ~/.cache/nvim ] && mv ~/.cache/nvim ~/.cache/nvim.old.$timestamp

    # Clone NVChad starter config
    git clone https://github.com/NvChad/starter ~/.config/nvim >/dev/null 2>&1 || die "Failed to download NvChad."

    # Backup and copy custom chadrc.lua config
    [ -f ~/.config/nvim/lua/chadrc.lua ] && mv ~/.config/nvim/lua/chadrc.lua ~/.config/nvim/lua/chadrc.lua.old.$timestamp
    cp -npr .config/nvim/lua/chadrc.lua ~/.config/nvim/lua/

    # Install all mason plugins and quit Neovim
    nvim --headless "+MasonInstallAll" +qa >/dev/null 2>&1
}

# NixOS doesn't use this
place_login_wallpaper() {
    echo "Setting Login Wallpaper..."
    # Places Login Wallpaper
    sudo cp -nr wallpapers/Login_Wallpaper.jpg /boot/
}

# NixOS doesn't use this
configure_nanorc_basic() {
    # Backup old config and enable basic syntax highlighting in nano
    local timestamp=$(date +%s)

    # Backup the old nanorc file with timestamp
    sudo cp /etc/nanorc /etc/nanorc.old.$timestamp >/dev/null 2>&1

    echo "Configuring nano..."
    # Add the syntax highlighting inclusion line if it's not already present
    if ! grep -q '^include "/usr/share/nano/\*.nanorc"' /etc/nanorc; then
        echo 'include "/usr/share/nano/*.nanorc"' | sudo tee -a /etc/nanorc > /dev/null
    fi
}

# Fedora/Gentoo/NixOS doesn't use this
configure_nanorc_extra() {
    # Adds extra nano syntax highlighting rules
    if ! grep -q '^include "/usr/share/nano/extra/\*.nanorc"' /etc/nanorc; then
        echo 'include "/usr/share/nano/extra/*.nanorc"' | sudo tee -a /etc/nanorc > /dev/null
    fi
}

# NixOS doesn't use this, openSUSE needs 2 ZYPP variables
set_qt_and_gtk_environment() {
    # Backup old config and set QT and GTK theming variables
    local timestamp=$(date +%s)

    echo "Setting QT and GTK Theme Variables..."
    # Backup the old environment file with timestamp
    sudo cp /etc/environment /etc/environment.old.$timestamp >/dev/null 2>&1

    # Set QT and GTK theming variables if not already present
    if ! grep -q "^QT_QPA_PLATFORMTHEME=qt5ct" /etc/environment; then
        echo 'QT_QPA_PLATFORMTHEME=qt5ct' | sudo tee -a /etc/environment > /dev/null
    fi

    if ! grep -q "^GTK_THEME=Gruvbox-Dark-BL" /etc/environment; then
        echo 'GTK_THEME=Gruvbox-Dark-BL' | sudo tee -a /etc/environment > /dev/null
    fi
}

# NixOS doesn't use this
append_slick_greeter_config() {
    # Backup old config and append new settings to slick-greeter.conf
    local timestamp=$(date +%s)

    echo "Configuring LightDM Greeter..."
    # Backup the old slick-greeter.conf with timestamp
    sudo cp /etc/lightdm/slick-greeter.conf /etc/lightdm/slick-greeter.conf.old.$timestamp >/dev/null 2>&1

    # Append new settings to slick-greeter.conf
    echo "[Greeter]
show-hostname=true
theme-name=Gruvbox-Dark-BL
icon-theme-name=gruvbox-dark-icons-gtk
cursor-theme-name=Capitaine Cursors (Gruvbox) - White
clock-format=%a, %-e %b %-l:%M %p 
background=/boot/Login_Wallpaper.jpg
logo=
draw-user-backgrounds=false" | sudo tee /etc/lightdm/slick-greeter.conf > /dev/null
}

# NixOS doesn't use this
append_lightdm_gtk_greeter_config() {
    # Backup old config and append new settings to lightdm-gtk-greeter.conf
    local timestamp=$(date +%s)

    # Backup the old lightdm-gtk-greeter.conf with timestamp
    sudo cp /etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf.old.$timestamp >/dev/null 2>&1

    # Append new settings to lightdm-gtk-greeter.conf
    echo "[greeter]
background=/boot/Login_Wallpaper.jpg
theme-name=Gruvbox-Dark-BL
icon-name=gruvbox-dark-icons-gtk
cursor-theme-name=Capitaine Cursors (Gruvbox) - White
font-name=Cantarell 11
xft-antialias=true
xft-dpi=96
xft-hintstyle=hintslight
xft-rgba=rgb
clock-format=%a, %-e %b %-l:%M %p 
indicators=~host;~spacer;~session;~clock;~power
user-background=false
hide-user-image = true" | sudo tee /etc/lightdm/lightdm-gtk-greeter.conf > /dev/null
}

restart_cinnamon() {
    echo "Restarting Cinnamon..."
    # Restarts Cinnamon
    cinnamon-dbus-command RestartCinnamon 1 >/dev/null 2>&1
}
