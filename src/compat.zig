// Zig version compatibility layer (0.14 vs 0.15+)
// Provides consistent API across different Zig standard library versions

const std = @import("std");
var env_init_once = std.once(initEnvMap);
var cached_env_map: ?std.process.EnvMap = null;

fn initEnvMap() void {
    cached_env_map = std.process.getEnvMap(std.heap.page_allocator) catch std.process.EnvMap.init(std.heap.page_allocator);
}

/// Get standard output file handle (compatible with both Zig 0.14 and 0.15+)
pub fn getStdOut() std.fs.File {
    if (@hasDecl(std.fs.File, "stdout")) {
        return std.fs.File.stdout();
    } else {
        return std.io.getStdOut();
    }
}

/// Get standard error file handle (compatible with both Zig 0.14 and 0.15+)
pub fn getStdErr() std.fs.File {
    if (@hasDecl(std.fs.File, "stderr")) {
        return std.fs.File.stderr();
    } else {
        return std.io.getStdErr();
    }
}

/// Get standard input file handle (compatible with both Zig 0.14 and 0.15+)
pub fn getStdIn() std.fs.File {
    if (@hasDecl(std.fs.File, "stdin")) {
        return std.fs.File.stdin();
    } else {
        return std.io.getStdIn();
    }
}

/// Get environment variable (cross-platform: works on Windows and POSIX)
/// Returns null if the variable is not set
pub fn getenv(key: []const u8) ?[]const u8 {
    env_init_once.call();
    return if (cached_env_map) |env_map| env_map.get(key) else null;
}
