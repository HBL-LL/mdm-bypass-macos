#!/bin/bash

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Error handling function
error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

# Warning function
warn() {
	echo -e "${YEL}WARNING: $1${NC}"
}

# Success function
success() {
	echo -e "${GRN}✓ $1${NC}"
}

# Info function
info() {
	echo -e "${BLU}ℹ $1${NC}"
}

# Check root permissions (macOS Recovery runs as root)
[ "$(id -u)" -eq 0 ] || error_exit "Must run as root (boot into macOS Recovery)."

# Validation function for username
validate_username() {
	local username="$1"

	# Check if username is empty
	if [ -z "$username" ]; then
		echo "Username cannot be empty"
		return 1
	fi

	# Check length (1-31 characters for macOS)
	if [ ${#username} -gt 31 ]; then
		echo "Username too long (max 31 characters)"
		return 1
	fi

	# Check for valid characters (alphanumeric, underscore, hyphen)
	if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
		echo "Username can only contain letters, numbers, underscore, and hyphen"
		return 1
	fi

	# Check if starts with letter or underscore
	if ! [[ "$username" =~ ^[a-zA-Z_] ]]; then
		echo "Username must start with a letter or underscore"
		return 1
	fi

	return 0
}

# Validation function for password
validate_password() {
	local password="$1"

	# Check if password is empty
	if [ -z "$password" ]; then
		echo "Password cannot be empty"
		return 1
	fi

	# Check minimum length (macOS allows any length, but recommend 4+)
	if [ ${#password} -lt 4 ]; then
		echo "Password too short (minimum 4 characters recommended)"
		return 1
	fi

	return 0
}

# Check if user already exists
check_user_exists() {
	local dscl_path="$1"
	local username="$2"

	if dscl -f "$dscl_path" localhost -read "/Local/Default/Users/$username" >/dev/null 2>&1; then
		return 0 # User exists
	else
		return 1 # User doesn't exist
	fi
}

# Find available UID (501-599)
find_available_uid() {
	local dscl_path="$1"
	local uid=501

	while [ $uid -lt 600 ]; do
		if ! dscl -f "$dscl_path" localhost -search /Local/Default/Users UniqueID $uid 2>/dev/null | grep -q "UniqueID"; then
			echo $uid
			return 0
		fi
		uid=$((uid + 1))
	done

	echo "501" # Default fallback
	return 1
}

# Function to detect system volumes with multiple fallback strategies
detect_volumes() {
	local system_vol=""
	local data_vol=""

	info "Detecting system volumes..." >&2

	# Strategy 1: Look for system volume (not Data, not Recovery, contains /System)
	for vol in /Volumes/*; do
		if [ -d "$vol" ]; then
			local vol_name; vol_name=$(basename "$vol")

			if [[ ! "$vol_name" =~ Data$ ]] && [[ ! "$vol_name" =~ Recovery ]] && [[ ! "$vol_name" =~ Preboot ]] && [ -d "$vol/System" ]; then
				system_vol="$vol_name"
				info "Found system volume: $system_vol" >&2
				break
			fi
		fi
	done

	# Strategy 2: If no system volume found, try looking for any volume with /System directory
	if [ -z "$system_vol" ]; then
		for vol in /Volumes/*; do
			if [ -d "$vol/System" ] && [[ ! "$(basename "$vol")" =~ Recovery ]]; then
				system_vol=$(basename "$vol")
				warn "Using volume with /System directory: $system_vol" >&2
				break
			fi
		done
	fi

	# Strategy 3: Check for Data volume
	if [ -d "/Volumes/Data/private/var/db/dslocal" ]; then
		data_vol="Data"
		info "Found data volume: $data_vol" >&2
	elif [ -n "$system_vol" ] && [ -d "/Volumes/$system_vol - Data/private/var/db" ]; then
		data_vol="$system_vol - Data"
		info "Found data volume: $data_vol" >&2
	else
		# Look for any volume ending with "Data"
		for vol in /Volumes/*Data; do
			if [ -d "$vol/private/var/db/dslocal" ]; then
				data_vol=$(basename "$vol")
				warn "Found data volume: $data_vol" >&2
				break
			fi
		done
	fi

	# Validate findings
	if [ -z "$system_vol" ]; then
		error_exit "Could not detect system volume. Please ensure you're running this in Recovery mode with a macOS installation present."
	fi

	if [ -z "$data_vol" ]; then
		error_exit "Could not detect data volume. Please ensure you're running this in Recovery mode with a macOS installation present."
	fi

	echo "$system_vol|$data_vol"
}

# Detect volumes at startup
volume_info=$(detect_volumes)
system_volume=$(echo "$volume_info" | cut -d'|' -f1)
data_volume=$(echo "$volume_info" | cut -d'|' -f2)

# Display header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            macOS MDM Setup Helper             ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
success "System Volume: $system_volume"
success "Data Volume: $data_volume"
echo ""

# Prompt user for choice
PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Reboot & Exit")
select opt in "${options[@]}"; do
	case $opt in
	"Bypass MDM from Recovery")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Starting MDM Bypass Process${NC}"
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo ""

		# Validate critical paths without renaming data volume
		info "Validating system paths..."

		system_path="/Volumes/$system_volume"
		data_path="/Volumes/$data_volume"

		if [ ! -d "$system_path" ]; then
			error_exit "System volume path does not exist: $system_path"
		fi

		if [ ! -d "$data_path" ]; then
			error_exit "Data volume path does not exist: $data_path"
		fi

		dscl_path="$data_path/private/var/db/dslocal/nodes/Default"
		if [ ! -d "$dscl_path" ]; then
			error_exit "Directory Services path does not exist: $dscl_path"
		fi

		success "All system paths validated"
		echo ""

		# Create Temporary Admin User
		echo -e "${CYAN}Creating Admin User${NC}"
		echo -e "${NC}Press Enter to use defaults (recommended)${NC}"

		# Get and validate real name
		read -r -p "Enter Full Name (Default is 'Apple'): " realName
		realName="${realName:=Apple}"

		# Get and validate username
		while true; do
			read -r -p "Enter Username (Default is 'Apple'): " username
			username="${username:=Apple}"

			if validation_msg=$(validate_username "$username"); then
				break
			else
				warn "$validation_msg"
				echo -e "${YEL}Please try again or press Ctrl+C to exit${NC}"
			fi
		done

		# Check if user already exists
		if check_user_exists "$dscl_path" "$username"; then
			warn "User '$username' already exists in Directory Services"
			read -r -p "Do you want to use a different username? (y/n): " response
			if [[ "$response" =~ ^[Yy]$ ]]; then
				while true; do
					read -r -p "Enter a different username: " username
					if [ -z "$username" ]; then
						warn "Username cannot be empty"
						continue
					fi
					if validation_msg=$(validate_username "$username"); then
						if ! check_user_exists "$dscl_path" "$username"; then
							break
						else
							warn "User '$username' also exists. Try another name."
						fi
					else
						warn "$validation_msg"
					fi
				done
			else
				warn "Continuing with existing user '$username' (may cause conflicts)"
			fi
		fi

		# Get and validate password
		while true; do
			read -r -p "Enter Password (Default is '1234'): " passw
			passw="${passw:=1234}"

			if validation_msg=$(validate_password "$passw"); then
				break
			else
				warn "$validation_msg"
				echo -e "${YEL}Please try again or press Ctrl+C to exit${NC}"
			fi
		done

		echo ""

		# Find available UID
		info "Checking for available UID..."
		available_uid=$(find_available_uid "$dscl_path")
		if [ "$available_uid" != "501" ]; then
			info "UID 501 is in use, using UID $available_uid instead"
		fi
		success "Using UID: $available_uid"
		echo ""

		# Create User Record
		info "Creating user account: $username"
		user_record="/Local/Default/Users/$username"

		if ! dscl -f "$dscl_path" localhost -create "$user_record" 2>/dev/null; then
			error_exit "Failed to create user account record"
		fi

		dscl -f "$dscl_path" localhost -create "$user_record" UserShell "/bin/zsh" || warn "Failed to set user shell"
		dscl -f "$dscl_path" localhost -create "$user_record" RealName "$realName" || warn "Failed to set real name"
		dscl -f "$dscl_path" localhost -create "$user_record" UniqueID "$available_uid" || warn "Failed to set UID"
		dscl -f "$dscl_path" localhost -create "$user_record" PrimaryGroupID "20" || warn "Failed to set GID"

		# Create Home Directory and set proper ownership
		user_home="$data_path/Users/$username"
		if [ ! -d "$user_home" ]; then
			if mkdir -p "$user_home" 2>/dev/null; then
				success "Created user home directory: $user_home"
			else
				error_exit "Failed to create user home directory: $user_home"
			fi
		else
			warn "User home directory already exists: $user_home"
		fi

		# Ensure the user owns their home directory (avoids permission/login loop issues)
		chown -R "$available_uid:20" "$user_home" 2>/dev/null || warn "Failed to set home directory ownership"

		dscl -f "$dscl_path" localhost -create "$user_record" NFSHomeDirectory "/Users/$username" || warn "Failed to set home directory path"

		if ! dscl -f "$dscl_path" localhost -passwd "$user_record" "$passw" 2>/dev/null; then
			error_exit "Failed to set user password"
		fi

		if ! dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null; then
			error_exit "Failed to add user to admin group"
		fi

		success "User account created and added to admin group"
		echo ""

		# Block MDM domains
		info "Blocking MDM enrollment domains..."

		etc_dir="$system_path/etc"
		[ -d "$etc_dir" ] || mkdir -p "$etc_dir" 2>/dev/null

		hosts_file="$etc_dir/hosts"
		[ -f "$hosts_file" ] || touch "$hosts_file" || error_exit "Failed to create hosts file"

		# Backup hosts file before modifying
		if [ ! -f "$hosts_file.bak-mdm" ]; then
			cp "$hosts_file" "$hosts_file.bak-mdm" 2>/dev/null && success "Backed up original hosts file to $hosts_file.bak-mdm"
		fi

		# Standard MDM / DEP domains
		BLOCKED_DOMAINS=(
			"deviceenrollment.apple.com"
			"mdmenrollment.apple.com"
			"iprofiles.apple.com"
			"vpp.itunes.apple.com"
			"mdm.apple.com"
		)

		for domain in "${BLOCKED_DOMAINS[@]}"; do
			if ! grep -qE "^[[:space:]]*0\.0\.0\.0[[:space:]]+$domain([[:space:]]|$)" "$hosts_file" 2>/dev/null; then
				echo "0.0.0.0 $domain" >> "$hosts_file"
			fi
		done

		success "MDM enrollment domains blocked in hosts file"
		echo ""

		# Configuration profiles & setup flags
		info "Configuring bypass markers..."

		config_path="$system_path/var/db/ConfigurationProfiles/Settings"
		[ -d "$config_path" ] || mkdir -p "$config_path" 2>/dev/null

		# Mark setup as complete
		touch "$data_path/private/var/db/.AppleSetupDone" 2>/dev/null && success "Marked setup as complete (.AppleSetupDone)" || warn "Could not mark setup as complete"

		# Remove activation records
		rm -rf "$config_path/.cloudConfigHasActivationRecord" 2>/dev/null && success "Removed activation record" || info "No activation record to remove"
		rm -rf "$config_path/.cloudConfigRecordFound" 2>/dev/null && success "Removed cloud config record" || info "No cloud config record to remove"

		# Create bypass markers
		touch "$config_path/.cloudConfigProfileInstalled" 2>/dev/null && success "Created profile installed marker" || warn "Could not create profile marker"
		touch "$config_path/.cloudConfigRecordNotFound" 2>/dev/null && success "Created record not found marker" || warn "Could not create not found marker"

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║             MDM Bypass Complete!              ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}Login Credentials:${NC}"
		echo -e "  Username : ${YEL}$username${NC}"
		echo -e "  Password : ${YEL}$passw${NC}"
		echo ""
		echo -e "${CYAN}Next steps:${NC}"
		echo -e "  1. Close this terminal window"
		echo -e "  2. Reboot your Mac (or select option 2 below)"
		echo ""
		;;
	"Reboot & Exit")
		echo ""
		info "Rebooting system..."
		reboot
		break
		;;
	*)
		echo -e "${RED}Invalid option $REPLY${NC}"
		;;
	esac
done

