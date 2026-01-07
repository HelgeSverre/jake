#!/bin/bash
# Run all output format demos

cd "$(dirname "$0")"

demos=(
    "output_format_current.sh"
    "output_format_v1_separator.sh"
    "output_format_v2_blank_lines.sh"
    "output_format_v3_indented_output.sh"
    "output_format_v4_header_only.sh"
    "output_format_v5_nx_style.sh"
    "output_format_v6_minimal.sh"
    "output_format_v7_box.sh"
)

for demo in "${demos[@]}"; do
    echo ""
    bash "$demo"
    echo ""
    echo "Press Enter for next..."
    read
done

echo "=== SUMMARY ==="
echo ""
echo "Current: Misaligned - output at col 0, jake at col 3"
echo ""
echo "V1 Separator: Clear visual break with dashes"
echo "V2 Blank:     Simple blank lines"
echo "V3 Indented:  All output indented (requires capture)"
echo "V4 Header:    Recipe name before output"
echo "V5 Nx-style:  Task prefix block (requires capture)"
echo "V6 Minimal:   Just output, status at end"
echo "V7 Box:       Box border around output"
