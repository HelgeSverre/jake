//! Cross-platform runtime helpers for environment, shell, and command lookup.

const std = @import("std");
const builtin = @import("builtin");
const compat = @import("compat.zig");

pub const ShellKind = enum {
    bash,
    zsh,
    fish,
    sh,
    ksh,
    csh,
    tcsh,
    powershell,
    pwsh,
    cmd,
};

const default_windows_pathext = ".COM;.EXE;.BAT;.CMD";

pub fn currentShellKind() ?ShellKind {
    if (compat.getenv("SHELL")) |shell_path| {
        return detectShellKind(shell_path);
    }
    if (builtin.os.tag == .windows) {
        if (compat.getenv("PSModulePath")) |_| {
            return .pwsh;
        }
        if (compat.getenv("COMSPEC")) |comspec| {
            return detectShellKind(comspec);
        }
    }
    return null;
}

pub fn detectShellKind(shell_path: []const u8) ?ShellKind {
    const basename = basenameAnySeparator(shell_path);
    const name = trimExecutableSuffix(basename);

    if (std.ascii.eqlIgnoreCase(name, "bash")) return .bash;
    if (std.ascii.eqlIgnoreCase(name, "zsh")) return .zsh;
    if (std.ascii.eqlIgnoreCase(name, "fish")) return .fish;
    if (std.ascii.eqlIgnoreCase(name, "sh")) return .sh;
    if (std.ascii.eqlIgnoreCase(name, "ksh")) return .ksh;
    if (std.ascii.eqlIgnoreCase(name, "csh")) return .csh;
    if (std.ascii.eqlIgnoreCase(name, "tcsh")) return .tcsh;
    if (std.ascii.eqlIgnoreCase(name, "powershell")) return .powershell;
    if (std.ascii.eqlIgnoreCase(name, "pwsh")) return .pwsh;
    if (std.ascii.eqlIgnoreCase(name, "cmd")) return .cmd;

    return null;
}

pub fn currentHomeDirOwned(allocator: std.mem.Allocator) !?[]const u8 {
    return homeDirOwnedFromEnv(allocator, builtin.os.tag, null);
}

pub const ShellInvocation = struct {
    shell: []const u8,
    flag: []const u8,
};

/// Returns the platform-default shell + invocation flag for running a single command string.
/// Use as `&[_][]const u8{ inv.shell, inv.flag, command }` when building child argv.
pub fn defaultShellInvocation() ShellInvocation {
    return shellInvocationForOs(builtin.os.tag);
}

pub fn shellInvocationForOs(os_tag: std.Target.Os.Tag) ShellInvocation {
    return if (os_tag == .windows)
        .{ .shell = "cmd.exe", .flag = "/C" }
    else
        .{ .shell = "/bin/sh", .flag = "-c" };
}

pub fn homeDirOwnedFromEnv(
    allocator: std.mem.Allocator,
    os_tag: std.Target.Os.Tag,
    env_map_opt: ?*const std.process.EnvMap,
) !?[]const u8 {
    if (getEnv(env_map_opt, "HOME")) |home| {
        if (home.len > 0) {
            return try allocator.dupe(u8, home);
        }
    }

    if (os_tag == .windows) {
        if (getEnv(env_map_opt, "USERPROFILE")) |profile| {
            if (profile.len > 0) {
                return try allocator.dupe(u8, profile);
            }
        }

        const home_drive = getEnv(env_map_opt, "HOMEDRIVE");
        const home_path = getEnv(env_map_opt, "HOMEPATH");
        if (home_drive != null and home_path != null and home_drive.?.len > 0 and home_path.?.len > 0) {
            return try std.fmt.allocPrint(allocator, "{s}{s}", .{ home_drive.?, home_path.? });
        }
    }

    return null;
}

pub fn currentShellConfigPathOwned(allocator: std.mem.Allocator) !?[]const u8 {
    const home = try currentHomeDirOwned(allocator) orelse return null;
    defer allocator.free(home);

    const shell = currentShellKind() orelse switch (builtin.os.tag) {
        .windows => return null,
        else => .sh,
    };
    return shellConfigPathOwned(allocator, shell, home);
}

