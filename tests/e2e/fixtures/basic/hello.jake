task hello:
    echo "Hello, World!"

task greet name="World":
    echo "Hello, {{name}}!"

# Reserved keywords are valid parameter names (jake#23)
task trace file="traces.jsonl":
    echo "Tracing to {{file}}"
