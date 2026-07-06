#!/bin/bash

# Database file
DB_FILE="video_pages.db"
CSV_FILE="valid_pages.csv"

# Base URL
BASE_URL="https://dub.onestream.today/stream/video/"

# Total pages to check (1 Lakh)
TOTAL_PAGES=100000

# Counter for valid pages
VALID_COUNT=0

# Create SQLite database and table if not exists
create_database() {
    sqlite3 $DB_FILE <<EOF
CREATE TABLE IF NOT EXISTS video_pages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    page_id INTEGER UNIQUE,
    title TEXT,
    working_url TEXT,
    is_valid INTEGER,
    scraped_date TEXT
);
EOF
    echo "Database initialized: $DB_FILE"
}

# Check if URL is valid (returns 200 OK)
check_url_valid() {
    local url=$1
    local response=$(curl -s -o /dev/null -w "%{http_code}" -L "$url" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9" \
        -H "Accept-Language: en-US,en;q=0.5" \
        --max-time 10)
    
    if [ "$response" = "200" ]; then
        return 0  # Valid
    else
        return 1  # Invalid
    fi
}

# Extract title from HTML
extract_title() {
    local url=$1
    local title=$(curl -s -L "$url" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9" \
        -H "Accept-Language: en-US,en;q=0.5" \
        --max-time 15 | \
        grep -E '<h1>|<h2>|<title>' | \
        head -1 | \
        sed -E 's/<[^>]*>//g' | \
        sed 's/^[ \t]*//;s/[ \t]*$//' | \
        head -1)
    
    # If title is empty, try to get from wrapper
    if [ -z "$title" ]; then
        title=$(curl -s -L "$url" \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
            --max-time 15 | \
            grep -A 1 'wrapper' | \
            grep -E '<h1>|<h2>' | \
            sed -E 's/<[^>]*>//g' | \
            sed 's/^[ \t]*//;s/[ \t]*$//' | \
            head -1)
    fi
    
    # If still empty, use "Title not found"
    if [ -z "$title" ]; then
        echo "Title not found"
    else
        echo "$title"
    fi
}

# Insert into database if valid
insert_to_database() {
    local page_id=$1
    local title=$2
    local working_url=$3
    local current_date=$(date '+%Y-%m-%d %H:%M:%S')
    
    sqlite3 $DB_FILE <<EOF
INSERT OR REPLACE INTO video_pages (page_id, title, working_url, is_valid, scraped_date)
VALUES ($page_id, "$title", "$working_url", 1, "$current_date");
EOF
}

# Append to CSV
append_to_csv() {
    local page_id=$1
    local title=$2
    local working_url=$3
    
    # Create CSV header if file doesn't exist
    if [ ! -f "$CSV_FILE" ]; then
        echo "Page ID,Title,Working URL,Scraped Date" > "$CSV_FILE"
    fi
    
    echo "$page_id,\"$title\",$working_url,$(date '+%Y-%m-%d %H:%M:%S')" >> "$CSV_FILE"
}

# Main scraping function
scrape_pages() {
    local start_page=${1:-1}
    local end_page=$TOTAL_PAGES
    
    echo "Starting scraping from page $start_page to $end_page"
    echo "==========================================="
    echo ""
    
    # Create progress bar function
    progress_bar() {
        local current=$1
        local total=$2
        local width=50
        local percent=$((current * 100 / total))
        local filled=$((percent * width / 100))
        local empty=$((width - filled))
        
        printf "\rProgress: ["
        printf "%${filled}s" | tr ' ' '#'
        printf "%${empty}s" | tr ' ' ' '
        printf "] %3d%% (%d/%d)" $percent $current $total
    }
    
    # Loop through pages
    for ((i=start_page; i<=end_page; i++)); do
        page_id=$i
        url="${BASE_URL}${page_id}"
        
        # Update progress
        progress_bar $i $end_page
        
        # Check if URL is valid
        if check_url_valid "$url"; then
            # Get title
            title=$(extract_title "$url")
            
            # Insert into database
            insert_to_database "$page_id" "$title" "$url"
            
            # Append to CSV
            append_to_csv "$page_id" "$title" "$url"
            
            # Increment valid count
            ((VALID_COUNT++))
            
            # Print success (once per 100 pages)
            if [ $((i % 100)) -eq 0 ]; then
                echo ""
                echo "[✓] Page $page_id - Valid - Title: $title"
            fi
        else
            # Skip invalid pages (don't add to database)
            if [ $((i % 1000)) -eq 0 ]; then
                echo ""
                echo "[✗] Page $page_id - Invalid (skipped)"
            fi
        fi
        
        # Small delay to avoid rate limiting
        sleep 0.5
    done
    
    echo ""
    echo "==========================================="
    echo "Scraping completed!"
    echo "Total pages checked: $TOTAL_PAGES"
    echo "Valid pages found: $VALID_COUNT"
    echo "Invalid pages: $((TOTAL_PAGES - VALID_COUNT))"
    echo "Database saved to: $DB_FILE"
    echo "CSV exported to: $CSV_FILE"
}

# Show statistics
show_stats() {
    echo ""
    echo "=== Database Statistics ==="
    sqlite3 $DB_FILE <<EOF
SELECT 'Total valid pages: ' || COUNT(*) FROM video_pages;
SELECT 'Latest pages:' || CHAR(10) || '-----------';
SELECT page_id, title, scraped_date FROM video_pages ORDER BY page_id DESC LIMIT 10;
EOF
}

# Main execution
main() {
    # Create database
    create_database
    
    # Check if we should continue from last page
    if [ -f "$DB_FILE" ]; then
        last_page=$(sqlite3 $DB_FILE "SELECT MAX(page_id) FROM video_pages;" 2>/dev/null)
        if [ -n "$last_page" ] && [ "$last_page" != "NULL" ]; then
            start_page=$((last_page + 1))
            echo "Resuming from page $start_page"
        else
            start_page=1
        fi
    else
        start_page=1
    fi
    
    # Start scraping
    scrape_pages $start_page
    
    # Show statistics
    show_stats
}

# Run main function
main