pub fn shellConfigPathOwned(
    allocator: std.mem.Allocator,
    shell: ShellKind,
    home_dir: []const u8,
) !?[]const u8 {
    return switch (shell) {
        .bash => try joinHomeRelativeOwned(allocator, home_dir, ".bashrc"),
        .zsh => try joinHomeRelativeOwned(allocator, home_dir, ".zshrc"),
        .fish => try joinHomeRelativeOwned(allocator, home_dir, ".config/fish/config.fish"),
        .sh => try joinHomeRelativeOwned(allocator, home_dir, ".profile"),
        .ksh => try joinHomeRelativeOwned(allocator, home_dir, ".kshrc"),
        .csh => try joinHomeRelativeOwned(allocator, home_dir, ".cshrc"),
        .tcsh => try joinHomeRelativeOwned(allocator, home_dir, ".tcshrc"),
        .powershell => try joinHomeRelativeOwned(allocator, home_dir, "Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"),
        .pwsh => try joinHomeRelativeOwned(allocator, home_dir, "Documents/PowerShell/Microsoft.PowerShell_profile.ps1"),
        .cmd => null,
    };
}

pub fn joinHomeRelativeOwned(
    allocator: std.mem.Allocator,
    home_dir: []const u8,
    relative_path: []const u8,
) ![]const u8 {
    const separator = preferredSeparator(home_dir);
    const normalized_relative = try normalizeSeparatorsOwned(allocator, relative_path, separator);
    defer allocator.free(normalized_relative);

    const needs_separator = home_dir.len > 0 and home_dir[home_dir.len - 1] != '/' and home_dir[home_dir.len - 1] != '\\';
    if (!needs_separator) {
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ home_dir, normalized_relative });
    }
    return try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ home_dir, separator, normalized_relative });
}

pub fn commandExists(cmd: []const u8) bool {
    if (cmd.len == 0) return false;

    const pathext = if (builtin.os.tag == .windows)
        (std.process.getEnvVarOwned(std.heap.page_allocator, "PATHEXT") catch null)
    else
        null;
    defer if (pathext) |value| std.heap.page_allocator.free(value);

    if (isAbsolutePathForOs(builtin.os.tag, cmd)) {
        return explicitPathExists(builtin.os.tag, cmd, pathext);
    }

    if (std.mem.indexOfAny(u8, cmd, "/\\") != null) {
        return explicitPathExists(builtin.os.tag, cmd, pathext);
    }

    const path_env = std.process.getEnvVarOwned(std.heap.page_allocator, "PATH") catch return false;
    defer std.heap.page_allocator.free(path_env);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const candidates = commandCandidatesOwned(allocator, builtin.os.tag, cmd, pathext) catch return false;

    // ZDEBUG: probe two known-existing system paths once to verify the binding works
    if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "JAKE_ZDEBUG_FILE")) |dbg_path| {
            defer std.heap.page_allocator.free(dbg_path);
            if (std.fs.createFileAbsolute(dbg_path, .{ .truncate = false })) |dbg_file| {
                defer dbg_file.close();
                dbg_file.seekFromEnd(0) catch {};
                const probes = [_][]const u8{ "C:\\Windows", "C:\\Windows\\System32\\cmd.exe", "C:\\does\\not\\exist.xyz" };
                var pbuf: [4096]u8 = undefined;
                for (probes) |p| {
                    const r = windowsPathExists(p);
                    if (std.fmt.bufPrint(&pbuf, "PROBE '{s}' exists={}\n", .{ p, r })) |m| {
                        dbg_file.writeAll(m) catch {};
                    } else |_| {}
                }
                // Probe an explicit caller-supplied path in both case variants to test case-sensitivity behavior.
                if (std.process.getEnvVarOwned(std.heap.page_allocator, "JAKE_ZPROBE_PATH")) |zpath| {
                    defer std.heap.page_allocator.free(zpath);
                    const r1 = windowsPathExists(zpath);
                    if (std.fmt.bufPrint(&pbuf, "ZPROBE '{s}' exists={}\n", .{ zpath, r1 })) |m| {
                        dbg_file.writeAll(m) catch {};
                    } else |_| {}
                    // Build an uppercase-extension variant: replace last 4 chars with uppercase (assumes ".cmd").
                    if (zpath.len >= 4) {
                        var upper_buf: [4096]u8 = undefined;
                        if (zpath.len < upper_buf.len) {
                            @memcpy(upper_buf[0..zpath.len], zpath);
                            const tail = upper_buf[zpath.len - 4 .. zpath.len];
                            for (tail) |*c| c.* = std.ascii.toUpper(c.*);
                            const upper_path = upper_buf[0..zpath.len];
                            const r2 = windowsPathExists(upper_path);
                            if (std.fmt.bufPrint(&pbuf, "ZPROBE '{s}' exists={}\n", .{ upper_path, r2 })) |m| {
                                dbg_file.writeAll(m) catch {};
                            } else |_| {}
                        }
                    }
                } else |_| {}
            } else |_| {}
        } else |_| {}
    }

    var path_iter = std.mem.splitScalar(u8, path_env, pathListSeparator(builtin.os.tag));
    while (path_iter.next()) |dir| {
        if (dir.len == 0) continue;

        for (candidates) |candidate| {
            const full_path = joinDirAndBase(allocator, dir, candidate) catch continue;
            const exists = pathExistsForLookup(full_path);
            if (builtin.os.tag == .windows) {
                if (std.process.getEnvVarOwned(std.heap.page_allocator, "JAKE_ZDEBUG_FILE")) |dbg_path| {
                    defer std.heap.page_allocator.free(dbg_path);
                    if (std.fs.createFileAbsolute(dbg_path, .{ .truncate = false })) |dbg_file| {
                        defer dbg_file.close();
                        dbg_file.seekFromEnd(0) catch {};
                        var dbgbuf: [4096]u8 = undefined;
                        if (std.fmt.bufPrint(&dbgbuf, "try len={d} exists={} hex='", .{ full_path.len, exists })) |msg| {
                            dbg_file.writeAll(msg) catch {};
                        } else |_| {}
                        // Dump path bytes as hex pairs so we see hidden chars (BOM, nulls, trailing whitespace).
                        var hexbuf: [3]u8 = undefined;
                        for (full_path) |byte| {
                            if (std.fmt.bufPrint(&hexbuf, "{x:0>2}", .{byte})) |hx| {
                                dbg_file.writeAll(hx) catch {};
                            } else |_| {}
                        }
                        dbg_file.writeAll("' tail='") catch {};
                        // Also dump the last 8 bytes as ASCII (with ? for non-printable) so it's easy to spot.
                        const tail_start = if (full_path.len > 8) full_path.len - 8 else 0;
                        for (full_path[tail_start..]) |byte| {
                            const safe: u8 = if (byte >= 0x20 and byte < 0x7f) byte else '?';
                            dbg_file.writeAll(&[_]u8{safe}) catch {};
                        }
                        dbg_file.writeAll("'\n") catch {};
                    } else |_| {}
                } else |_| {}
            }
            if (exists) return true;
        }
    }

    return false;
}

