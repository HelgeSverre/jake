task multi-loop:
    echo "First loop:"
    @each red green blue
        echo "  Color: {{item}}"
    @end
    echo "Second loop:"
    @each 1 2 3
        echo "  Number: {{item}}"
    @end
    echo "Complete"
