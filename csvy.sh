#!/bin/bash

# Define the name for the output CSV file
output_csv="mm_dataset.csv"

# Define temporary files for header and data
temp_header_file="header.tmp"
temp_data_file="data.tmp"

# --- Initialization ---
# Clear existing content from the output CSV and temporary files, or create them if they don't exist
> "$output_csv"
> "$temp_header_file"
> "$temp_data_file"

echo "Starting conversion of .txt files to CSV..."

# Get a list of all .txt files in the current directory
txt_files=(*.txt)

# Check if any .txt files were found
if [ ${#txt_files[@]} -eq 0 ]; then
    echo "No .txt files found in the current directory. Exiting."
    exit 1
fi

# --- Step 1: Generate the CSV Header ---
# We will use the first .txt file to determine the column headers.
# This assumes that all .txt files will have a similar structure and the same set of keys,
# or at least a subset of the keys found in the first file.
first_file="${txt_files[0]}"

if [ -f "$first_file" ]; then
    echo "Generating header from: $first_file"
    # Start the header with "name" (for the filename)
    echo -n "name" > "$temp_header_file"

    # Extract all unique keys from the first file, sort them alphabetically,
    # and append them to the header, separated by commas.
    # The regex '^[a-zA-Z0-9._]+' matches the key at the beginning of each line.
    grep -oE '^[a-zA-Z0-9._]+' "$first_file" | sort | uniq | while read -r key; do
        echo -n ",$key" >> "$temp_header_file"
    done
    echo "" >> "$temp_header_file" # Add a newline to complete the header row

    # Copy the generated header to the final output CSV
    cat "$temp_header_file" > "$output_csv"
else
    echo "Error: The first file '$first_file' was not found. Cannot generate header. Exiting."
    exit 1
fi

# Read the generated header keys (excluding "name") into an array
# This array will be used to ensure consistent column order when processing data.
# `tail -n +2` skips the "name" column.
header_keys=($(grep -oE '[^,]+' "$temp_header_file" | tail -n +2))
echo "Detected header keys: ${header_keys[*]}"

# --- Step 2: Process each .txt file and append data to CSV ---
echo "Processing .txt files..."

for file in "${txt_files[@]}"; do
    # Extract the filename without the .txt extension
    filename=$(basename "$file" .txt)
    echo "  Processing file: $file (as $filename)"

    # Start a new data line in the temporary data file with the filename
    echo -n "$filename" >> "$temp_data_file"

    # Declare an associative array to store key-value pairs for the current file
    declare -A file_data

    # Read the content of the current .txt file line by line
    while IFS= read -r line; do
        # Use awk to extract the first word (key) and the second word (value) from each line
        key=$(echo "$line" | awk '{print $1}')
        value=$(echo "$line" | awk '{print $2}')

        # Store the key-value pair in the associative array if both are non-empty
        if [[ -n "$key" && -n "$value" ]]; then
            file_data["$key"]="$value"
        fi
    done < "$file"

    # Iterate through the header keys to ensure consistent column order
    for key_in_header in "${header_keys[@]}"; do
        # Retrieve the value for the current header key from the file_data array
        value_to_add="${file_data["$key_in_header"]}"

        # If a key from the header is not found in the current file, use an empty string
        if [[ -z "$value_to_add" ]]; then
            value_to_add=""
        fi
        # Append the value (or empty string) to the temporary data file, prefixed with a comma
        echo -n ",$value_to_add" >> "$temp_data_file"
    done
    echo "" >> "$temp_data_file" # Add a newline to end the current row for the next file
done

# Append all processed data from the temporary data file to the final output CSV
cat "$temp_data_file" >> "$output_csv"

# --- Cleanup ---
# Remove the temporary files
rm "$temp_header_file" "$temp_data_file"

echo "CSV file '$output_csv' created successfully in the current directory."
echo "You can now open '$output_csv' with your preferred spreadsheet software."
