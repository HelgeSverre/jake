task check-tools:
    @needs echo cat ls
    echo "All tools present"

task check-missing:
    @needs nonexistent_tool_12345
    echo "This should not print"
