#!/bin/bash

# Source common functions
die() { echo -e "\033[1;31mError:\033[0m $*" >&2; exit 1; }
[ -f ./Setup-Common.sh ] && source ./Setup-Common.sh || die "Setup-Common.sh not found."

# Check if the script is run as root
check_if_root

# Check if the script is run from the root account
check_if_not_root_account

# Get the current username
get_current_username

# Autologin Prompt
prompt_for_autologin

# VM Prompt
prompt_for_vm

# Display Status from Prompts
display_status "$enable_autologin" "$is_vm"

# Check if custom make.conf and VIDEO_CARDS have already been set previously
MAKECONF_FLAG="/etc/portage/.makeconf_configured"

if [ -f "$MAKECONF_FLAG" ]; then
  echo "make.conf already configured during install. Skipping..."
else
  echo "Configuring /etc/portage/make.conf..."

  # Backup current make.conf & replace with custom one
  timestamp=$(date +%s)
  cp /etc/portage/make.conf /etc/portage/make.conf.old.${timestamp} || die "Failed to back up current make.conf."
  cp etc/portage/make.conf /etc/portage/make.conf || die "Failed to copy custom make.conf."

  # Set MAKEOPTS based on CPU cores (load limit = cores + 1)
  cores=$(nproc) || die "Failed to retrieve number of CPU cores."
  makeopts_load_limit=$((cores + 1))
  sed -i "s/^MAKEOPTS=.*/MAKEOPTS=\"-j$cores -l$makeopts_load_limit\"/" /etc/portage/make.conf || die "Failed to set MAKEOPTS in make.conf."
  echo "Set MAKEOPTS to -j$cores -l$makeopts_load_limit"

  # Set EMERGE_DEFAULT_OPTS based on CPU cores (load limit as 90% of cores)
  load_limit=$(echo "$cores * 0.9" | bc -l | awk '{printf "%.1f", $0}') || die "Failed to calculate load limit."
  sed -i "s/^EMERGE_DEFAULT_OPTS=.*/EMERGE_DEFAULT_OPTS=\"-j$cores -l$load_limit\"/" /etc/portage/make.conf || die "Failed to set EMERGE_DEFAULT_OPTS in make.conf."
  echo "Set EMERGE_DEFAULT_OPTS to -j$cores -l$load_limit"
  
  # Call the function
  set_video_card || die "Failed to set video card."

  # Drop flag so this doesn't run again
  touch "$MAKECONF_FLAG" || die "Failed to create $MAKECONF_FLAG flag."
fi

# Install Essentials
emerge -vquN app-eselect/eselect-repository app-editors/nano dev-vcs/git || die "Failed to install essential packages."

# Switch from rsync to git for faster repository sync times
FLAG="/var/db/repos/.synced-git-repo"

# Skip this if run previously
if [[ ! -f "$FLAG" ]]; then
  eselect repository disable gentoo || die "Failed to disable gentoo repository."
  eselect repository enable gentoo || die "Failed to enable gentoo repository."
  rm -rf /var/db/repos/gentoo || die "Failed to remove existing gentoo repository."
  touch "$FLAG" || die "Failed to create git sync flag."
  echo "Switched to git for repository sync."
else
  echo "Repository already configured for git. Skipping."
fi

# Enable Additional Overlays
eselect repository add sunny-overlay git https://github.com/dguglielmi/sunny-overlay.git || die "Failed to add sunny-overlay repository."
eselect repository enable guru || die "Failed to enable guru repository."
eselect repository enable gentoo-zh || die "Failed to enable gentoo-zh repository."
eselect repository enable djs_overlay || die "Failed to enable djs_overlay repository."

# Mask select djs_overlay packages
echo "app-editors/neovim::djs_overlay" | tee /etc/portage/package.mask/neovim || die "Failed to mask neovim package."
echo "www-client/brave-bin::djs_overlay" | tee /etc/portage/package.mask/brave || die "Failed to mask brave-bin package."