/// Existence check used during PATH and command lookup. On Windows we go directly
/// through `GetFileAttributesW` because Zig's `std.fs.accessAbsolute` panics on
/// `OBJECT_NAME_INVALID`, which Windows returns for plenty of real PATH entries
/// (relative paths, mixed separators, malformed substrings). On POSIX we keep
/// using the standard access call.
fn pathExistsForLookup(path: []const u8) bool {
    if (builtin.os.tag == .windows) return windowsPathExists(path);
    if (std.fs.accessAbsolute(path, .{})) |_| return true else |_| return false;
}

extern "kernel32" fn GetFileAttributesW(lpFileName: [*:0]const u16) callconv(.winapi) u32;
const INVALID_FILE_ATTRIBUTES_W: u32 = 0xFFFFFFFF;

fn windowsPathExists(path: []const u8) bool {
    var buf: [std.os.windows.PATH_MAX_WIDE]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, path) catch return false;
    if (len >= buf.len) return false;
    buf[len] = 0;
    const wpath: [:0]const u16 = buf[0..len :0];
    return GetFileAttributesW(wpath.ptr) != INVALID_FILE_ATTRIBUTES_W;
}

pub fn commandCandidatesOwned(
    allocator: std.mem.Allocator,
    os_tag: std.Target.Os.Tag,
    cmd: []const u8,
    pathext_opt: ?[]const u8,
) ![]const []const u8 {
    var candidates: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (candidates.items) |candidate| allocator.free(candidate);
        candidates.deinit(allocator);
    }

    if (os_tag != .windows or hasWindowsExecutableExtension(cmd, pathext_opt)) {
        try candidates.append(allocator, try allocator.dupe(u8, cmd));
        return candidates.toOwnedSlice(allocator);
    }

    const pathext = pathext_opt orelse default_windows_pathext;
    var ext_iter = std.mem.splitScalar(u8, pathext, ';');
    while (ext_iter.next()) |ext_raw| {
        const ext = std.mem.trim(u8, ext_raw, " \t");
        if (ext.len == 0) continue;

        try candidates.append(allocator, try std.fmt.allocPrint(allocator, "{s}{s}", .{ cmd, ext }));
    }

    if (candidates.items.len == 0) {
        try candidates.append(allocator, try allocator.dupe(u8, cmd));
    }

    return candidates.toOwnedSlice(allocator);
}

