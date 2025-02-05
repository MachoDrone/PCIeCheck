#!/bin/bash
reset

clear

echo -e "\033[1;4;31mMemory Type and Type Detail'Unknown' is likely an empty RAM slot\033[0m"
sudo dmidecode --type memory | grep -i "type\|speed"

sudo lspci -vvv 2>/dev/null | grep -A 30 NVMe | grep -i "LnkCap" | awk '
BEGIN {
    # Base speed for PCIe 1.0
    base_speed = 2.5;
}
{
    if ($1 == "LnkCap:") {
        for (i = 1; i <= NF; i++) {
            if ($i == "Speed") {
                speed = $(i + 1);
                gsub(/[,GT\/s]/, "", speed);
                speed = speed + 0; # Convert to number
                version = 1;
                while (speed > base_speed * (2 ^ (version - 1))) version++;
                print "\033[1;34mCurrent DDR Link Speed: " speed " GT/s (PCIe " version ".0)\033[0m";
                break;
            }
        }
    }
}'
sudo lspci -vvv 2>/dev/null | grep -A 30 NVMe | grep -i "LnkCap"

sudo bash << EOF
# Check RAM (DDR4) support for PCIe 4.0 but do not print individual slots
sudo dmidecode --type memory | awk '
BEGIN {
    ddr4_detected = 0;
}
{
    if (/Type: DDR4/) {
        ddr4_detected = 1;
    }
}
END {
    if (ddr4_detected) {
        print "\033[0;1;34mMemory Type: DDR4 - Compatible with PCIe 4.0 detected\033[0m";
    } else {
        print "\033[34mNo DDR4 memory detected\033[0m";
    }
}'

# Check NVMe SSD for PCIe 1.0 to 5.0 support
pci_info=\$(sudo lspci -vvv 2>/dev/null | grep -A 30 NVMe | grep -i "LnkCap")
while IFS= read -r line; do
    if [[ \$line =~ Speed[[:space:]]*([0-9]+)[[:space:]]*GT/s ]]; then
        speed=\${BASH_REMATCH[1]}
        case \$speed in
            2) echo -e "\033[1;34mNVMe SSD PCIe Compatibility: Supports PCIe 1.0";;
            5) echo -e "\033[1;34mNVMe SSD PCIe Compatibility: Supports PCIe 2.0";;
            8) echo -e "\033[1;34mNVMe SSD PCIe Compatibility: Supports PCIe 3.0";;
            16) echo -e "\033[1;34mNVMe SSD PCIe Compatibility: Supports PCIe 4.0";;
            32) echo -e "\033[1;34mNVMe SSD PCIe Compatibility: Supports PCIe 5.0";;
            *) echo -e "\033[1;34mNVMe SSD PCIe Compatibility: Unknown or unsupported speed";;
        esac
        break
    fi
done <<< "\$pci_info"
if [[ -z \$(echo \$pci_info | grep -E "Speed 2GT/s|Speed 5GT/s|Speed 8GT/s|Speed 16GT/s|Speed 32GT/s") ]]; then
    echo "NVMe SSD PCIe Compatibility: No PCIe 1.0-5.0 NVMe SSD detected or check manually."
fi

