task documented:
    echo "This is a very long command" \
         "that spans multiple lines"

task state:
    start=3000; p=$start; \
        p=$((p+1)); \
        echo "port=$p"
