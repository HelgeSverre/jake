task nested-if:
    @if exists(/bin)
        echo "A: /bin exists"
        @if env(HOME)
            echo "B: HOME is set"
        @else
            echo "C: No HOME"
        @end
        echo "D: after inner if"
    @else
        echo "E: No /bin"
    @end
    echo "F: after outer if"