for i in {0..7}; do
    # Check if the GPU exists
    if nvidia-smi -i \$i &> /dev/null; then
        # Enable persistence mode
        nvidia-smi -i \$i -pm 1 &> /dev/null

        # Set GPU and memory clocks
        nvidia-smi -i \$i -lgc 500,500 &> /dev/null
        nvidia-smi -i \$i -lmc 5000 &> /dev/null

        # Query performance state
        nvidia-smi -i \$i -q -d PERFORMANCE &> /dev/null
        sleep 2

        # Extract CUDA version directly from nvidia-smi output
        cuda_version=\$(nvidia-smi -i \$i | grep "CUDA Version" | awk '{print \$9}')

        # Extract PCIe speed and width
        pcie_speed=\$(lspci -vv -s \$(nvidia-smi -i \$i --query-gpu=pci.bus_id --format=csv,noheader) | grep -i "LnkSta:" | awk -F'Speed |GT/s' '{print \$2}' | awk '{if(\$1==2.5)print "1.0";else if(\$1==5.0)print "2.0";else if(\$1==8.0)print "3.0";else if(\$1==16.0)print "4.0";else if(\$1==32.0)print "5.0";else print "Unknown"}')
        pcie_width=\$(lspci -vv -s \$(nvidia-smi -i \$i --query-gpu=pci.bus_id --format=csv,noheader) | grep -i "LnkSta:" | sed -n 's/.*Width x\([0-9]\+\).*/\1/p')

        # Format pcie_width for display
        formatted_width="x\$pcie_width"
        if [ \${#pcie_width} -eq 1 ]; then
            formatted_width="x \$pcie_width"
        fi

        # Extract VRAM size
        vram_mib=\$(nvidia-smi -i \$i --query-gpu=memory.total --format=csv,noheader | awk '{print \$1}')
        vram_gb=\$(echo "\$vram_mib / 1024" | bc -l | awk '{print int(\$1 + 0.5)}')  # Round to nearest whole number

        # Extract GPU name
        gpu_name=\$(lspci -s \$(nvidia-smi -i \$i --query-gpu=pci.bus_id --format=csv,noheader) | cut -d ":" -f 3-)

        # Extract driver version and temperature
        driver_version=\$(nvidia-smi -i \$i --query-gpu=driver_version --format=csv,noheader)
        temperature=\$(nvidia-smi -i \$i --query-gpu=temperature.gpu --format=csv,noheader)

        # Output GPU details with new format
        echo -e "\033[1;34mGPU PCIe \$pcie_speed \$formatted_width slot \$vram_gb GB  \$driver_version  \$cuda_version  \$temperature°C  \$gpu_name"

        # Reset GPU clocks and disable persistence mode
        nvidia-smi -i \$i -rgc &> /dev/null
        nvidia-smi -i \$i -rmc &> /dev/null
        nvidia-smi -i \$i -pm 0 &> /dev/null
    fi
done

# Check for PCIe 1.0 to 5.0 slot for GPU
pci_info=\$(sudo lspci -vvv 2>/dev/null | grep -A 30 "Root Port" | grep -i "LnkCap")
while IFS= read -r line; do
    if [[ \$line =~ Speed[[:space:]]*([0-9]+)[[:space:]]*GT/s ]]; then
        speed=\${BASH_REMATCH[1]}
        case \$speed in
            2) echo "GPU Slot PCIe Compatibility: PCIe 1.0 x16 slot exists";;
            5) echo "GPU Slot PCIe Compatibility: PCIe 2.0 x16 slot exists";;
            8) echo "GPU Slot PCIe Compatibility: PCIe 3.0 x16 slot exists";;
            16) echo "GPU Slot PCIe Compatibility: PCIe 4.0 x16 slot exists";;
            32) echo "GPU Slot PCIe Compatibility: PCIe 5.0 x16 slot exists";;
            *) echo "GPU Slot PCIe Compatibility: Unknown or unsupported speed";;
        esac
        break
    fi
done <<< "\$pci_info"
if [[ -z \$(echo \$pci_info | grep -E "Speed 2GT/s|Speed 5GT/s|Speed 8GT/s|Speed 16GT/s|Speed 32GT/s") ]]; then
    echo "GPU Slot PCIe Compatibility: No PCIe 1.0-5.0 slot detected or check manually."
fi
EOF

