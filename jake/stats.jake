# Code Statistics tasks

@group stats
@desc "Count lines of code in Zig sources"
task loc:
    @pre echo "Lines of code:"
    find src -name "*.zig" | xargs wc -l | tail -1

@group stats
@desc "Find TODO:/FIXME:/HACK: comments in source"
task todos:
    @ignore
    grep -rn "TODO:\|FIXME:\|HACK:\|XXX:" src/ || echo "No TODOs found!"

@group stats
@desc "Show largest source files by line count"
task complexity:
    @pre echo "Largest source files:"
    wc -l src/*.zig | sort -n | tail -10
