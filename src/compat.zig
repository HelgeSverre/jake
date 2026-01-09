// Zig version compatibility layer (0.14 vs 0.15+)
// Provides consistent API across different Zig standard library versions

const std = @import("std");

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

const builtin = @import("builtin");
const native_os = builtin.os.tag;

/// Get environment variable (cross-platform: works on Windows and POSIX)
/// Returns null if the variable is not set
/// Note: On Windows, returns null (env var features disabled for now)
pub const getenv = if (native_os == .windows)
    struct {
        pub fn f(_: []const u8) ?[]const u8 {
            return null;
        }
    }.f
else
    std.posix.getenv;
