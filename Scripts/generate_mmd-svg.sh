#!/bin/bash

##############################################
#               CONFIGURATION
##############################################
SOURCE_DIR="./Documents/Edition-files"
DEST_DIR="./Documents/Graph"
TRANSLATIONS_DIR="./Translations/Mermaid"
MMDC="./node_modules/.bin/mmdc"
MERMAID_CONFIG="./mermaid-config.json"
MISSING_KEYS_FILE="./Translations/addedKey.json"

# Associative arrays
declare -gA TRANSLATIONS
declare -gA ALL_PLACEHOLDERS
declare -gA MISSING_KEYS_BY_LANG

# Options
PROCESS_ALL_FILES=false
TARGET_FILES=()
VALIDATE=false
AUTO_CLEAN=false
AUTO_EXECUTE=false
TARGET_LANG=""

##############################################
#               HELP
##############################################
show_help() {
    cat << EOF
Usage: $0 [LANGUAGE_OPTIONS] [FILE_OPTIONS]

Language Options:
  -fr                    Generate SVG files for French.
  -en                    Generate SVG files for English.
  -a, --all              Generate SVG files for all available languages.

File Options:
  [FILES]                List of .mmd files to process (with or without .mmd extension).
  -a                     Process all .mmd files in $SOURCE_DIR.

Other Options:
  -h, --help             Show this help message.
  -i, --install          Install prerequisites for the script.
  -v, --validate         Validate placeholders without generating files.
  -c, --clean            Automatically remove unused keys from JSON files.
  -x, --execute          Automatically execute Generation after -v and/or -c

Examples:
  $0 -i                  # Install prerequisites.
  $0 -h                  # Show help.
  $0 -fr file1.mmd       # Generate SVG for a specific file in French.
  $0 -en -a              # Generate SVG for all files in English.
  $0 -a -a               # Generate SVG for all files in all languages.
  $0 -fr -v              # Validate placeholders for French.
  $0 -en -v -c           # Validate and clean JSON files for English.
  $0 -en -v -c -x        # Validate and clean JSON files for all language and auto generate after.
EOF
}

##############################################
#         INSTALL PREREQUISITES
##############################################
install_prerequisites() {
    echo ""
    echo "🛠️ Installing prerequisites for EIDOS Translation Generator"
    echo ""

    ##############################################
    # jq
    ##############################################
    if ! command -v jq >/dev/null 2>&1; then
        echo "→ Installing jq..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v brew >/dev/null 2>&1; then
            brew install jq
        else
            echo "❌ jq not found and no supported package manager"
            exit 1
        fi
    else
        echo "→ jq already installed"
    fi

    ##############################################
    # Node.js + npm
    ##############################################
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        echo "→ Installing Node.js and npm..."
        if command -v apt-get >/dev/null 2>&1; then
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif command -v brew >/dev/null 2>&1; then
            brew install node
        else
            echo "❌ Node.js/npm not found and no supported package manager"
            exit 1
        fi
    else
        echo "→ Node.js and npm already installed"
    fi

    ##############################################
    # npm project (LOCAL)
    ##############################################
    if [[ ! -f "package.json" ]]; then
        echo "→ Initializing local npm project"
        npm init -y >/dev/null 2>&1 || {
            echo "❌ npm init failed"
            exit 1
        }
    else
        echo "→ package.json already exists"
    fi

    ##############################################
    # Mermaid CLI (LOCAL)
    ##############################################
    if [[ ! -x "node_modules/.bin/mmdc" ]]; then
        echo "→ Installing @mermaid-js/mermaid-cli locally"
        npm install @mermaid-js/mermaid-cli || {
            echo "❌ Failed to install mermaid-cli"
            exit 1
        }
    else
        echo "→ mermaid-cli already installed locally"
    fi

    ##############################################
    # Verify mmdc
    ##############################################
    if [[ ! -x "node_modules/.bin/mmdc" ]]; then
        echo "❌ mmdc binary not found after installation"
        exit 1
    fi

    ##############################################
    # Directories
    ##############################################
    echo "→ Creating required directories"
    mkdir -p "$SOURCE_DIR"
    mkdir -p "$DEST_DIR"
    mkdir -p "$TRANSLATIONS_DIR"
    mkdir -p "$(dirname "$MISSING_KEYS_FILE")"

    echo ""
    echo "✅ Installation completed successfully"
    echo "→ mmdc: $(realpath node_modules/.bin/mmdc)"
    echo ""
}


