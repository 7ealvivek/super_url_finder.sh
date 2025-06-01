#!/bin/bash

# --- Configuration ---
DEFAULT_OUTPUT_FILE="all_discovered_urls.txt"
RAW_OUTPUT_FILE=$(mktemp discovered_urls_raw.XXXXXX.txt)
DEFAULT_KATANA_DEPTH=3
KATANA_EXCLUDE_EXTENSIONS="png,jpeg,woff,woff2,gif,jpg,css,svg,ico,ttf,eot,otf,mp3,mp4,avi,webp,json,xml,txt,pdf,doc,docx,xls,xlsx,ppt,pptx,zip,tar,gz,rar,iso"
TOOLS_INSTALL_DIR="$HOME/recon_tools_automated" # Directory for git-cloned tools

# --- Tool Definitions (name -> "type:details") ---
# type can be:
#   go:go_package_path
#   pip:pip_package_name
#   git_pip_local:git_repo_url:clone_dir_name:requirements_file_rel_path (will pip install . in clone_dir)
declare -A REQUIRED_TOOLS_MAP=(
    ["gau"]="go:github.com/lc/gau/v2/cmd/gau@latest"
    ["gauplus"]="go:github.com/ethicalhackingplayground/gauplus@latest"
    ["waymore"]="pip:waymore"
    ["waybackurls"]="go:github.com/tomnomnom/waybackurls@latest"
    ["katana"]="go:github.com/projectdiscovery/katana/cmd/katana@latest"
    ["hakrawler"]="go:github.com/hakluke/hakrawler@latest"
    ["gospider"]="go:github.com/jaeles-project/gospider@latest"
    ["httpx"]="go:github.com/projectdiscovery/httpx/cmd/httpx@latest"
    ["paramspider"]="git_pip_local:https://github.com/devanshbatham/ParamSpider.git:ParamSpider:requirements.txt"
)
# Names to iterate over, preserving order somewhat
REQUIRED_TOOLS_ORDER=("go" "python3" "pip3" "git" "gau" "gauplus" "waymore" "waybackurls" "katana" "hakrawler" "gospider" "httpx" "paramspider")


# --- Script Options ---
OUTPUT_FILE="$DEFAULT_OUTPUT_FILE"
STRIP_QUERY_PARAMS=false
KATANA_DEPTH="$DEFAULT_KATANA_DEPTH"
INPUT_TARGET=""
ASSUME_YES=false # For non-interactive installations

# --- Helper Functions ---
log() {
    echo "[*] $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

error_log() {
    echo "[!] $(date +'%Y-%m-%d %H:%M:%S') - $1" >&2
}

warning_log() {
    echo "[W] $(date +'%Y-%m-%d %H:%M:%S') - $1" >&2
}

usage() {
    echo "Usage: $0 [options] <domain.com | file_with_domains.txt>"
    echo "Options:"
    echo "  -o, --output <file>        Specify output file (default: $DEFAULT_OUTPUT_FILE)"
    echo "  -s, --strip-params         Strip query parameters and fragments before unique sort"
    echo "  -d, --depth <num>          Specify Katana crawl depth (default: $DEFAULT_KATANA_DEPTH)"
    echo "  -y, --yes                  Assume 'yes' to all installation prompts (non-interactive)"
    echo "  -h, --help                 Show this help message"
    exit 1
}

prompt_install() {
    local tool_name="$1"
    local install_method_msg="$2"
    if $ASSUME_YES; then
        REPLY="y"
    else
        read -r -p "[?] Tool '$tool_name' not found. Attempt to install ($install_method_msg)? [Y/n]: " REPLY
    fi
    if [[ "$REPLY" =~ ^[Yy]$ ]] || [[ -z "$REPLY" ]]; then
        return 0 # Yes
    else
        return 1 # No
    fi
}

check_prerequisites() {
    log "Checking core prerequisites..."
    local all_prereqs_met=true

    for prereq in "go" "python3" "pip3" "git"; do
        if ! command -v "$prereq" &> /dev/null; then
            error_log "Core prerequisite '$prereq' NOT FOUND."
            case "$prereq" in
                "go") error_log "Please install Go (golang) and ensure it's in your PATH. Visit https://golang.org/dl/";;
                "python3") error_log "Please install Python 3. Visit https://www.python.org/downloads/";;
                "pip3") error_log "Please install pip3 (Python package installer). Often comes with Python 3 or can be installed via 'python3 -m ensurepip --upgrade' or your system's package manager (e.g., python3-pip).";;
                "git") error_log "Please install Git. Visit https://git-scm.com/downloads/";;
            esac
            all_prereqs_met=false
        else
            log "Core prerequisite '$prereq' found: $(command -v "$prereq")"
        fi
    done

    if ! $all_prereqs_met; then
        error_log "One or more core prerequisites are missing. Please install them and try again."
        exit 1
    fi

    # Check if GOBIN or default Go bin path is in PATH for Go tools
    if command -v go &> /dev/null; then
        local go_bin_path
        go_bin_path=$(go env GOBIN)
        if [ -z "$go_bin_path" ]; then
            go_bin_path=$(go env GOPATH)/bin
        fi
        if [[ ":$PATH:" != *":$go_bin_path:"* ]]; then
            warning_log "Go binary path '$go_bin_path' does not appear to be in your \$PATH."
            warning_log "Go tools installed via 'go install' might not be found unless you add it."
            warning_log "Consider adding 'export PATH=\$PATH:$go_bin_path' to your ~/.bashrc or ~/.zshrc."
        fi
    fi
    log "Core prerequisite check complete."
}


