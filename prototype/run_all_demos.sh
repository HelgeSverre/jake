#!/bin/bash
# Run all spinner demos to compare options

cd "$(dirname "$0")"

echo "========================================"
echo "   SPINNER OUTPUT HANDLING DEMOS"
echo "========================================"
echo ""
echo "This will run 5 demos showing different approaches"
echo "to handling spinner + command output interaction."
echo ""
echo "Press Enter to start each demo..."
echo ""

run_demo() {
    local script="$1"
    local name="$2"

    echo "----------------------------------------"
    echo ">>> $name"
    echo "----------------------------------------"
    read -p "Press Enter to run..."
    echo ""
    bash "$script"
    echo ""
    echo ""
}

run_demo "demo_problem.sh" "CURRENT PROBLEM (interleaved output)"
run_demo "option1_pause_resume.sh" "OPTION 1: Pause/Resume"
run_demo "option2_detect_react.sh" "OPTION 2: Detect & React"
run_demo "option3_buffer_after.sh" "OPTION 3: Buffer After"
run_demo "option4_static_indicator.sh" "OPTION 4: Static Indicator"

echo "========================================"
echo "   DEMO COMPLETE"
echo "========================================"
echo ""
echo "Summary:"
echo "  Problem: Spinner and command output race, causing corruption"
echo ""
echo "  Option 1: Simple pause/resume - spinner stops during commands"
echo "  Option 2: Pipe + poll - spinner visible between output chunks"
echo "  Option 3: Buffer all - output shown after command completes"
echo "  Option 4: Static - no animation, just arrow indicator"
echo ""
echo "Recommendation: Start with Option 1 (simplest fix)"