# Allow select unstable packages to be merged
echo "x11-misc/gpaste ~amd64" | tee /etc/portage/package.accept_keywords/gpaste || die "Failed to add gpaste to package.accept_keywords."
echo "app-admin/grub-customizer ~amd64" | tee /etc/portage/package.accept_keywords/grub-customizer || die "Failed to add grub-customizer to package.accept_keywords."
echo "media-video/haruna ~amd64" | tee /etc/portage/package.accept_keywords/haruna || die "Failed to add haruna to package.accept_keywords."
echo "x11-apps/lightdm-gtk-greeter-settings ~amd64" | tee /etc/portage/package.accept_keywords/lightdm-gtk-greeter-settings || die "Failed to add lightdm-gtk-greeter-settings to package.accept_keywords."
echo "x11-themes/kvantum ~amd64" | tee /etc/portage/package.accept_keywords/kvantum || die "Failed to add kvantum to package.accept_keywords."
echo "app-backup/timeshift ~amd64" | tee /etc/portage/package.accept_keywords/timeshift || die "Failed to add timeshift to package.accept_keywords."

# Enable Extra Use Flags
echo "app-editors/gedit-plugins charmap git terminal" | tee /etc/portage/package.use/gedit-plugins || die "Failed to set USE flags for gedit-plugins."
echo "media-video/ffmpegthumbnailer gnome" | tee /etc/portage/package.use/ffmpegthumbnailer || die "Failed to set USE flags for ffmpegthumbnailer."
echo "gnome-extra/nemo tracker" | tee /etc/portage/package.use/nemo || die "Failed to set USE flags for nemo."
echo "app-emulation/qemu glusterfs iscsi opengl pipewire spice usbredir vde virgl virtfs zstd" | tee /etc/portage/package.use/qemu || die "Failed to set USE flags for qemu."

# Temporary Python Versions Fix
echo "sys-cluster/glusterfs PYTHON_SINGLE_TARGET: python3_12
x11-apps/lightdm-gtk-greeter-settings PYTHON_SINGLE_TARGET: python3_12" | tee /etc/portage/package.use/python || die "Failed to set USE flags for python."

# Sync Repository + All Overlays
emaint sync -a || die "Failed to sync repositories and overlays."

# Select 23.0 gnome desktop systemd profile for Cinnamon
eselect profile set default/linux/amd64/23.0/desktop/gnome/systemd || die "Failed to set default profile."

# Enable Sound (Pipewire)
echo "media-video/pipewire sound-server" | tee /etc/portage/package.use/pipewire || die "Failed to set USE flags for pipewire."
echo "media-sound/pulseaudio -daemon" | tee /etc/portage/package.use/pulseaudio || die "Failed to set USE flags for pulseaudio."

# Emerge changes and cleanup
emerge -vqDuN @world || die "Failed to emerge world update."
emerge -q --depclean || die "Failed to clean up unused dependencies."