pub fn pathListSeparator(os_tag: std.Target.Os.Tag) u8 {
    return if (os_tag == .windows) ';' else ':';
}

fn explicitPathExists(os_tag: std.Target.Os.Tag, raw_path: []const u8, pathext_opt: ?[]const u8) bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const candidates = commandCandidatesOwned(allocator, os_tag, raw_path, pathext_opt) catch return false;
    for (candidates) |candidate| {
        const normalized_candidate = normalizeSeparatorsOwned(allocator, candidate, std.fs.path.sep) catch continue;
        if (builtin.os.tag == .windows) {
            if (windowsPathExists(normalized_candidate)) return true;
        } else if (isAbsolutePathForOs(os_tag, candidate)) {
            if (std.fs.accessAbsolute(normalized_candidate, .{})) |_| return true else |_| {}
        } else {
            if (std.fs.cwd().access(normalized_candidate, .{})) |_| return true else |_| {}
        }
    }

    return false;
}

fn getEnv(env_map_opt: ?*const std.process.EnvMap, key: []const u8) ?[]const u8 {
    if (env_map_opt) |env_map| {
        return env_map.get(key);
    }
    return compat.getenv(key);
}

fn preferredSeparator(home_dir: []const u8) u8 {
    const has_backslash = std.mem.indexOfScalar(u8, home_dir, '\\') != null;
    const has_forwardslash = std.mem.indexOfScalar(u8, home_dir, '/') != null;
    return if (has_backslash and !has_forwardslash) '\\' else '/';
}

fn basenameAnySeparator(path: []const u8) []const u8 {
    const slash_index = std.mem.lastIndexOfAny(u8, path, "/\\") orelse return path;
    return path[slash_index + 1 ..];
}

fn normalizeSeparatorsOwned(
    allocator: std.mem.Allocator,
    path: []const u8,
    separator: u8,
) ![]const u8 {
    const normalized = try allocator.dupe(u8, path);
    for (normalized) |*c| {
        if (c.* == '/' or c.* == '\\') {
            c.* = separator;
        }
    }
    return normalized;
}

fn trimExecutableSuffix(name: []const u8) []const u8 {
    if (endsWithIgnoreCase(name, ".exe")) return name[0 .. name.len - 4];
    if (endsWithIgnoreCase(name, ".cmd")) return name[0 .. name.len - 4];
    if (endsWithIgnoreCase(name, ".bat")) return name[0 .. name.len - 4];
    if (endsWithIgnoreCase(name, ".com")) return name[0 .. name.len - 4];
    return name;
}

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool {
    if (suffix.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

fn hasWindowsExecutableExtension(cmd: []const u8, pathext_opt: ?[]const u8) bool {
    const ext = std.fs.path.extension(cmd);
    if (ext.len == 0) return false;

    const pathext = pathext_opt orelse default_windows_pathext;
    var ext_iter = std.mem.splitScalar(u8, pathext, ';');
    while (ext_iter.next()) |candidate_raw| {
        const candidate = std.mem.trim(u8, candidate_raw, " \t");
        if (candidate.len == 0) continue;
        if (std.ascii.eqlIgnoreCase(ext, candidate)) {
            return true;
        }
    }
    return false;
}

fn isAbsolutePathForOs(os_tag: std.Target.Os.Tag, path: []const u8) bool {
    if (path.len == 0) return false;

    if (os_tag == .windows) {
        if (path.len >= 3 and std.ascii.isAlphabetic(path[0]) and path[1] == ':' and (path[2] == '\\' or path[2] == '/')) {
            return true;
        }
        return std.mem.startsWith(u8, path, "\\\\") or std.mem.startsWith(u8, path, "//");
    }

    return path[0] == '/';
}

fn joinDirAndBase(allocator: std.mem.Allocator, dir: []const u8, base: []const u8) ![]const u8 {
    const needs_separator = dir.len > 0 and dir[dir.len - 1] != '/' and dir[dir.len - 1] != '\\';
    if (!needs_separator) {
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ dir, base });
    }
    return try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ dir, std.fs.path.sep, base });
}

test "detectShellKind handles unix and windows paths" {
    try std.testing.expectEqual(ShellKind.bash, detectShellKind("/bin/bash").?);
    try std.testing.expectEqual(ShellKind.zsh, detectShellKind("/opt/homebrew/bin/zsh").?);
    try std.testing.expectEqual(ShellKind.bash, detectShellKind("C:\\Program Files\\Git\\bin\\bash.exe").?);
    try std.testing.expectEqual(ShellKind.pwsh, detectShellKind("C:\\Program Files\\PowerShell\\7\\pwsh.exe").?);
    try std.testing.expectEqual(ShellKind.cmd, detectShellKind("C:\\Windows\\System32\\cmd.exe").?);
}

