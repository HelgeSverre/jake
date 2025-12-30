task process:
    @each alpha beta gamma
        @if exists(/bin)
            echo "Processing: {{item}} (system ok)"
        @else
            echo "{{item}} (no system)"
        @end
    @end
    echo "Done"
