#!/bin/bash

set -e

# Script to install Python modules via apt packages
# Reads from /config/python-modules.txt and installs corresponding python3-* packages

MODULES_FILE="/config/python-modules.txt"
LOG_FILE="/tmp/python-modules-install.log"

echo "Starting Python modules installation..." | tee $LOG_FILE

# Check if modules file exists
if [ ! -f "$MODULES_FILE" ]; then
    echo "Warning: $MODULES_FILE not found. Skipping Python modules installation." | tee -a $LOG_FILE
    exit 0
fi

# Update apt cache
echo "Updating apt cache..." | tee -a $LOG_FILE
apt-get update

# Arrays to track installation status
declare -a INSTALLED_PACKAGES=()
declare -a FAILED_PACKAGES=()

# Function to try installing a package with different naming conventions
try_install_package() {
    local module_name="$1"
    local package_variants=(
        "python3-${module_name}"
        "python3-${module_name//_/-}"  # Replace underscores with hyphens
        "python3-${module_name//-/_}"  # Replace hyphens with underscores
    )

    # Special case mappings for common packages
    case "$module_name" in
        "beautifulsoup4") package_variants=("python3-bs4" "python3-beautifulsoup4") ;;
        "pillow") package_variants=("python3-pil" "python3-pillow") ;;
        "pyyaml") package_variants=("python3-yaml" "python3-pyyaml") ;;
        "lxml-html-clean") package_variants=("python3-lxml-html-clean" "python3-lxml[html_clean]") ;;
        "imap-tools") package_variants=("python3-imap-tools" "python3-imaplib2") ;;
        "imapclient") package_variants=("python3-imapclient" "python-imapclient" "python3-python-imapclient") ;;
        "magic") package_variants=("python3-magic" "python3-python-magic") ;;
        "slugify") package_variants=("python3-slugify" "python3-python-slugify") ;;
        "phonenumbers") package_variants=("python3-phonenumbers") ;;
        "num2words") package_variants=("python3-num2words") ;;
        "pdfminer") package_variants=("python3-pdfminer" "python3-pdfminer.six") ;;
    esac

    for package in "${package_variants[@]}"; do
        echo "Trying to install: $package" | tee -a $LOG_FILE

        # Check if package exists
        if apt-cache show "$package" >/dev/null 2>&1; then
            echo "Package $package found in repositories" | tee -a $LOG_FILE

            # Try to install
            if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$package" 2>/dev/null; then
                echo "✓ Successfully installed: $package (for module: $module_name)" | tee -a $LOG_FILE
                INSTALLED_PACKAGES+=("$package")
                return 0
            else
                echo "✗ Failed to install: $package" | tee -a $LOG_FILE
            fi
        else
            echo "Package $package not found in repositories" | tee -a $LOG_FILE
        fi
    done

    echo "✗ Could not install any package variant for module: $module_name" | tee -a $LOG_FILE
    FAILED_PACKAGES+=("$module_name")
    return 0
}

# Read modules from file and install them
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    # Remove leading/trailing whitespace
    module_name=$(echo "$line" | xargs)

    # Skip if empty after trimming
    if [[ -z "$module_name" ]]; then
        continue
    fi

    echo "Processing module: $module_name" | tee -a $LOG_FILE
    try_install_package "$module_name"

done < "$MODULES_FILE"

# Clean up apt cache
echo "Cleaning up apt cache..." | tee -a $LOG_FILE
rm -rf /var/lib/apt/lists/*

# Print summary
echo "" | tee -a $LOG_FILE
echo "=== INSTALLATION SUMMARY ===" | tee -a $LOG_FILE
echo "Successfully installed packages:" | tee -a $LOG_FILE
for package in "${INSTALLED_PACKAGES[@]}"; do
    echo "  ✓ $package" | tee -a $LOG_FILE
done

if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    echo "" | tee -a $LOG_FILE
    echo "Failed to install modules (will need pip fallback):" | tee -a $LOG_FILE
    for module in "${FAILED_PACKAGES[@]}"; do
        echo "  ✗ $module" | tee -a $LOG_FILE
    done

    # Create fallback requirements.txt for pip installation with version specifications
    echo "Creating fallback requirements.txt for failed modules..." | tee -a $LOG_FILE
    > /tmp/fallback-requirements.txt
    for module in "${FAILED_PACKAGES[@]}"; do
        case "$module" in
            "imap-tools") echo "imap-tools==1.6.0" >> /tmp/fallback-requirements.txt ;;
            "imapclient") echo "IMAPClient" >> /tmp/fallback-requirements.txt ;;
            "lxml-html-clean") echo "lxml_html_clean" >> /tmp/fallback-requirements.txt ;;
            *) echo "$module" >> /tmp/fallback-requirements.txt ;;
        esac
    done
    echo "Fallback requirements saved to /tmp/fallback-requirements.txt" | tee -a $LOG_FILE
fi

echo "" | tee -a $LOG_FILE
echo "Python modules installation completed!" | tee -a $LOG_FILE
echo "Log saved to: $LOG_FILE"
