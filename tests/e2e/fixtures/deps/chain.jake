task compile:
    echo "Compiling..."

task link: [compile]
    echo "Linking..."

task test: [link]
    echo "Testing..."

task build: [test]
    echo "Build complete"
