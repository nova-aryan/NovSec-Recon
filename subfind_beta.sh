#!/bin/bash

# Colors
green="\033[1;32m"
blue="\033[1;34m"
red="\033[1;31m"
end="\033[0m"

# Show Banner
if command -v figlet &>/dev/null && command -v lolcat &>/dev/null; then
    figlet "NovSec Recon" | lolcat
else
    echo -e "${green}[+] NovSec Recon Started${end}"
fi

# Check for required tools
for tool in subfinder assetfinder github-subdomains curl jq anew httpx dnsx waybackurls gau katana; do
    if ! command -v $tool &>/dev/null; then
        echo -e "${red}[-] $tool not installed. Please install it before running this script.${end}"
        exit 1
    fi
done

# Input domain
read -p "Enter the target domain: " domain
mkdir -p "$domain" "$domain/urls" "$domain/status-codes"

# Logging start
echo "[+] Recon started at $(date)" > "$domain/log.txt"

### Subdomain Enumeration

echo -e "${green}\n[+] Running subfinder...${end}"
subfinder -d "$domain" -silent | anew "$domain/subdomain.txt"

echo -e "${green}[+] Running assetfinder...${end}"
assetfinder --subs-only "$domain" | anew "$domain/subdomain.txt"

echo -e "${green}[+] Getting from crt.sh...${end}"
curl -s "https://crt.sh/?q=%25.%25.${domain}&output=json" -H "User-Agent: Mozilla/5.0" |
jq -r '.[].name_value' | grep -E "^[^*]*\.${domain//./\\.}" | anew "$domain/subdomain.txt"

echo -e "${green}[+] Running github-subdomains...${end}"
github-subdomains -d "$domain" -o "$domain/githubsub.txt"
cat "$domain/githubsub.txt" | anew "$domain/subdomain.txt"

### Clean + Resolve Subdomains

echo -e "${green}[+] Cleaning and resolving subdomains with dnsx...${end}"
sort -u "$domain/subdomain.txt" | sed '/\*/d' | dnsx -silent -retries 2 | tee "$domain/resolved.txt"

### HTTP Probing

echo -e "${green}[+] Probing alive subdomains with httpx...${end}"
httpx -l "$domain/resolved.txt" -silent -status-code -title -tech-detect -threads 50 | tee "$domain/final.txt"

### Categorize by Status Codes

echo -e "${green}[+] Categorizing by status codes...${end}"
httpx -l "$domain/resolved.txt" -mc 200 -silent > "$domain/status-codes/200.txt"
httpx -l "$domain/resolved.txt" -mc 403 -silent > "$domain/status-codes/403.txt"
httpx -l "$domain/resolved.txt" -mc 404 -silent > "$domain/status-codes/404.txt"

### Second-Level Enumeration

echo -e "${green}[+] Extracting second-level domains and rerunning subfinder...${end}"
sed 's|http[s]*://||g' "$domain/final.txt" | cut -d "/" -f1 | anew "$domain/subdomaintwo.txt"
subfinder -dL "$domain/subdomaintwo.txt" -silent | anew "$domain/subdomain.txt"
dnsx -l "$domain/subdomain.txt" -silent | anew "$domain/resolved.txt"
httpx -l "$domain/resolved.txt" -silent | anew "$domain/final.txt"

### Historical URL Collection

echo -e "${blue}[+] Gathering historical URLs (waybackurls, gau, katana)...${end}"
cat "$domain/resolved.txt" | waybackurls | anew "$domain/urls/waybackurls.txt"
cat "$domain/resolved.txt" | gau | anew "$domain/urls/gau.txt"
katana -list "$domain/final.txt" -d 3 -silent -o "$domain/urls/katana.txt"

# Combine all
cat "$domain/urls/"*.txt | sort -u | tee "$domain/urls/all_historical_urls.txt"

# JS + Params Extract (optional)
grep '\.js$' "$domain/urls/all_historical_urls.txt" > "$domain/urls/jsfiles.txt"
grep -E '\?|=' "$domain/urls/all_historical_urls.txt" > "$domain/urls/params.txt"

### Logging complete
echo "[+] Recon completed at $(date)" >> "$domain/log.txt"

echo -e "${green}[✔] Recon completed! All data saved in ./$domain directory.${end}"