install_tool() {
    local tool_name="$1"
    local install_info="$2"
    local install_type="${install_info%%:*}"
    local install_data="${install_info#*:}"

    log "Attempting to install '$tool_name'..."
    case "$install_type" in
        go)
            local go_package_path="$install_data"
            log "Using 'go install $go_package_path'"
            if GO111MODULE=on go install -v "$go_package_path"; then
                log "Successfully initiated install for '$tool_name'. Please ensure '$tool_name' is now in your PATH."
                # It might take a moment for shell to recognize, or PATH needs reload.
                # Re-checking PATH is important. If command -v fails, manual PATH check by user needed.
            else
                error_log "Failed to install '$tool_name' using 'go install'."
                error_log "Ensure Go is correctly installed and GOBIN or GOPATH/bin is in your PATH."
                return 1
            fi
            ;;
        pip)
            local pip_package_name="$install_data"
            log "Using 'python3 -m pip install --user $pip_package_name'"
            if python3 -m pip install --user --upgrade "$pip_package_name"; then
                log "Successfully initiated install for '$tool_name'."
                warning_log "If '$tool_name' command is not found, ensure Python's user bin directory (e.g., ~/.local/bin) is in your PATH."
            else
                error_log "Failed to install '$tool_name' using 'pip install'."
                return 1
            fi
            ;;
        git_pip_local)
            IFS=':' read -r git_repo_url clone_dir_name req_file_rel_path <<< "$install_data"
            local clone_path="$TOOLS_INSTALL_DIR/$clone_dir_name"
            
            if [ -d "$clone_path" ]; then
                log "Directory '$clone_path' already exists. Assuming already cloned or attempting update."
                # (Optional: Add git pull logic here if desired)
            else
                mkdir -p "$TOOLS_INSTALL_DIR"
                log "Cloning '$git_repo_url' into '$clone_path'..."
                if ! git clone --depth 1 "$git_repo_url" "$clone_path"; then
                    error_log "Failed to clone '$tool_name' from '$git_repo_url'."
                    return 1
                fi
            fi

            if [ -f "$clone_path/$req_file_rel_path" ]; then
                log "Installing Python requirements from '$clone_path/$req_file_rel_path'..."
                if ! python3 -m pip install --user -r "$clone_path/$req_file_rel_path"; then
                    error_log "Failed to install requirements for '$tool_name'."
                    # return 1 # Some tools might work partially or have optional deps.
                fi
            else
                warning_log "Requirements file '$req_file_rel_path' not found in '$clone_path'. Skipping."
            fi
            
            log "Installing '$tool_name' from local clone directory '$clone_path' using 'pip install .'"
            if (cd "$clone_path" && python3 -m pip install --user .); then
                log "Successfully initiated local pip install for '$tool_name'."
                warning_log "If '$tool_name' command is not found, ensure Python's user bin directory (e.g., ~/.local/bin) is in your PATH."
            else
                error_log "Failed local pip install for '$tool_name' from '$clone_path'."
                error_log "You might need to run 'python3 setup.py install' manually (possibly with sudo) or troubleshoot."
                return 1
            fi
            ;;
        *)
            error_log "Unknown installation type '$install_type' for tool '$tool_name'."
            return 1
            ;;
    esac
    # Brief pause to allow system to recognize new command, or for user to source .bashrc if PATH changed
    # In an interactive shell, this might not be enough, user might need to open new terminal or `source ~/.bashrc`
    hash -r 2>/dev/null || true # Tries to clear shell's command hash
    return 0
}


