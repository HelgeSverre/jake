task glob-test:
    @each src/*.txt
        echo "Found: {{item}}"
    @end
    echo "Glob complete"
