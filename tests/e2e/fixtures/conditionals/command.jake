# command() condition tests

# Test existing command in PATH
task check-existing:
    @if command(sh)
        echo "sh exists in PATH"
    @else
        echo "sh not found"
    @end

# Test nonexistent command
task check-missing:
    @if command(jake_nonexistent_cmd_xyz123)
        echo "command found (unexpected)"
    @else
        echo "command not found (expected)"
    @end

# Test absolute path
task check-absolute:
    @if command(/bin/sh)
        echo "absolute path exists"
    @else
        echo "absolute path not found"
    @end

# Test with common dev tools
task check-tools:
    @if command(ls)
        echo "ls: found"
    @end
    @if command(cat)
        echo "cat: found"
    @end
    @if command(this_tool_does_not_exist_12345)
        echo "fake: found"
    @else
        echo "fake: not found"
    @end
