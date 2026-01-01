# Debugging & Inspection tasks

version = "0.3.0"

@group debug
@desc "Run jake with verbose tracing"
task trace:
    @needs zig
    zig build -Doptimize=ReleaseFast
    ./zig-out/bin/jake -v {{$1}}

@group debug
@desc "Show environment and system info"
task env-info:
    echo "Jake version: {{version}}"
    echo "Platform: $(uname -s) $(uname -m)"
    echo "Home: {{home()}}"
    echo "Shell: $SHELL"
    echo "PATH contains jake: "
    which jake || echo "jake not in PATH"