test "homeDirOwnedFromEnv prefers HOME and supports Windows fallbacks" {
    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();

    try env_map.put("HOME", "/home/tester");
    const home_from_home = try homeDirOwnedFromEnv(std.testing.allocator, .windows, &env_map);
    defer std.testing.allocator.free(home_from_home.?);
    try std.testing.expectEqualStrings("/home/tester", home_from_home.?);

    env_map.remove("HOME");
    try env_map.put("USERPROFILE", "C:\\Users\\tester");
    const home_from_profile = try homeDirOwnedFromEnv(std.testing.allocator, .windows, &env_map);
    defer std.testing.allocator.free(home_from_profile.?);
    try std.testing.expectEqualStrings("C:\\Users\\tester", home_from_profile.?);

    env_map.remove("USERPROFILE");
    try env_map.put("HOMEDRIVE", "C:");
    try env_map.put("HOMEPATH", "\\Users\\fallback");
    const home_from_drive = try homeDirOwnedFromEnv(std.testing.allocator, .windows, &env_map);
    defer std.testing.allocator.free(home_from_drive.?);
    try std.testing.expectEqualStrings("C:\\Users\\fallback", home_from_drive.?);
}

test "shellConfigPathOwned handles Windows PowerShell profiles" {
    const powershell_path = (try shellConfigPathOwned(std.testing.allocator, .powershell, "C:\\Users\\tester")).?;
    defer std.testing.allocator.free(powershell_path);
    try std.testing.expectEqualStrings("C:\\Users\\tester\\Documents\\WindowsPowerShell\\Microsoft.PowerShell_profile.ps1", powershell_path);

    const pwsh_path = (try shellConfigPathOwned(std.testing.allocator, .pwsh, "C:\\Users\\tester")).?;
    defer std.testing.allocator.free(pwsh_path);
    try std.testing.expectEqualStrings("C:\\Users\\tester\\Documents\\PowerShell\\Microsoft.PowerShell_profile.ps1", pwsh_path);

    try std.testing.expectEqual(@as(?[]const u8, null), try shellConfigPathOwned(std.testing.allocator, .cmd, "C:\\Users\\tester"));
}

test "commandCandidatesOwned expands PATHEXT on Windows" {
    const candidates = try commandCandidatesOwned(std.testing.allocator, .windows, "tool", ".EXE;.CMD");
    defer {
        for (candidates) |candidate| std.testing.allocator.free(candidate);
        std.testing.allocator.free(candidates);
    }

    try std.testing.expectEqual(@as(usize, 2), candidates.len);
    try std.testing.expectEqualStrings("tool.EXE", candidates[0]);
    try std.testing.expectEqualStrings("tool.CMD", candidates[1]);
}

test "shellInvocationForOs picks platform-appropriate shell" {
    const win = shellInvocationForOs(.windows);
    try std.testing.expectEqualStrings("cmd.exe", win.shell);
    try std.testing.expectEqualStrings("/C", win.flag);

    const nix = shellInvocationForOs(.linux);
    try std.testing.expectEqualStrings("/bin/sh", nix.shell);
    try std.testing.expectEqualStrings("-c", nix.flag);

    const mac = shellInvocationForOs(.macos);
    try std.testing.expectEqualStrings("/bin/sh", mac.shell);
    try std.testing.expectEqualStrings("-c", mac.flag);
}

test "commandCandidatesOwned preserves explicit executable extension on Windows" {
    const candidates = try commandCandidatesOwned(std.testing.allocator, .windows, "tool.cmd", ".EXE;.CMD");
    defer {
        for (candidates) |candidate| std.testing.allocator.free(candidate);
        std.testing.allocator.free(candidates);
    }

    try std.testing.expectEqual(@as(usize, 1), candidates.len);
    try std.testing.expectEqualStrings("tool.cmd", candidates[0]);
}

test "commandExists honors PATHEXT for relative explicit paths on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "tool.cmd", .data = "@echo off\r\n" });

    var prev_cwd = try std.fs.cwd().openDir(".", .{});
    defer prev_cwd.close();
    try tmp.dir.setAsCwd();
    defer prev_cwd.setAsCwd() catch {};

    try std.testing.expect(explicitPathExists(.windows, "tool", ".CMD"));
    try std.testing.expect(explicitPathExists(.windows, ".\\tool", ".CMD"));
}