##############################################
#          FILE SEARCH
##############################################
find_file() {
    local target="$1"

    # Add .mmd if missing
    if [[ ! "$target" =~ \.mmd$ ]]; then
        target="${target}.mmd"
    fi

    # Search for the file
    local found=$(find "$SOURCE_DIR" -type f -name "$(basename "$target")" -o -path "*/$(basename "$target")" | head -n 1)

    if [[ -z "$found" ]]; then
        echo "❌ File not found: $target" >&2
        return 1
    fi

    echo "$found"
    return 0
}

get_files_to_process() {
    if [[ "$PROCESS_ALL_FILES" == true ]]; then
        find "$SOURCE_DIR" -type f -name "*.mmd"
    else
        for target in "${TARGET_FILES[@]}"; do
            find_file "$target"
        done
    fi
}

##############################################
# Progress bar function
##############################################
show_progress_bar() {
    local current=$1
    local total=$2

    # PROTECTION ABSOLUE
    (( total <= 0 )) && return 0

    local width=20
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))

    local elapsed_time=$SECONDS
    local remaining_time=0
    if (( current > 0 )); then
        local time_per_item=$((elapsed_time / current))
        remaining_time=$(((total - current) * time_per_item))
    fi

    printf "\r   ["
    printf "%${completed}s" | tr ' ' '#'
    printf "%${remaining}s" | tr ' ' '-'
    printf "] %3d%%" "$percentage"

    if (( current > 0 )); then
        printf " | ETA: %02dm%02ds" \
            $((remaining_time / 60)) \
            $((remaining_time % 60))
    fi
}
print_message_above_bar() {
    local msg="$1"
    tput sc          # save cursor
    tput cuu1        # move up 1 line
    tput el          # clear the line
    echo "$msg"
    tput rc          # restore cursor
}    
##############################################
# Extract and Check PlaceHolders
##############################################
extract_placeholders() {
    local file="$1"
    grep -oP '\{\{[A-Z_][A-Z0-9_]*\}\}' "$file" | sed 's/[{}]//g' | sort -u
}

