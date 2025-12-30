task a: [b]
    echo "A"

task b: [c]
    echo "B"

task c: [a]
    echo "C"