check_and_install_tools() {
    log "Checking for required tools and attempting installation if missing..."
    local all_tools_available=true

    # Iterate in defined order, skipping prerequisite checks as they are handled above
    for tool_name in "${REQUIRED_TOOLS_ORDER[@]}"; do
        # Skip the base prerequisites as they were checked by check_prerequisites()
        if [[ "$tool_name" == "go" || "$tool_name" == "python3" || "$tool_name" == "pip3" || "$tool_name" == "git" ]]; then
            continue
        fi

        local install_info="${REQUIRED_TOOLS_MAP[$tool_name]}"
        if [ -z "$install_info" ]; then
            warning_log "No installation definition found for '$tool_name'. Skipping auto-install check."
            continue
        fi
        
        log "Checking for tool: $tool_name"
        if ! command -v "$tool_name" &> /dev/null; then
            local install_method_msg=""
            local install_type_tmp="${install_info%%:*}"
             case "$install_type_tmp" in
                go) install_method_msg="go install";;
                pip) install_method_msg="pip install";;
                git_pip_local) install_method_msg="git clone & pip install";;
                *) install_method_msg="unknown method";;
            esac

            if prompt_install "$tool_name" "$install_method_msg"; then
                if install_tool "$tool_name" "$install_info"; then
                    if ! command -v "$tool_name" &> /dev/null; then
                        warning_log "Installation of '$tool_name' initiated, but command still not found. You might need to:"
                        warning_log "  1. Open a new terminal session."
                        warning_log "  2. Ensure the relevant bin directory (e.g., \$HOME/go/bin, ~/.local/bin) is in your \$PATH."
                        warning_log "  3. Source your shell profile (e.g., 'source ~/.bashrc' or 'source ~/.zshrc')."
                        all_tools_available=false # Mark as not available for this run.
                    else
                        log "Tool '$tool_name' is now available: $(command -v $tool_name)"
                    fi
                else
                    error_log "Installation attempt failed for '$tool_name'."
                    all_tools_available=false
                fi
            else
                error_log "Skipping installation of '$tool_name'. This tool will not be used."
                all_tools_available=false
            fi
        else
            log "Tool '$tool_name' found: $(command -v "$tool_name")"
        fi
    done

    if ! $all_tools_available; then
        error_log "One or more required tools are unavailable or failed to install. The script might not function optimally."
        # Decide if to exit or continue
        if ! $ASSUME_YES; then
            read -r -p "[?] Continue with available tools? [Y/n]: " REPLY_CONTINUE
            if ! ([[ "$REPLY_CONTINUE" =~ ^[Yy]$ ]] || [[ -z "$REPLY_CONTINUE" ]]); then
                log "Exiting due to missing tools."
                exit 1
            fi
        else
            warning_log "Continuing with available tools due to -y flag, but results may be incomplete."
        fi
    fi
    log "Tool check and installation phase complete."
}


cleanup() {
    log "Cleaning up temporary file: $RAW_OUTPUT_FILE"
    rm -f "$RAW_OUTPUT_FILE"
}

# --- Parse Command Line Arguments ---
while [[ "$#" -gt 0 ]]; do
    key="$1"
    case $key in
        -o|--output) OUTPUT_FILE="$2"; shift; shift ;;
        -s|--strip-params) STRIP_QUERY_PARAMS=true; shift ;;
        -d|--depth) KATANA_DEPTH="$2"; if ! [[ "$KATANA_DEPTH" =~ ^[0-9]+$ ]]; then error_log "Katana depth must be int"; usage; fi; shift; shift ;;
        -y|--yes) ASSUME_YES=true; shift ;;
        -h|--help) usage ;;
        -*) error_log "Unknown option: $1"; usage ;;
        *) if [ -z "$INPUT_TARGET" ]; then INPUT_TARGET="$1"; else error_log "Multiple targets specified incorrectly."; usage; fi; shift ;;
    esac
done

# --- Main Logic ---
if [ -z "$INPUT_TARGET" ]; then error_log "No target specified."; usage; fi

check_prerequisites
check_and_install_tools # This will check and prompt for installation

