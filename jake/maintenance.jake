# Maintenance tasks

@group maintenance
@desc "Rebuild and reinstall jake"
task self-update: [build-release]
    @pre echo "Reinstalling jake..."
    # Use atomic replacement to avoid macOS code signature invalidation
    cp zig-out/bin/jake {{local_bin("jake")}}.new
    mv {{local_bin("jake")}}.new {{local_bin("jake")}}
    @post echo "Updated {{local_bin(\"jake\")}}"

@group maintenance
@desc "Remove jake from local bin"
task uninstall:
    rm -f {{local_bin("jake")}}
    echo "Removed {{local_bin(\"jake\")}}"

@group maintenance
@desc "Clear jake cache files"
task cache-clean:
    @ignore
    rm -rf .jake
    echo "Jake cache cleared"

@group maintenance
@desc "Remove all build artifacts and caches"
task prune:
    @ignore
    @pre echo "Pruning build artifacts..."
    rm -rf zig-out .zig-cache .jake dist
    @post echo "All artifacts removed"
