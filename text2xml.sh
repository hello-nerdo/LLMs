#!/bin/bash
#
# text2xml.sh - Convert text files to XML for LLM processing
#
# Converts text files to structured XML format with file paths as attributes.
# Automatically detects text files, handles multiple paths, and copies output to clipboard.
#
# USAGE:
#   ./text2xml.sh <path> [path2...] [--ext .ext1 .ext2...]
#
# EXAMPLES:
#   ./text2xml.sh .                    # All text files in current directory
#   ./text2xml.sh src/ --ext .js .ts   # Only JS/TS files from src/
#   ./text2xml.sh docs/ README.md      # Multiple paths
#
# OPTIONS:
#   --ext    Filter by file extensions (default: common text types)
#
# OUTPUT:
#   XML format: <document path='file.txt'>content</document>
#   Statistics: file count, character count, estimated tokens
#   Result copied to clipboard automatically

# Function to check if file is actually text
is_text_file() {
    local file="$1"

    # First check if file exists and is readable
    if [[ ! -r "$file" ]]; then
        return 1
    fi

    # Use file command to check mime type
    local mime_type=$(file --mime-type -b "$file" 2>/dev/null)

    # Check if it's a text file based on mime type
    if [[ "$mime_type" =~ ^text/ ]] || [[ "$mime_type" == "application/json" ]] || [[ "$mime_type" == "application/xml" ]] || [[ "$mime_type" == "application/javascript" ]] || [[ "$mime_type" == "application/x-httpd-php" ]] || [[ "$mime_type" == "application/x-sh" ]]; then
        return 0
    fi

    # Additional check for files that might be text but have wrong mime type
    # Check if file contains null bytes (binary indicator)
    if grep -q $'\x00' "$file" 2>/dev/null; then
        return 1
    fi

    # If no null bytes and file is small enough, do a more thorough check
    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    if [[ -n "$file_size" && "$file_size" -lt 1048576 ]]; then  # Less than 1MB
        # Check if file is mostly printable characters
        local total_chars=$(wc -c < "$file" 2>/dev/null || echo 0)
        local printable_chars=$(tr -d -c '[:print:][:space:]' < "$file" 2>/dev/null | wc -c 2>/dev/null || echo 0)

        if [[ $total_chars -gt 0 ]]; then
            local ratio=$((printable_chars * 100 / total_chars))
            if [[ $ratio -gt 95 ]]; then  # More than 95% printable characters
                return 0
            fi
        fi
    fi

    return 1
}

