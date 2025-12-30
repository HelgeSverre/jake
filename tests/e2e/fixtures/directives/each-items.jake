task process-items:
    @each apple banana cherry
        echo "Processing: {{item}}"
    @end
    echo "Done processing items"
