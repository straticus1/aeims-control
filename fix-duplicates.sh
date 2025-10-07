#!/bin/bash

# Fix duplicate projection_type entries in Terraform files

cd terraform

# For each .tf file, remove duplicate projection_type lines
for file in *.tf; do
    echo "Fixing $file..."

    # Create a temporary file
    temp_file=$(mktemp)

    # Process the file to remove duplicate projection_type lines
    awk '
    BEGIN { in_gsi = 0; seen_projection = 0 }
    /global_secondary_index {/ {
        in_gsi = 1;
        seen_projection = 0;
        print;
        next
    }
    /^[[:space:]]*}[[:space:]]*$/ && in_gsi {
        in_gsi = 0;
        seen_projection = 0;
        print;
        next
    }
    /projection_type = "ALL"/ && in_gsi {
        if (!seen_projection) {
            seen_projection = 1;
            print;
        }
        next;
    }
    { print }
    ' "$file" > "$temp_file"

    # Replace the original file
    mv "$temp_file" "$file"
done

echo "Fixed duplicate projection_type entries in all Terraform files"