TARGETS=()
# (Rest of the target preparation and URL gathering logic from the previous script)
if [ -f "$INPUT_TARGET" ]; then
    log "Reading targets from file: $INPUT_TARGET"
    while IFS= read -r line || [[ -n "$line" ]]; do
        cleaned_line=$(echo "$line" | sed -e 's|^https?://||' -e 's|/$||')
        if [[ -n "$cleaned_line" ]]; then TARGETS+=("$cleaned_line"); fi
    done < "$INPUT_TARGET"
else
    log "Processing single target: $INPUT_TARGET"
    cleaned_target=$(echo "$INPUT_TARGET" | sed -e 's|^https?://||' -e 's|/$||')
    if [[ -n "$cleaned_target" ]]; then TARGETS+=("$cleaned_target"); fi
fi

if [ ${#TARGETS[@]} -eq 0 ]; then error_log "No valid targets found."; exit 1; fi

log "Output will be saved to: $OUTPUT_FILE"
log "Found ${#TARGETS[@]} target(s) to process."
if $STRIP_QUERY_PARAMS; then log "Query parameters and fragments will be stripped."; fi

trap cleanup EXIT INT TERM

for domain_to_process in "${TARGETS[@]}"; do
    log "----------------------------------------------------"
    log "Gathering URLs for: $domain_to_process"
    log "----------------------------------------------------"

    # Use httpx to find live URLs
    live_target_urls_from_httpx=""
    if command -v httpx &> /dev/null; then
      live_target_urls_from_httpx=$(echo "$domain_to_process" | httpx -silent -no-fallback -H "User-Agent: Mozilla/5.0" 2>/dev/null)
    else
      warning_log "httpx not found or not usable. Proceeding with less precision for live targets."
    fi

    declare -A urls_to_scan_map
    if [ -n "$live_target_urls_from_httpx" ]; then
        log "Live servers found by httpx for $domain_to_process:"
        echo "$live_target_urls_from_httpx"
        while IFS= read -r url; do urls_to_scan_map["$url"]=1; done <<< "$live_target_urls_from_httpx"
    else
        log "No live HTTP/S servers found by httpx (or httpx unavailable). Using fallbacks."
    fi
    urls_to_scan_map["http://$domain_to_process"]=1
    urls_to_scan_map["https://$domain_to_process"]=1
    
    live_target_urls_final=""
    for url in "${!urls_to_scan_map[@]}"; do live_target_urls_final+="$url"$'\n'; done
    live_target_urls_final=$(echo "$live_target_urls_final" | sed '/^$/d')

    if [ -z "$live_target_urls_final" ]; then log "No URLs to scan for $domain_to_process. Skipping."; continue; fi
    
    log "Effective URLs/endpoints to scan for $domain_to_process:"
    echo "$live_target_urls_final"

    echo "$live_target_urls_final" | while IFS= read -r target_url; do
        if [ -z "$target_url" ]; then continue; fi
        log ">>> Processing base: $target_url"
        current_domain_for_tools=$(echo "$target_url" | sed -e 's|^https?://||' -e 's|/.*$||' | cut -d':' -f1)

        # Gau
        if command -v gau &>/dev/null; then log "Running gau for $current_domain_for_tools..."; gau --subs "$current_domain_for_tools" >> "$RAW_OUTPUT_FILE" 2>/dev/null; else warning_log "gau not found. Skipping."; fi
        # Gauplus
        if command -v gauplus &>/dev/null; then log "Running gauplus for $current_domain_for_tools..."; gauplus -subs -t 10 -d "$current_domain_for_tools" >> "$RAW_OUTPUT_FILE" 2>/dev/null; else warning_log "gauplus not found. Skipping."; fi
        # Waybackurls
        if command -v waybackurls &>/dev/null; then log "Running waybackurls for $current_domain_for_tools..."; echo "$current_domain_for_tools" | waybackurls >> "$RAW_OUTPUT_FILE" 2>/dev/null; else warning_log "waybackurls not found. Skipping."; fi
        # Waymore
        if command -v waymore &>/dev/null; then log "Running waymore for $current_domain_for_tools..."; waymore -i "$current_domain_for_tools" -mode U -oU "$RAW_OUTPUT_FILE.waymore_tmp"; cat "$RAW_OUTPUT_FILE.waymore_tmp" >> "$RAW_OUTPUT_FILE"; rm -f "$RAW_OUTPUT_FILE.waymore_tmp"; else warning_log "waymore not found. Skipping."; fi
        # Katana
        if command -v katana &>/dev/null; then log "Running Katana for $target_url..."; katana -u "$target_url" -silent -jc -kf all -fx -xhr -d "$KATANA_DEPTH" -headless -aff -ef "$KATANA_EXCLUDE_EXTENSIONS" >> "$RAW_OUTPUT_FILE" 2>/dev/null; else warning_log "katana not found. Skipping."; fi
        # Hakrawler
        if command -v hakrawler &>/dev/null; then log "Running hakrawler for $target_url..."; echo "$target_url" | hakrawler -depth 3 -plain >> "$RAW_OUTPUT_FILE" 2>/dev/null; else warning_log "hakrawler not found. Skipping."; fi
        # Gospider
        if command -v gospider &>/dev/null; then
            log "Running gospider for $target_url..."
            gospider_output_dir=$(mktemp -d gospider_out.XXXXXX)
            gospider -s "$target_url" -c 5 -d "$KATANA_DEPTH" --other-source --include-subs --robots -q -o "$gospider_output_dir" > /dev/null 2>&1
            found_gospider_files=$(find "$gospider_output_dir" -type f \( -name '*.txt' -o -name "*$current_domain_for_tools*" \) 2>/dev/null)
            if [ -n "$found_gospider_files" ]; then cat $found_gospider_files >> "$RAW_OUTPUT_FILE" 2>/dev/null; fi
            rm -rf "$gospider_output_dir"
        else
            warning_log "gospider not found. Skipping."
        fi
    done <<< "$live_target_urls_final"

    # ParamSpider
    if command -v paramspider &>/dev/null; then
        log "Running ParamSpider for $domain_to_process..."
        paramspider_temp_outdir=$(mktemp -d paramspider_temp.XXXXXX)
        # ParamSpider output handling is tricky for versions. Try to be generic.
        # Recent paramspider may output to output/<domain>.txt or just print to stdout.
        # Redirect stdout of paramspider to catch URLs it prints
        (cd "$paramspider_temp_outdir" && paramspider -d "$domain_to_process" --exclude "$KATANA_EXCLUDE_EXTENSIONS" --quiet) >> "$RAW_OUTPUT_FILE" 2>/dev/null
        # Also check standard output location
        paramspider_outfile_v2="${paramspider_temp_outdir}/output/${domain_to_process}.txt"
        if [ -f "$paramspider_outfile_v2" ] && [ -s "$paramspider_outfile_v2" ]; then
             cat "$paramspider_outfile_v2" >> "$RAW_OUTPUT_FILE"
        fi
        rm -rf "$paramspider_temp_outdir"
    else
        warning_log "paramspider not found. Skipping."
    fi
done

log "All tools finished for all targets. Processing combined results..."

if [ ! -s "$RAW_OUTPUT_FILE" ]; then error_log "No URLs collected. Raw output file '$RAW_OUTPUT_FILE' is empty."; exit 1; fi

TEMP_URLS_EXTRACTED=$(mktemp urls_extracted.XXXXXX.txt)
TEMP_FINAL_PROCESSING_FILE=$(mktemp urls_final_processing.XXXXXX.txt)

cat "$RAW_OUTPUT_FILE" | grep -Eaio 'https?://[^[:space:]\"''`<>]+' | sed -e 's/[.,;!"%)]*$//' > "$TEMP_URLS_EXTRACTED"
if [ ! -s "$TEMP_URLS_EXTRACTED" ]; then error_log "No valid HTTP/S URLs extracted."; rm -f "$TEMP_URLS_EXTRACTED" "$TEMP_FINAL_PROCESSING_FILE"; exit 1; fi

if $STRIP_QUERY_PARAMS; then
    log "Stripping query parameters and fragments..."
    cat "$TEMP_URLS_EXTRACTED" | sed -E 's/[?#].*$//' > "$TEMP_FINAL_PROCESSING_FILE"
else
    cp "$TEMP_URLS_EXTRACTED" "$TEMP_FINAL_PROCESSING_FILE"
fi
rm "$TEMP_URLS_EXTRACTED"

cat "$TEMP_FINAL_PROCESSING_FILE" | sed -E 's#/*$##g' | sort -u > "$OUTPUT_FILE"
rm "$TEMP_FINAL_PROCESSING_FILE"

FINAL_COUNT=$(wc -l < "$OUTPUT_FILE")
if [ "$FINAL_COUNT" -eq 0 ]; then log "No unique URLs found after processing."; else log "Collected $FINAL_COUNT unique URLs: $OUTPUT_FILE"; fi
log "Script finished."
