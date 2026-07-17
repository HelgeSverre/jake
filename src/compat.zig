// Small std shims shared across the codebase.
// The 0.14-era fallback branches are gone — jake requires Zig 0.15.2+.

const std = @import("std");
var env_init_once = std.once(initEnvMap);
var cached_env_map: ?std.process.EnvMap = null;

fn initEnvMap() void {
    cached_env_map = std.process.getEnvMap(std.heap.page_allocator) catch std.process.EnvMap.init(std.heap.page_allocator);
}

/// Get standard output file handle
pub fn getStdOut() std.fs.File {
    return std.fs.File.stdout();
}

/// Get standard error file handle
pub fn getStdErr() std.fs.File {
    return std.fs.File.stderr();
}

/// Get standard input file handle
pub fn getStdIn() std.fs.File {
    return std.fs.File.stdin();
}

/// Get environment variable (cross-platform: works on Windows and POSIX)
/// Returns null if the variable is not set
pub fn getenv(key: []const u8) ?[]const u8 {
    env_init_once.call();
    return if (cached_env_map) |env_map| env_map.get(key) else null;
}