determine_pcie_support() {
    # Extract CPU model, focusing only on the first line and relevant parts, removing newlines and spaces
    cpu_model=$(lscpu | grep -i "Model name" | cut -d ':' -f2 | sed 's/^[ \t]*//;s/[ \t]*\$//' | awk '{print $0}' | head -n 1 | tr -d '\n')

    # Check for PCIe compatibility based on CPU model
    if [[ $cpu_model =~ "Ryzen 9 5900X" ]]; then
        echo -e "\033[34mCPU Compatibility: AMD Ryzen 9 5900X supports PCIe 4.0"
        cpu_pcie_version="4.0"
    elif [[ $cpu_model =~ "13th Gen Intel(R) Core(TM)" ]]; then
        echo -e "\033[34mCPU Compatibility: Intel 13th Gen Core processors support PCIe 5.0"
        cpu_pcie_version="5.0"
    else
        echo -e "\033[34mCPU Compatibility: CPU model not recognized for PCIe support."
        cpu_pcie_version="Unknown"
    fi

    # Check if lspci is installed
    if ! command -v lspci &> /dev/null; then
        echo -e "\nError: 'lspci' command not found. Please install 'pciutils' package."
        echo "Installation command: sudo apt install pciutils  # For Debian/Ubuntu"
        echo "                      sudo yum install pciutils  # For CentOS/RHEL"
        return
    fi

    # Query PCIe capabilities of the system
    echo -e "\033[0;2;34mTesting PCIe capabilities of the system..."
    pcie_info=$(sudo lspci -vvv 2>/dev/null | grep -i "LnkCap" | grep -i "Speed")

    if [[ -z "$pcie_info" ]]; then
        echo "No PCIe link capabilities found. Possible reasons:"
        echo "1. No PCIe devices are connected."
        echo "2. Insufficient permissions (try running the script with 'sudo')."
        echo "3. The system does not expose PCIe link capabilities via 'lspci'."
        echo "4. The kernel or hardware does not support querying PCIe capabilities."
    else
        declare -A pcie_versions
        while read -r line; do
            if [[ $line =~ Speed\ ([0-9.]+)GT/s ]]; then
                speed=${BASH_REMATCH[1]}
                if (( $(echo "$speed == 2.5" | bc -l) )); then
                    ((pcie_versions["1.0"]++))
                elif (( $(echo "$speed == 5.0" | bc -l) )); then
                    ((pcie_versions["2.0"]++))
                elif (( $(echo "$speed == 8.0" | bc -l) )); then
                    ((pcie_versions["3.0"]++))
                elif (( $(echo "$speed == 16.0" | bc -l) )); then
                    ((pcie_versions["4.0"]++))
                elif (( $(echo "$speed == 32.0" | bc -l) )); then
                    ((pcie_versions["5.0"]++))
                else
                    ((pcie_versions["Unknown"]++))
                fi
            fi
        done <<< "$pcie_info"

        echo -e "PCIe Version Summary:"
        for version in "${!pcie_versions[@]}"; do
            echo "  PCIe $version: ${pcie_versions[$version]} links detected"
        done

        # Determine the maximum detected PCIe version
        max_detected_version=$(printf "%s\n" "${!pcie_versions[@]}" | sort -V | tail -n1)
        echo -e "\033[0;1;32mMaximum Tested CPU: PCIe $max_detected_version"

        # Compare detected version with CPU's claimed support
        if [[ $cpu_pcie_version != "Unknown" ]]; then
            if (( $(echo "$max_detected_version < $cpu_pcie_version" | bc -l) )); then
                echo -e "\033[0;33mWarning: The detected PCIe version ($max_detected_version) is lower than the CPU's claimed support (PCIe $cpu_pcie_version)."
                echo -e "\033[4;33mPossible reasons:\033[0m \033[0;33mMotherboard or BIOS settings are limiting the PCIe version, No PCIe $cpu_pcie_version devices are connected, The system is not utilizing the full PCIe capabilities of the CPU. \nThis may be just fine, as you intended."
            else
                echo -e "\nThe detected PCIe version matches or exceeds the CPU's claimed support (PCIe $cpu_pcie_version)."
            fi
        fi
    fi
}

# Call the function to determine PCIe support
determine_pcie_support