# All Packages
packages=(
    # Unstable Packages
    "x11-misc/gpaste"
    "app-admin/grub-customizer"
    #"x11-apps/lightdm-gtk-greeter-settings" # clashes with gobject-introspection
    "x11-themes/kvantum"
    "app-backup/timeshift" # triggers use flag change
    # Desktop environment related packages
    "x11-base/xorg-server"
    "gnome-extra/cinnamon"
    "x11-misc/lightdm"
    "x11-misc/lightdm-gtk-greeter"
    "www-client/brave-bin"
    "media-gfx/eog"
    "app-text/evince"
    "media-video/ffmpegthumbnailer"
    "app-editors/gedit"
    "app-editors/vscodium"
    #"app-editors/gedit-plugins" # clashes with gobject-introspection
    "gnome-extra/gnome-calculator"
    "sys-apps/gnome-disk-utility"
    "media-gfx/gnome-screenshot"
    "gnome-extra/gnome-system-monitor"
    "x11-terms/gnome-terminal"
    "media-gfx/gthumb"
    "media-video/haruna"
    "gnome-extra/nemo"
    "gnome-extra/nemo-fileroller"
    "x11-misc/qt5ct"
    "gui-apps/qt6ct"
    "media-sound/rhythmbox"
    # System utilities
    "app-admin/eclean-kernel"
    "dev-python/zstandard" # for eclean-kernel
    "app-arch/file-roller"
    "sys-apps/flatpak"
    "sys-apps/xdg-desktop-portal-gtk"
    "app-portage/gentoolkit"
    "sys-block/gparted"
    "app-portage/mirrorselect"
    "sys-fs/ncdu"
    "app-misc/neofetch"
    "net-firewall/ufw"    
    "app-arch/unzip"
    "x11-apps/xkill"
    "x11-apps/xrandr"
    # Network utilities
    "net-ftp/filezilla"
    "gnome-base/gvfs"
    "kde-misc/kdeconnect"
    "net-fs/samba"
    # Applications
    "sys-apps/bleachbit"
    "sys-process/bottom"
    "app-office/libreoffice"
    "app-editors/neovim"
    "net-p2p/qbittorrent"
    "app-emulation/spice-vdagent"
    "media-fonts/noto"
    "media-fonts/noto-emoji"
    "x11-misc/xclip"
    # For NvChad
    "sys-devel/gcc"
    "dev-build/make"
    "sys-apps/ripgrep"   
    # Virtualization Tools
    "app-emulation/virt-manager" # triggers use flag change
    "app-emulation/qemu"
    "app-emulation/libvirt" # triggers use flag change
    "sys-firmware/edk2-bin"
    "net-dns/dnsmasq"
    "net-misc/vde"
    "net-misc/bridge-utils"
    "net-firewall/iptables"
    "sys-apps/dmidecode"
    "sys-cluster/glusterfs"
    "net-libs/libiscsi"
    "app-emulation/guestfs-tools"
)
# Automatically accept USE changes and update config files
touch /etc/portage/package.use/zzz_autounmask || die "Failed to create /etc/portage/package.use/zzz_autounmask."
# Emerge with autounmask-write and continue
emerge -vqDuN --with-bdeps=y "${packages[@]}" --autounmask-write --autounmask-continue=y || die "Emerge failed during initial package installation."
# Update configurations automatically, writing to zzz_autounmask
dispatch-conf <<< $(echo -e 'y') || die "Failed to run dispatch-conf for configuration update."
# Resume emerge
emerge -vqDuN --with-bdeps=y --keep-going "${packages[@]}" || die "Failed to install packages."

# Enable Flathub for Flatpak
enable_flathub

# Preserve old configurations (for Virtual Machine Manager)
preserve_old_libvirt_configs

# Set proper permissions in libvirtd.conf
set_libvirtd_permissions

# Set proper permissions in qemu.conf
set_qemu_permissions

# Enable and start services
echo "Enabling services..."
systemctl enable libvirtd >/dev/null 2>&1 || die "Failed to enable libvirtd service."
systemctl enable lightdm >/dev/null 2>&1 || die "Failed to enable lightdm service."
systemctl enable NetworkManager >/dev/null 2>&1 || die "Failed to enable NetworkManager service."
systemctl --global enable pipewire.service >/dev/null 2>&1 || die "Failed to enable pipewire.service globally."
systemctl --global enable pipewire-pulse.socket >/dev/null 2>&1 || die "Failed to enable pipewire-pulse.socket globally."
systemctl --global enable wireplumber.service >/dev/null 2>&1 || die "Failed to enable wireplumber.service globally."

# Only enable net-autostart if in physical machine
manage_virsh_network

# Add the current user to the necessary groups
add_user_to_groups libvirt kvm input disk video pipewire

# Backup original LightDM config
backup_lightdm_config

# Modify lightdm.conf in-place
modify_lightdm_conf "gentoo"

# Ensure autologin group exists and add user
ensure_autologin_group

# If running in a VM, set display-setup-script in lightdm.conf
set_lightdm_display_for_vm

# Set timeout for stopping services during shutdown via drop in file
set_systemd_timeout_stop

# Reload the systemd configuration
reload_systemd_daemon

# Add flag for Setup-Theme.sh
add_setup_theme_flag "gentoo"

# Display Reboot Message
print_reboot_message
