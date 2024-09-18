#!/bin/bash
set -x  # Enable debugging output

# Define the base directory for NSCbuilder
nscbuilder_base="/NSCbuilder"

# Set the directory of the script
script_dir=$(dirname "$(realpath "$0")")
echo "Script directory: $script_dir"

# Use the base directory instead of the script directory
bat_name=$(basename "$0" .sh)
ofile_name="${bat_name}_options.sh"
echo "Options file name: $ofile_name"

# Set the options file path relative to the base directory
op_file="$nscbuilder_base/zconfig/$ofile_name"
echo "Options file path: $op_file"

# Source the options file if it exists
if [ -f "$op_file" ]; then
    echo "Sourcing options file"
    source "$op_file"
else
    echo "Error: Options file $op_file not found."
    exit 1
fi

# Print variables from the options file
echo "nut: $nut"
echo "dec_keys: $dec_keys"

# Set absolute paths relative to the base directory
squirrel="$nscbuilder_base/$nut"
dec_keys="$nscbuilder_base/$dec_keys"

echo "Absolute squirrel path: $squirrel"
echo "Absolute dec_keys path: $dec_keys"

# Check if required files exist
if [ ! -f "$dec_keys" ]; then
    echo "...................................."
    echo "You're missing the following things:"
    echo "...................................."
    echo
    echo '- "keys.txt" is not correctly pointed to or is missing.'
    echo "Current working directory: $(pwd)"
    echo "Contents of $nscbuilder_base:"
    ls -l "$nscbuilder_base"
    echo "Contents of $nscbuilder_base/ztools (if it exists):"
    ls -l "$nscbuilder_base/ztools" 2>/dev/null || echo "ztools directory not found"
    echo
    read -p "Press Enter to continue..."
    echo "Program will exit now."
    sleep 2
    exit 1
fi

# Function to generate cache
generate_cache() {
    echo "Generating cache..."

    # Run the workers functions to generate the cache
    $pycommand "$squirrel" -lib_call workers back_check_files
    if [ $? -ne 0 ]; then
        echo "Error: back_check_files failed."
        exit 1
    fi

    $pycommand "$squirrel" -lib_call workers scrape_local_libs
    if [ $? -ne 0 ]; then
        echo "Error: scrape_local_libs failed."
        exit 1
    fi

    $pycommand "$squirrel" -lib_call workers scrape_remote_libs
    if [ $? -ne 0 ]; then
        echo "Error: scrape_remote_libs failed."
        exit 1
    fi

    echo "Cache generation completed."
}

# Function to start the service
start_service() {
    echo "Starting NSC_Builder Server..."
    
    # Check if the required script exists before proceeding
    if [ ! -f "$squirrel" ]; then
        echo "Error: Squirrel script $squirrel not found."
        exit 1
    fi

    # Clear the log file before starting the server
    : > "$nscbuilder_base/squirrel.log"

    # Generate cache before starting the server
    generate_cache

    # Run nutdb check_files
    $pycommand "$squirrel" -lib_call nutdb check_files
    if [ $? -ne 0 ]; then
        echo "Error: nutdb check_files failed."
        exit 1
    fi

    # Start the server
    if [ "$noconsole" = "false" ]; then
        $pycommand "$squirrel" -lib_call Interface server -xarg "$port" "$host" "$videoplayback" "$ssl"
    else
        # Ensure the log file path is correct and writable
        touch "$nscbuilder_base/squirrel.log"  # Create the log file if it does not exist
        if [ ! -w "$nscbuilder_base/squirrel.log" ]; then
            echo "Error: Log file $nscbuilder_base/squirrel.log is not writable."
            exit 1
        fi

        # Start the server in the background and redirect output to the log file
        $pycommand "$squirrel" -lib_call Interface server -xarg "$port" "$host" "$videoplayback" "$ssl" "$noconsole" >> "$nscbuilder_base/squirrel.log" 2>&1 &
        
        # Capture the PID and write it to a file
        echo $! > "$nscbuilder_base/squirrel.pid"
    fi

    # Check if the server started successfully
    if [ $? -eq 0 ]; then
        echo "Server started successfully."
    else
        echo "Error: Failed to start the server."
    fi
}


# Function to stop the service
stop_service() {
    echo "Stopping NSC_Builder Server..."

    # Use pkill to terminate the process running the squirrel script
    if pkill -9 -f "$squirrel"; then
        echo "Server stopped successfully."
    else
        echo "Server was not running or failed to stop."
    fi
}

# Function to check the status of the service
status_service() {
    if [ -f "$nscbuilder_base/squirrel.pid" ]; then
        pid=$(cat "$nscbuilder_base/squirrel.pid")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "Server is running with PID $pid."
        else
            echo "PID file exists, but process is not running."
        fi
    else
        echo "Server is not running."
    fi
}

# Function to restart the service
restart_service() {
    stop_service
    sleep 2
    start_service
}

# Function to install dependencies
install_dependencies() {
    echo "Installing dependencies..."

    # Install Python and pip if not already installed
    if ! command -v python3 &> /dev/null; then
        echo "Error: python3 is not installed."
        exit 1
    fi

    # Upgrade pip and install setuptools and wheel
    $pycommand -m pip install --upgrade pip setuptools wheel

    # Install necessary packages
    $pycommand -m pip install urllib3 unidecode tqdm bs4 requests Pillow pycryptodome pykakasi googletrans chardet eel bottle zstandard colorama google-auth-httplib2 google-auth-oauthlib oauth2client pyopenssl

    # Upgrade specific packages
    $pycommand -m pip install --upgrade google-api-python-client pyopenssl

    echo "**********************************************************************************"
    echo "--- IMPORTANT: Check if dependencies were installed correctly before continuing ---"
    echo "**********************************************************************************"
}

# Parse command line arguments
case "$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        status_service
        ;;
    install)
        install_dependencies
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|install}"
        exit 1
        ;;
esac

exit 0