# Process single path function
path2xml() {
    local target_path="$1"
    local display_path="$2"
    local extensions=("${@:3}")
    local use_extensions=false

    # If no display path provided, use the target path
    if [[ -z "$display_path" ]]; then
        display_path="$target_path"
    fi

    # Check if extensions were provided
    if [[ ${#extensions[@]} -gt 0 ]]; then
        use_extensions=true
    fi

    # Validate target path
    if [[ -z "$target_path" ]]; then
        echo "Error: No target path provided" >&2
        echo "Usage: paths2xml <path> [--ext .ext1 .ext2 ...]" >&2
        return 1
    fi

    # Convert to absolute path if relative
    if [[ ! "$target_path" =~ ^/ ]]; then
        target_path="$(pwd)/$target_path"
    fi

    # Check if path exists
    if [[ ! -e "$target_path" ]]; then
        echo "Error: Path '$target_path' does not exist" >&2
        return 1
    fi

    # Default extensions if none provided
    if [[ ${#extensions[@]} -eq 0 ]]; then
        extensions=(".md" ".txt" ".py" ".js" ".ts" ".jsx" ".tsx" ".cpp" ".c" ".h" ".hpp" ".java" ".go" ".rs" ".rb" ".php" ".swift" ".kt" ".scala" ".r" ".m" ".mm" ".css" ".scss" ".sass" ".less" ".html" ".xml" ".json" ".yaml" ".yml" ".toml" ".ini" ".conf" ".sh" ".bash" ".zsh" ".fish" ".vim" ".lua" ".pl" ".sql" ".dockerfile" ".makefile" ".cmake" ".gradle" ".maven")
    fi

    # Function to check if file has matching extension
    has_matching_extension() {
        local file="$1"
        local filename=$(basename "$file")

        if [[ ! $use_extensions ]]; then
            return 0  # If not using extension filter, include all text files
        fi

        for ext in "${extensions[@]}"; do
            if [[ "$filename" == *"$ext" ]]; then
                return 0
            fi
        done
        return 1
    }

    # Process files
    local files_found=0
    local total_chars=0
    local output=""

    # Use find to get all files recursively
    while IFS= read -r -d '' file; do
        # Skip if not a regular file
        if [[ ! -f "$file" ]]; then
            continue
        fi

        # Check if it's actually a text file
        if ! is_text_file "$file"; then
            continue
        fi

        # Check extension if extension filter is active
        if [[ $use_extensions == true ]] && ! has_matching_extension "$file"; then
            continue
        fi

        # Get relative path from target directory, but prefix with display path
        local rel_path="${file#$target_path/}"
        if [[ "$file" == "$target_path" ]]; then
            rel_path=$(basename "$file")
        fi

        # Prepend display path if it's not just the filename
        if [[ "$display_path" != "$target_path" && "$display_path" != "." ]]; then
            if [[ "$rel_path" == "$(basename "$file")" && -f "$target_path" ]]; then
                # Single file case - use display path as is
                rel_path="$display_path"
            else
                # Directory case - prepend display path
                rel_path="$display_path/$rel_path"
            fi
        fi

        # Read file content
        local content=""
        if content=$(cat "$file" 2>/dev/null); then
            # Output in the requested format
            output+="<document path='$rel_path'>"$'\n'
            output+="$content"$'\n'
            output+="</document>"$'\n\n'

            # Count characters for token estimation
            local file_chars=${#content}
            total_chars=$((total_chars + file_chars))

            ((files_found++))
        else
            echo "Warning: Could not read file '$rel_path'" >&2
        fi

    done < <(find "$target_path" -type f -print0 2>/dev/null)

    # Output char count to stderr (will be captured)
    echo "CHAR_COUNT:$total_chars" >&2

    # Output the content
    echo "$output"

    return $files_found
}

# Main function - handles multiple paths
paths2xml() {
    local paths=()
    local extensions=()
    local use_extensions=false

    # If no arguments and stdin has data, read paths from stdin
    if [[ $# -eq 0 && ! -t 0 ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && paths+=("$line")
        done
    fi

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ext)
                shift
                use_extensions=true
                while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                    extensions+=("$1")
                    shift
                done
                ;;
            *)
                paths+=("$1")
                shift
                ;;
        esac
    done

    # Validate that at least one path was provided
    if [[ ${#paths[@]} -eq 0 ]]; then
        echo "Error: No target path(s) provided" >&2
        echo "Usage: paths2xml <path1> [path2 ...] [--ext .ext1 .ext2 ...]" >&2
        return 1
    fi

    local combined_output=""
    local total_files=0
    local total_chars=0
    local dirs_processed=0

    # Process each path
    for original_path in "${paths[@]}"; do
        # Store the original path for display
        local display_path="$original_path"
        local target_path="$original_path"

        # Convert to absolute path if relative
        if [[ ! "$target_path" =~ ^/ ]]; then
            target_path="$(pwd)/$target_path"
        fi

        # Check if path exists
        if [[ ! -e "$target_path" ]]; then
            echo "Warning: Path '$original_path' does not exist, skipping" >&2
            continue
        fi

        # Track if it's a directory
        if [[ -d "$target_path" ]]; then
            ((dirs_processed++))
        fi

        # Call path2xml and capture both stdout and stderr
        local path_result
        local path_stderr

        if [[ $use_extensions == true ]]; then
            path_result=$(path2xml "$target_path" "$display_path" "${extensions[@]}" 2>&1)
        else
            path_result=$(path2xml "$target_path" "$display_path" 2>&1)
        fi
        local path_files=$?

        # Extract char count from stderr (CHAR_COUNT:xxxx)
        local path_chars=0
        if [[ $path_result =~ CHAR_COUNT:([0-9]+) ]]; then
            path_chars="${BASH_REMATCH[1]}"
        fi

        # Remove the char count line from output
        local path_output=$(echo "$path_result" | grep -v "^CHAR_COUNT:")

        # Accumulate results
        combined_output+="$path_output"
        total_files=$((total_files + path_files))
        total_chars=$((total_chars + path_chars))
    done

    # Calculate estimated tokens (chars / 4)
    local estimated_tokens=$((total_chars / 4))

    # Add enhanced summary
    combined_output+="<!-- Statistics: -->"$'\n'
    combined_output+="<!-- Total files: $total_files -->"$'\n'
    combined_output+="<!-- Total directories: $dirs_processed -->"$'\n'
    combined_output+="<!-- Total characters: $total_chars -->"$'\n'
    combined_output+="<!-- Estimated tokens: $estimated_tokens -->"

    # Copy to clipboard
    echo -n "$combined_output" | pbcopy

    # Enhanced summary to stderr
    echo "✓ Copied to clipboard as XML" >&2
    echo "  :file_folder: Files: $total_files" >&2
    echo "  :open_file_folder: Directories: $dirs_processed" >&2
    echo "  :memo: Characters: $(printf "%'d" $total_chars)" >&2
    echo "  :dart: Estimated tokens: $(printf "%'d" $estimated_tokens)" >&2
}

# Run main if the script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  paths2xml "$@"
fi
