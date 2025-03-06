#!/bin/bash

# Function to insert data into a table
insert_into_table() {
    local db_path="$1"
    local metadata_file="$db_path/metadata.csv"

    show_banner "Insert Data"

    # Check if metadata file exists
    if [ ! -f "$metadata_file" ]; then
        show_error "No tables found in this database."
        return 1
    fi

    # List available tables
    local table_names=$(grep -v "^table_name" "$metadata_file" | cut -d',' -f1 | sort | uniq)
    if [ -z "$table_names" ]; then
        show_error "No tables found in this database."
        return 1
    fi

    echo -e "${COLOR_WHITE}Available tables:${COLOR_RESET}"
    select table_name in $table_names; do
        if [ -n "$table_name" ]; then
            break
        else
            show_error "Invalid selection."
        fi
    done

    # Get table metadata
    local metadata=$(get_table_metadata "$db_path" "$table_name")
    if [ -z "$metadata" ]; then
        show_error "Failed to retrieve table metadata."
        return 1
    fi

    local columns=$(echo "$metadata" | cut -d'|' -f1)
    local types=$(echo "$metadata" | cut -d'|' -f2)
    local pk_column=$(echo "$metadata" | cut -d'|' -f3)

    # Prepare data file
    local data_file="$db_path/$table_name.csv"
    if [ ! -f "$data_file" ]; then
        touch "$data_file"
        echo "$columns" > "$data_file"
    fi

    # Initialize record as an array to properly handle all columns
    local columns_arr=()
    local types_arr=()
    local values=()
    
    # Convert comma-separated list to arrays
    IFS=',' read -r -a columns_arr <<< "$columns"
    IFS=',' read -r -a types_arr <<< "$types"
    
    # Initialize values array with empty strings
    for ((i=0; i<${#columns_arr[@]}; i++)); do
        values[i]=""
    done
    
    echo -e "\n${COLOR_CYAN}Entering data for table '$table_name':${COLOR_RESET}"
    
    # Collect data for each column
    for ((i=0; i<${#columns_arr[@]}; i++)); do
        local column="${columns_arr[$i]}"
        local type="${types_arr[$i]}"
        local is_pk=0
        
        # Check if this is the primary key column
        if [ "$column" == "$pk_column" ]; then
            is_pk=1
        fi
        
        while true; do
            read -p "$(prompt_text "Enter value for $column ($type)")" input_value
            
            # For non-primary key fields, allow skipping (will default to empty for string)
            if [ -z "$input_value" ] && [ $is_pk -eq 0 ] && [ "$type" == "string" ]; then
                values[$i]=""
                break
            # For primary keys and integers, require a valid value
            elif [ -z "$input_value" ] && ([ $is_pk -eq 1 ] || [ "$type" == "int" ]); then
                show_error "Value cannot be empty for $column ($type)"
                continue
            fi
            
            # Validate the input value
            if validate_value "$input_value" "$type" "$column"; then
                # For primary key, check uniqueness
                if [ $is_pk -eq 1 ]; then
                    if grep -q "^$input_value," "$data_file" || grep -q ",$input_value," "$data_file"; then
                        show_error "Primary key '$input_value' already exists!"
                        continue
                    fi
                fi
                
                # Store the valid value (escaped if needed)
                values[$i]=$(escape_csv "$input_value")
                break
            fi
        done
    done
    
    # Build the record string
    local record=""
    for ((i=0; i<${#values[@]}; i++)); do
        record+="${values[$i]},"
    done
    record="${record%,}"  # Remove trailing comma
    
    # Append record to data file
    echo "$record" >> "$data_file"
    show_success "Record inserted successfully into table '$table_name'."
    
    return 0
}

# Function to select data from a table
select_from_table() {
    local db_path="$1"
    local metadata_file="$db_path/metadata.csv"

    show_banner "Select Data"

    # Check if metadata file exists
    if [ ! -f "$metadata_file" ]; then
        show_error "No tables found in this database."
        return 1
    fi

    # List available tables
    local table_names=$(grep -v "^table_name" "$metadata_file" | cut -d',' -f1 | sort | uniq)
    if [ -z "$table_names" ]; then
        show_error "No tables found in this database."
        return 1
    fi

    echo -e "${COLOR_WHITE}Available tables:${COLOR_RESET}"
    select table_name in $table_names; do
        if [ -n "$table_name" ]; then
            break
        else
            show_error "Invalid selection."
        fi
    done

    # Get table metadata
    local metadata=$(get_table_metadata "$db_path" "$table_name")
    local pk_column=$(echo "$metadata" | cut -d'|' -f3)
    local data_file="$db_path/$table_name.csv"

    if [ ! -f "$data_file" ]; then
        show_error "Table '$table_name' has no data."
        return 1
    fi

    # Prompt for selection type
    echo -e "\n${COLOR_WHITE}Select option:${COLOR_RESET}"
    select opt in "All records" "By primary key"; do
        case $opt in
            "All records")
                echo
                column -t -s ',' < "$data_file" | while read -r line; do
                    echo -e "  ${COLOR_CYAN}$line${COLOR_RESET}"
                done
                break
                ;;
            "By primary key")
                read -p "$(prompt_text "Enter $pk_column value")" pk_value
                result=$(grep -E "(^$pk_value,|,$pk_value,|,$pk_value$)" "$data_file")
                if [ -n "$result" ]; then
                    echo
                    echo -e "  ${COLOR_GREEN}$(echo "$result" | column -t -s ',')${COLOR_RESET}"
                else
                    show_error "No record found with $pk_column = $pk_value"
                fi
                break
                ;;
            *) show_error "Invalid option" ;;
        esac
    done
    
    return 0
}

# Function to update data in a table
update_table() {
    local db_path="$1"
    local metadata_file="$db_path/metadata.csv"

    show_banner "Update Data"

    # Check if metadata file exists
    if [ ! -f "$metadata_file" ]; then
        show_error "No tables found in this database."
        return 1
    fi

    # List available tables
    local table_names=$(grep -v "^table_name" "$metadata_file" | cut -d',' -f1 | sort | uniq)
    if [ -z "$table_names" ]; then
        show_error "No tables found in this database."
        return 1
    fi

    echo -e "${COLOR_WHITE}Available tables:${COLOR_RESET}"
    select table_name in $table_names; do
        if [ -n "$table_name" ]; then
            break
        else
            show_error "Invalid selection."
        fi
    done

    # Get table metadata
    local metadata=$(get_table_metadata "$db_path" "$table_name")
    local columns_str=$(echo "$metadata" | cut -d'|' -f1)
    local types_str=$(echo "$metadata" | cut -d'|' -f2)
    local pk_column=$(echo "$metadata" | cut -d'|' -f3)

    # Convert comma-separated columns to array
    IFS=',' read -r -a columns <<< "$columns_str"
    IFS=',' read -r -a types <<< "$types_str"

    # Get data file
    local data_file="$db_path/$table_name.csv"
    if [ ! -f "$data_file" ]; then
        show_error "Table '$table_name' has no data."
        return 1
    fi

    # Display current data
    echo -e "\n${COLOR_CYAN}Current records:${COLOR_RESET}"
    column -t -s ',' < "$data_file"

    # Get primary key value
    read -p "$(prompt_text "Enter $pk_column value to update")" pk_value

    # Find record
    local record_line=$(grep -n -E "(^$pk_value,|,$pk_value,|,$pk_value$)" "$data_file" | cut -d':' -f1)
    if [ -z "$record_line" ]; then
        show_error "No record found with $pk_column = $pk_value"
        return 1
    fi

    # Get current record
    local current_record=$(sed -n "${record_line}p" "$data_file")
    echo -e "\n${COLOR_CYAN}Updating record:${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}$(echo "$current_record" | column -t -s ',')${COLOR_RESET}"

    # Create new record
    local new_record=""
    local pk_index=0

    # Find PK column index
    for i in "${!columns[@]}"; do
        if [ "${columns[$i]}" == "$pk_column" ]; then
            pk_index=$i
            break
        fi
    done

    # Update fields
    IFS=',' read -r -a current_values <<< "$current_record"
    for i in "${!columns[@]}"; do
        local column="${columns[$i]}"
        local type="${types[$i]}"
        local current_value="${current_values[$i]}"
        
        # Skip primary key to prevent modification
        if [ "$i" -eq "$pk_index" ]; then
            new_record+="$current_value,"
            continue
        fi
        
        read -p "$(prompt_text "Update $column ($type) [current: $current_value]")" new_value
        
        # If empty, keep current value
        if [ -z "$new_value" ]; then
            new_record+="$current_value,"
        else
            # Validate and add new value
            if validate_value "$new_value" "$type" "$column"; then
                new_record+="$(escape_csv "$new_value"),"
            else
                # If invalid, keep current value
                new_record+="$current_value,"
            fi
        fi
    done

    # Remove trailing comma
    new_record="${new_record%,}"

    # Update record in file
    sed -i "${record_line}s/.*/$new_record/" "$data_file"
    
    echo -e "\n${COLOR_GREEN}Record updated successfully!${COLOR_RESET}"
    return 0
}

# Function to delete data from a table
delete_from_table() {
    local db_path="$1"
    local metadata_file="$db_path/metadata.csv"

    show_banner "Delete Data"

    # Check if metadata file exists
    if [ ! -f "$metadata_file" ]; then
        show_error "No tables found in this database."
        return 1
    fi

    # List available tables
    local table_names=$(grep -v "^table_name" "$metadata_file" | cut -d',' -f1 | sort | uniq)
    if [ -z "$table_names" ]; then
        show_error "No tables found in this database."
        return 1
    fi

    echo -e "${COLOR_WHITE}Available tables:${COLOR_RESET}"
    select table_name in $table_names; do
        if [ -n "$table_name" ]; then
            break
        else
            show_error "Invalid selection."
        fi
    done

    # Get table metadata
    local metadata=$(get_table_metadata "$db_path" "$table_name")
    local pk_column=$(echo "$metadata" | cut -d'|' -f3)
    local data_file="$db_path/$table_name.csv"

    if [ ! -f "$data_file" ]; then
        show_error "Table '$table_name' has no data."
        return 1
    fi

    # Display current data
    echo -e "\n${COLOR_CYAN}Current records:${COLOR_RESET}"
    column -t -s ',' < "$data_file"

    # Get primary key value
    read -p "$(prompt_text "Enter $pk_column value to delete")" pk_value

    # Delete record
    local temp_file=$(mktemp)
    local header=$(head -n 1 "$data_file")
    local deleted=0

    echo "$header" > "$temp_file"

    while IFS= read -r line; do
        if [[ "$line" == "$header" ]]; then
            continue
        fi
        
        if echo "$line" | grep -q -E "(^$pk_value,|,$pk_value,|,$pk_value$)"; then
            deleted=1
            continue
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$data_file"

    if [ $deleted -eq 1 ]; then
        mv "$temp_file" "$data_file"
        show_success "Record deleted successfully from table '$table_name'."
        echo -e "\n${COLOR_CYAN}Updated records:${COLOR_RESET}"
        column -t -s ',' < "$data_file"
    else
        rm "$temp_file"
        show_error "No record found with $pk_column = $pk_value"
    fi
    
    return 0
}