scan_all_placeholders() {
    echo ""
    echo "🔍 Scanning placeholders in .mmd files..."
    sleep 0.3

    ALL_PLACEHOLDERS=()

    files_to_scan=()
    while IFS= read -r file; do
        files_to_scan+=("$file")
    done < <(get_files_to_process)

    total_files=${#files_to_scan[@]}
    current=0
    SECONDS=0  # Réinitialiser le compteur de temps

    for file in "${files_to_scan[@]}"; do
        ((current++))
        rel_path="${file#$SOURCE_DIR/}"

        while IFS= read -r placeholder; do
            if [[ -n "$placeholder" ]]; then
                ALL_PLACEHOLDERS["$placeholder"]=1
            fi
        done < <(extract_placeholders "$file")

        show_progress_bar "$current" "$total_files"
        sleep 0.05
    done

    echo ""
    echo ""
    local elapsed_time=$SECONDS
    echo "✅ ${#ALL_PLACEHOLDERS[@]} unique placeholders found in $elapsed_time seconds"
    sleep 0.2
}


##############################################
# Prepare keys with values and files
##############################################
prepare_keys_with_values() {
    local lang="$1"
    local values_array_name="$2"
    local files_array_name="$3"
    shift 3
    local keys=("$@")
    
    local dir="$TRANSLATIONS_DIR/$lang"

    for key in "${keys[@]}"; do
        local values_seen=()
        local file_list=()
        
        for json_file in "$dir"/*.json; do
            [[ ! -f "$json_file" ]] && continue
            
            if jq -e --arg k "$key" 'has($k)' "$json_file" >/dev/null 2>&1; then
                local v=$(jq -r --arg k "$key" '.[$k]' "$json_file" 2>/dev/null)
                [[ -n "$v" && "$v" != "null" ]] && values_seen+=("$v")
                file_list+=("$(basename "$json_file")")
            fi
        done
        
        # Get unique values
        local unique_values=()
        if [[ ${#values_seen[@]} -gt 0 ]]; then
            mapfile -t unique_values < <(printf '%s\n' "${values_seen[@]}" | sort -u)
        fi
        
        # Store in the arrays using eval
        eval "${values_array_name}[\"${key}\"]=\"\$(IFS='|'; echo \"\${unique_values[*]}\")\""
        eval "${files_array_name}[\"${key}\"]=\"\$(IFS=','; echo \"\${file_list[*]}\")\""
    done
}

##############################################
# Validate placeholders
##############################################
validate_placeholders() {
    local lang="$1"
    local missing_keys_file="./Translations/addedKey.json"
    local duplicate_keys_file="./Translations/duplicateKey.json"

    echo ""
    echo "=============================="
    echo "   🔍 Validation: $lang"
    echo "=============================="
    sleep 0.3

    load_translations "$lang" || return 1

    local missing_keys=()
    local unused_keys=()
    declare -A key_files

    # ----------------------------
    # Check for missing keys
    # ----------------------------
    echo "→ Checking for missing keys..."
    sleep 0.2
    
    local total_placeholders=${#ALL_PLACEHOLDERS[@]}
    local current=0
    local SECONDS=0

    for placeholder in "${!ALL_PLACEHOLDERS[@]}"; do
        ((current++))
        if [[ ! -v TRANSLATIONS["$placeholder"] || -z "${TRANSLATIONS[$placeholder]}" ]]; then
            missing_keys+=("$placeholder")
        fi
        
        show_progress_bar "$current" "$total_placeholders"
    done

    show_progress_bar "$total_placeholders" "$total_placeholders"
    echo ""
    
    # Prepare missing keys for JSON save
    local keys_to_save_missing=()
    for key in "${missing_keys[@]}"; do
        keys_to_save_missing+=("$lang:$key::")
    done

    # ----------------------------
    # Check for unused keys
    # ----------------------------
    echo "→ Checking for unused keys..."
    sleep 0.2
    
    local total_translations=${#TRANSLATIONS[@]}
    current=0
    SECONDS=0  # reset timer

    for key in "${!TRANSLATIONS[@]}"; do
        ((current++))

        if [[ -z "${ALL_PLACEHOLDERS[$key]}" ]]; then
            unused_keys+=("$key")
        fi

        show_progress_bar "$current" "$total_translations"
    done

    # Forcer état final
    show_progress_bar "$total_translations" "$total_translations"
    echo ""

    # ----------------------------
    # Check for duplicates
    # ----------------------------
    echo "→ Checking for duplicates..."
    sleep 0.2
    local dir="$TRANSLATIONS_DIR/$lang"
    
    local json_files=("$dir"/*.json)
    local total_json_files=0
    for f in "${json_files[@]}"; do
        [[ -f "$f" ]] && ((total_json_files++))
    done
    
    SECONDS=0
    current=0
    total_json_files=${#json_files[@]}

    for json_file in "${json_files[@]}"; do
        [[ ! -f "$json_file" ]] && continue
        ((current++))

        show_progress_bar "$current" "$total_json_files"

        filename=$(basename "$json_file")
        while read -r key; do
            clean_key=${key//$'\r'/}
            [[ -z "$clean_key" ]] && continue

            if [[ -z "${key_files[$clean_key]}" ]]; then
                key_files["$clean_key"]="$filename"
            else
                key_files["$clean_key"]+=",${filename}"
            fi
        done < <(jq -r 'keys[]' "$json_file" 2>/dev/null)
    done
    show_progress_bar 1 1 

    echo ""


    # Prepare duplicate keys with values
    declare -A duplicate_keys_values
    declare -A duplicate_keys_files
    
    # Convert key_files keys to array
    local all_keys=("${!key_files[@]}")
    
    # Call prepare_keys_with_values correctly
    if [[ ${#all_keys[@]} -gt 0 ]]; then
        echo "→ Analyzing duplicate values..."
        sleep 0.2
        prepare_keys_with_values "$lang" "duplicate_keys_values" "duplicate_keys_files" "${all_keys[@]}"
    fi

    local keys_to_save_duplicate=()
    local duplicate_entries=()
    
    for key in "${!duplicate_keys_files[@]}"; do
        # Keep only duplicates (keys in multiple files)
        if [[ "${duplicate_keys_files[$key]}" == *","* ]]; then
            local value="${duplicate_keys_values[$key]}"
            local files="${duplicate_keys_files[$key]}"
            keys_to_save_duplicate+=("$lang:$key:$value:$files")
            duplicate_entries+=("$key ($files | values: $value)")
        fi
    done

    # ----------------------------
    # Display results
    # ----------------------------
    echo ""
    sleep 0.3
    echo "┌────────────────────────────┐"
    echo "   📊 Validation Results"
    echo "└────────────────────────────┘"
    sleep 0.2

    local has_issues=false

    # Missing keys
    if [[ ${#missing_keys[@]} -gt 0 ]]; then
        has_issues=true
        echo ""
        echo "❌ MISSING keys in JSON (${#missing_keys[@]}):"
        sleep 0.1
        for key in "${missing_keys[@]}"; do
            echo "   - $key"
        done
    fi

    # Unused keys
    if [[ ${#unused_keys[@]} -gt 0 ]]; then
        has_issues=true
        echo ""
        echo "⚠️  UNUSED keys in JSON (${#unused_keys[@]}):"
        sleep 0.1
        for key in "${unused_keys[@]}"; do
            echo "   - $key"
        done
    fi

    # Duplicate keys
    if [[ ${#duplicate_entries[@]} -gt 0 ]]; then
        has_issues=true
        echo ""
        echo "⚠️  DUPLICATE keys between files (${#duplicate_entries[@]}):"
        sleep 0.1
        for entry in "${duplicate_entries[@]}"; do
            echo "   - $entry"
        done
    fi

    # Success
    if [[ "$has_issues" == false ]]; then
        echo ""
        echo "✅ No issues detected!"
        sleep 0.1
        echo "   - ${#ALL_PLACEHOLDERS[@]} placeholders used"
        sleep 0.05
        echo "   - ${#TRANSLATIONS[@]} keys available"
        sleep 0.05
        echo "   - Perfect match ✨"
        sleep 0.1
    fi

    echo ""

    # ----------------------------
    # Save keys
    # ----------------------------
    [[ ${#keys_to_save_missing[@]} -gt 0 ]] && save_keys_with_values_to_json "$missing_keys_file" "${keys_to_save_missing[@]}"
    [[ ${#keys_to_save_duplicate[@]} -gt 0 ]] && save_keys_with_values_to_json "$duplicate_keys_file" "${keys_to_save_duplicate[@]}"

    # ----------------------------
    # Suggest cleaning unused keys
    # ----------------------------
    if [[ ${#unused_keys[@]} -gt 0 ]]; then
        if [[ "$AUTO_CLEAN" == true ]]; then
            clean_unused_keys "$lang" "${unused_keys[@]}"
        else
            echo "💡 Tip: Use -c or --clean to automatically remove unused keys"
            echo ""
        fi
    fi

    return 0
}

##############################################
# Save missing/deleted key for PlaceHolders
##############################################
save_keys_with_values_to_json() {
    local json_file="$1"
    shift
    local entries=("$@")

    echo ""
    echo "💾 Saving keys with values to $json_file..."
    sleep 0.2
    mkdir -p "$(dirname "$json_file")"

    local json_output="{}"
    if [[ -f "$json_file" ]]; then
        json_output=$(cat "$json_file")
        if ! jq -e 'type=="object"' <<< "$json_output" >/dev/null 2>&1; then
            echo "⚠️  Existing JSON is not an object, resetting to {}" >&2
            json_output="{}"
        fi
    fi

    local total_entries=${#entries[@]}
    local current=0

    for entry in "${entries[@]}"; do
        ((current++))
        
        # Parse lang:key:value[:files]
        IFS=':' read -r lang key value files <<< "$entry"
        files=${files:-""}

        # Prepare all_values if value contains multiple values separated by |
        if [[ -n "$value" ]]; then
            IFS='|' read -ra all_values_array <<< "$value"
            local main_value="${all_values_array[0]}"

            if [[ ${#all_values_array[@]} -gt 1 ]]; then
                local all_values_json=$(printf '%s\n' "${all_values_array[@]}" | jq -R . | jq -s .)
                json_output=$(jq --arg lang "$lang" --arg key "$key" --arg value "$main_value" \
                    --arg files "$files" --argjson all_values "$all_values_json" \
                    '.[$lang][$key]={value:$value, files:($files|split(",")|map(select(length>0))), all_values:$all_values}' \
                    <<< "$json_output")
            else
                json_output=$(jq --arg lang "$lang" --arg key "$key" --arg value "$main_value" \
                    --arg files "$files" \
                    '.[$lang][$key]={value:$value, files:($files|split(",")|map(select(length>0)))}' \
                    <<< "$json_output")
            fi
        else
            # Empty value case
            json_output=$(jq --arg lang "$lang" --arg key "$key" \
                --arg files "$files" \
                '.[$lang][$key]={value:"", files:($files|split(",")|map(select(length>0)))}' \
                <<< "$json_output")
        fi
        
        # Show progress
        show_progress_bar "$current" "$total_entries"
        sleep 0.02

    done
    show_progress_bar "$total_entries" "$total_entries"
    echo ""

    # Write atomically
    local tmp
    tmp=$(mktemp) || { echo "❌ mktemp failed"; return 1; }
    echo "$json_output" | jq . > "$tmp" || { echo "❌ jq failed"; rm -f "$tmp"; return 1; }
    mv "$tmp" "$json_file" || { echo "❌ mv failed"; rm -f "$tmp"; return 1; }

    echo ""
    echo "✅ Keys saved to $json_file"
    sleep 0.2
}

##############################################
# Clean Keys
##############################################
clean_unused_keys() {
    local lang="$1"
    shift
    local unused_keys=("$@")
    local deleted_keys_file="./Translations/deletedKey.json"

    echo "🧹 Cleaning unused keys..."
    sleep 0.3

    local dir="$TRANSLATIONS_DIR/$lang"
    local cleaned_count=0

    # Prepare values and files for each unused key
    echo "→ Preparing key information..."
    sleep 0.2
    declare -A deleted_keys_values
    declare -A deleted_keys_files
    prepare_keys_with_values "$lang" "deleted_keys_values" "deleted_keys_files" "${unused_keys[@]}"

    # Remove unused keys from JSON files
    local json_files=("$dir"/*.json)
    local total_files=0
    for f in "${json_files[@]}"; do
        [[ -f "$f" ]] && ((total_files++))
    done
    
    local current_file=0

    echo "→ Removing keys from JSON files..."
    echo ""
    
    for json_file in "${json_files[@]}"; do
        [[ ! -f "$json_file" ]] && continue
        ((current_file++))

        local filename=$(basename "$json_file")
        local temp_file="${json_file}.tmp"
        local file_cleaned=false
        local json_content
        json_content=$(cat "$json_file")

        local keys_in_file=0
        for key in "${unused_keys[@]}"; do
            if jq -e --arg k "$key" 'has($k)' "$json_file" >/dev/null 2>&1; then
                json_content=$(echo "$json_content" | jq "del(.\"$key\")")
                echo "   ✓ Removed: $key (from $filename)"
                ((cleaned_count++))
                ((keys_in_file++))
                file_cleaned=true
                sleep 0.02
            fi
        done

        if [[ "$file_cleaned" == true ]]; then
            echo "$json_content" | jq . > "$temp_file"
            mv "$temp_file" "$json_file"
        fi
        
        show_progress_bar "$current_file" "$total_files"
        sleep 0.05
    done
    show_progress_bar "$total_files" "$total_files"
    echo ""

    # Prepare and save entries for JSON
    echo "→ Saving deleted keys information..."
    sleep 0.2
    local keys_to_save_deleted=()
    for key in "${unused_keys[@]}"; do
        local value="${deleted_keys_values[$key]}"
        local files="${deleted_keys_files[$key]}"
        keys_to_save_deleted+=("$lang:$key:$value:$files")
    done
    save_keys_with_values_to_json "$deleted_keys_file" "${keys_to_save_deleted[@]}"

    echo ""
    echo "✅ $cleaned_count key(s) removed"
    sleep 0.2
    echo ""
}

##############################################
# Load translations for a specific language
##############################################
load_translations() {
    local lang="$1"
    local dir="$TRANSLATIONS_DIR/$lang"

    echo "→ Loading translations from: $dir"
    sleep 0.2

    # Check if directory exists
    if [[ ! -d "$dir" ]]; then
        echo "⚠️ Warning: Translation directory not found: $dir"
        return 0
    fi

    # Reset associative array
    TRANSLATIONS=()

    # Load all JSON files
    local count=0
    local json_files=("$dir"/*.json)
    local total_files=0
    
    for f in "${json_files[@]}"; do
        [[ -f "$f" ]] && ((total_files++))
    done
    
    local current_file=0
    
    for json_file in "${json_files[@]}"; do
        [[ ! -f "$json_file" ]] && continue
        ((current_file++))

        # Read each key=value pair
        while IFS="=" read -r key value; do
            TRANSLATIONS["$key"]="$value"
            ((count++))
        done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$json_file" 2>/dev/null)
        
        show_progress_bar "$current_file" "$total_files"
        sleep 0.05
    done
    show_progress_bar "$total_files" "$total_files"
    echo ""

    echo ""
    echo "✅ $count keys loaded"
    echo ""
    sleep 0.2
    return 0
}

##############################################
# Apply translations to a .mmd file
##############################################
apply_translations() {
    local file="$1"
    local content
    content=$(cat "$file")

    for key in "${!TRANSLATIONS[@]}"; do
        value="${TRANSLATIONS[$key]}"
        # Escape special characters for sed
        escaped_value=$(printf '%s\n' "$value" | sed 's/[&/\]/\\&/g')
        content=$(printf '%s\n' "$content" | sed "s/{{$key}}/$escaped_value/g")
    done

    printf '%s\n' "$content"
}

##############################################
# Convert .mmd to .svg
##############################################
convert_to_svg() {
    local input="$1"
    local output="$2"

    # If a config file exists, use it
    if [[ -f "$MERMAID_CONFIG" ]]; then
        output=$($MMDC -i "$input" -o "$output" -c "$MERMAID_CONFIG" -b transparent 2>&1 >/dev/null)
        status=$?
        if [[ $status -ne 0 ]]; then
            echo "❌ Failed: $output"
        fi
    else
        # Otherwise, use dark theme via command line
        output=$($MMDC -i "$input" -o "$output" -t dark -b transparent 2>&1 >/dev/null)
        status=$?
        if [[ $status -ne 0 ]]; then
            echo "❌ Failed: $output"
        fi
    fi

    # Delete temp file
    rm -f "$tmp"

    return $?
}

##############################################
# Process a specific language
##############################################
process_language() {
    local lang="$1"
    local files_to_process=()
    local file
    local rel_path
    local subdir
    local filename
    local name
    local tmp
    local svg
    local start_time
    local end_time
    local total_time
    local errors=0

    echo ""
    echo "=============================="
    echo "   🌍 Language: $lang"
    echo "=============================="
    sleep 0.3

    # Load translations
    load_translations "$lang" || echo "⚠️ Warning: No translations loaded for $lang"

    # Create output directory for the language
    local OUTPUT="$DEST_DIR/$lang"
    mkdir -p "$OUTPUT"

    # Get the list of files to process
    files_to_process=()
    while IFS= read -r file; do
        files_to_process+=("$file")
    done < <(get_files_to_process)

    local total_files=${#files_to_process[@]}
    local current=0

    if [[ $total_files -eq 0 ]]; then
        echo "❌ No files to process"
        return 1
    fi

    echo ""
    echo "→ $total_files Mermaid file(s) to process"
    echo ""
    sleep 0.3

    # Start timer
    start_time=$(date +%s)

    for file in "${files_to_process[@]}"; do
        ((current++))

        rel_path="${file#$SOURCE_DIR/}"
        subdir="$(dirname "$rel_path")"
        mkdir -p "$OUTPUT/$subdir"

        filename="$(basename -- "$file")"
        name="${filename%.*}"
        tmp="/tmp/${name}_${lang}.mmd"
        svg="$OUTPUT/$subdir/$name.svg"

        # Generate translated MMD file
        apply_translations "$file" > "$tmp"

        # Convert to SVG silently
        if ! convert_to_svg "$tmp" "$svg" >/dev/null 2>&1; then
            ((errors++))
            echo "" 
            print_message_above_bar "❌ Failed to generate: $file"
        else
            echo "" 
            print_message_above_bar "   ✓ Generated: $svg"
        fi

        # Update progress bar (always on last line)
        show_progress_bar "$current" "$total_files"
        sleep 0.05
    done

    # Add a newline after finishing the bar
    echo ""

    # Calculate total time
    end_time=$(date +%s)
    total_time=$((end_time - start_time))

    echo ""
    echo ""
    sleep 0.3

    if [[ $errors -gt 0 ]]; then
        echo "✓ Done with $errors warning(s) out of $total_files files in $total_time seconds."
    else
        echo "✓ All files processed successfully in $total_time seconds."
    fi
    sleep 0.3
}

##############################################
# Process all languages
##############################################
process_all_languages() {
    local lang
    local lang_list=($(find "$TRANSLATIONS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

    if [[ ${#lang_list[@]} -eq 0 ]]; then
        echo "❌ No language directory found in $TRANSLATIONS_DIR"
        return 1
    fi

    echo "🌍 Detected languages: ${lang_list[*]}"
    echo ""
    sleep 0.3

    local total_langs=${#lang_list[@]}
    local current_lang=0

    for lang in "${lang_list[@]}"; do
        ((current_lang++))
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Language $current_lang/$total_langs: $lang"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        sleep 0.2
        process_language "$lang"
    done
    
    echo ""
    echo "✅ All languages processed!"
    sleep 0.3
}
##############################################
# Auto-execute conversion if flag is set
##############################################
auto_execute_conversion() {
    if [[ "$AUTO_EXECUTE" == true ]]; then
        echo ""
        echo "🚀 Auto-executing conversion..."
        sleep 0.3
        
        if [[ "$TARGET_LANG" == "all" ]]; then
            process_all_languages
        else
            process_language "$TARGET_LANG"
        fi
    fi
}

##############################################
#         PROCESS ARGUMENTS
##############################################
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Process language options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--install)
                install_prerequisites
                exit 0
                ;;
            -v|--validate)
                VALIDATE=true
                shift
                ;;
            -fr)
                TARGET_LANG="fr"
                shift
                ;;
            -en)
                TARGET_LANG="en"
                shift
                ;;
            -a|--all)
                if [[ -z "$TARGET_LANG" ]]; then
                    TARGET_LANG="all"
                else
                    PROCESS_ALL_FILES=true
                fi
                shift
                ;;
            -c|--clean)
                AUTO_CLEAN=true
                shift
                ;;
            -x|--execute)
                AUTO_EXECUTE=true
                shift
                ;;
            -*)
                echo "❌ Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                TARGET_FILES+=("$1")
                shift
                ;;
        esac
    done

    # If no files are specified, process all files
    if [[ ${#TARGET_FILES[@]} -eq 0 ]]; then
        PROCESS_ALL_FILES=true
    fi
}

##############################################
#              MAIN PROGRAM
##############################################
parse_arguments "$@"

# Display selected options
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║   🚀 EIDOS Translation Generator      ║"
echo "╚═══════════════════════════════════════╝"
echo ""
sleep 0.3

#  Execution flags
if [[ "$VALIDATE" == true ]]; then
    echo ""
    echo "🔍 Mode: VALIDATION"
    echo ""
    sleep 0.3

    # Delete previous reports
    rm -f "./Translations/addedKey.json"
    rm -f "./Translations/duplicateKey.json"
    
    # Scan placeholders
    scan_all_placeholders

    # Validate placeholders for each language
    LANG_LIST=($(find "$TRANSLATIONS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

    if [[ ${#LANG_LIST[@]} -eq 0 ]]; then
        echo "❌ No language directory found."
        exit 1
    fi

    if [[ "$TARGET_LANG" == "all" ]]; then
        total_langs=${#LANG_LIST[@]}
        current_lang=0
        
        for lang in "${LANG_LIST[@]}"; do
            ((current_lang++))
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Validating language $current_lang/$total_langs"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            sleep 0.2
            validate_placeholders "$lang"
        done
    else
        validate_placeholders "$TARGET_LANG"
    fi

    echo ""
    echo "✅ Validation completed."
    sleep 0.3
    
    auto_execute_conversion
    exit 0
elif [[ "$AUTO_CLEAN" == true ]]; then
    echo ""
    echo "🧹 Mode: Clean"
    echo ""
    sleep 0.3

    # Scan placeholders first
    scan_all_placeholders

    # Clean unused keys
    if [[ "$TARGET_LANG" == "all" ]]; then
        LANG_LIST=($(find "$TRANSLATIONS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))
        
        total_langs=${#LANG_LIST[@]}
        current_lang=0
        
        for lang in "${LANG_LIST[@]}"; do
            ((current_lang++))
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Cleaning language $current_lang/$total_langs: $lang"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            sleep 0.2
            
            load_translations "$lang"
            unused_keys=()
            for key in "${!TRANSLATIONS[@]}"; do
                if [[ -z "${ALL_PLACEHOLDERS[$key]}" ]]; then
                    unused_keys+=("$key")
                fi
            done
            if [[ ${#unused_keys[@]} -gt 0 ]]; then
                clean_unused_keys "$lang" "${unused_keys[@]}"
            else
                echo "✅ No unused keys found for $lang"
                sleep 0.2
            fi
        done
    else
        load_translations "$TARGET_LANG"
        unused_keys=()
        for key in "${!TRANSLATIONS[@]}"; do
            if [[ -z "${ALL_PLACEHOLDERS[$key]}" ]]; then
                unused_keys+=("$key")
            fi
        done
        if [[ ${#unused_keys[@]} -gt 0 ]]; then
            clean_unused_keys "$TARGET_LANG" "${unused_keys[@]}"
        else
            echo "✅ No unused keys found for $TARGET_LANG"
            sleep 0.2
        fi
    fi
    
    echo ""
    echo "✅ Cleaning completed."
    sleep 0.3

    auto_execute_conversion
    exit 0
elif [[ "$TARGET_LANG" == "all" ]]; then
    echo "🌍 Generating SVG files for all languages"
    sleep 0.3
    process_all_languages
    exit 0
else
    echo "🌐 Generating SVG files for $TARGET_LANG"
    sleep 0.3
    process_language "$TARGET_LANG"
    exit 0
fi