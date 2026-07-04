//! Shared Jakefile loading pipeline used by CLI entrypoints and watch mode.

const std = @import("std");
const lexer_mod = @import("lexer.zig");
const parser_mod = @import("parser.zig");
const import_mod = @import("import.zig");
const external_mod = @import("external.zig");
const jakefile_index_mod = @import("jakefile_index.zig");
const context_mod = @import("context.zig");
const compat = @import("compat.zig");
const args_mod = @import("args.zig");

const Lexer = lexer_mod.Lexer;
const Parser = parser_mod.Parser;
const Jakefile = parser_mod.Jakefile;
const JakefileIndex = jakefile_index_mod.JakefileIndex;
const RuntimeContext = context_mod.RuntimeContext;

pub const LoadedJakefile = struct {
    jakefile: Jakefile,
    index: JakefileIndex,
    runtime: RuntimeContext,
    source: []const u8,
    watch_files: []const []const u8,
    allocator: std.mem.Allocator,
    import_allocations: ?import_mod.ImportAllocations,
    external_allocations: ?external_mod.ExternalRecipes,

    pub fn deinit(self: *LoadedJakefile) void {
        self.runtime.deinit();
        self.index.deinit();
        self.jakefile.deinit(self.allocator);
        self.allocator.free(self.source);

        for (self.watch_files) |path| {
            self.allocator.free(path);
        }
        self.allocator.free(self.watch_files);

        if (self.external_allocations) |*allocs| {
            var mutable_allocs = allocs.*;
            mutable_allocs.deinit();
        }
        if (self.import_allocations) |*allocs| {
            var mutable_allocs = allocs.*;
            mutable_allocs.deinit();
        }
    }
};

pub const FindJakefileResult = struct {
    path: []const u8,
    dir: ?[]const u8,
};

/// Searches for a Jakefile starting from the current directory and traversing up
/// to parent directories. Returns the path to the found Jakefile.
/// Only traverses if the path is the default "Jakefile" - explicit paths are used as-is.
pub fn findJakefile(allocator: std.mem.Allocator, requested_path: []const u8) !FindJakefileResult {
    if (!std.mem.eql(u8, requested_path, "Jakefile")) {
        return .{ .path = requested_path, .dir = null };
    }

    if (std.fs.cwd().openFile("Jakefile", .{})) |file| {
        file.close();
        return .{ .path = "Jakefile", .dir = null };
    } else |_| {}

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &path_buf) catch return error.FileNotFound;

    var current_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(current_buf[0..cwd.len], cwd);
    var current_dir: []const u8 = current_buf[0..cwd.len];

    while (true) {
        const parent = std.fs.path.dirname(current_dir) orelse break;
        if (parent.len == 0 or std.mem.eql(u8, parent, current_dir)) break;

        var parent_buf: [std.fs.max_path_bytes]u8 = undefined;
        const jakefile_path = std.fmt.bufPrint(&parent_buf, "{s}/Jakefile", .{parent}) catch break;

        if (std.fs.cwd().openFile(jakefile_path, .{})) |file| {
            file.close();

            const path_copy = allocator.dupe(u8, jakefile_path) catch return error.OutOfMemory;
            const dir_copy = allocator.dupe(u8, parent) catch {
                allocator.free(path_copy);
                return error.OutOfMemory;
            };
            return .{ .path = path_copy, .dir = dir_copy };
        } else |_| {}

        current_dir = current_buf[0..parent.len];
    }

    return error.FileNotFound;
}

pub fn loadJakefile(allocator: std.mem.Allocator, path: []const u8) !LoadedJakefile {
    const found = try findJakefile(allocator, path);
    defer if (found.dir) |dir| allocator.free(dir);
    const jakefile_path = found.path;
    defer if (found.dir != null) allocator.free(jakefile_path);

    if (found.dir) |dir| {
        std.posix.chdir(dir) catch return error.FileNotFound;
    }

    const actual_path = if (found.dir != null) "Jakefile" else jakefile_path;
    const file = try std.fs.cwd().openFile(actual_path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(source);

    var jakefile = try parseJakefileSource(allocator, source, actual_path);
    errdefer jakefile.deinit(allocator);

    var import_allocations: ?import_mod.ImportAllocations = null;
    errdefer if (import_allocations) |*allocs| {
        var mutable_allocs = allocs.*;
        mutable_allocs.deinit();
    };

    if (jakefile.imports.len > 0) {
        import_allocations = import_mod.resolveImports(allocator, &jakefile, actual_path) catch |err| {
            printImportError(err);
            return error.ImportFailed;
        };
    }

    const base_dir = std.fs.path.dirname(actual_path) orelse ".";
    var external_allocations: ?external_mod.ExternalRecipes = null;
    errdefer if (external_allocations) |*allocs| {
        var mutable_allocs = allocs.*;
        mutable_allocs.deinit();
    };

    external_allocations = external_mod.loadAndMergeExternalRecipes(allocator, &jakefile, base_dir) catch |err| blk: {
        printExternalWarning(err);
        break :blk null;
    };

    var index = try JakefileIndex.build(allocator, &jakefile);
    errdefer index.deinit();

    var runtime = RuntimeContext.init(allocator);
    errdefer runtime.deinit();
    try runtime.configure(&jakefile, &index);

    const watch_files = try collectWatchFiles(allocator, actual_path, base_dir);
    errdefer {
        for (watch_files) |watch_file| {
            allocator.free(watch_file);
        }
        allocator.free(watch_files);
    }

    return .{
        .jakefile = jakefile,
        .index = index,
        .runtime = runtime,
        .source = source,
        .watch_files = watch_files,
        .allocator = allocator,
        .import_allocations = import_allocations,
        .external_allocations = external_allocations,
    };
}

fn collectWatchFiles(allocator: std.mem.Allocator, root_path: []const u8, base_dir: []const u8) ![]const []const u8 {
    const project_root_abs = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(project_root_abs);

    const root_abs = if (std.fs.path.isAbsolute(root_path))
        try allocator.dupe(u8, root_path)
    else
        try std.fs.cwd().realpathAlloc(allocator, root_path);
    defer allocator.free(root_abs);

    var watch_files: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer deinitOwnedStringList(allocator, &watch_files);

    var seen_realpaths: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var key_iter = seen_realpaths.keyIterator();
        while (key_iter.next()) |key| {
            allocator.free(key.*);
        }
        seen_realpaths.deinit(allocator);
    }

    try collectImportWatchFiles(allocator, &watch_files, &seen_realpaths, project_root_abs, root_abs);
    try collectExternalWatchFiles(allocator, &watch_files, project_root_abs, base_dir);

    return try watch_files.toOwnedSlice(allocator);
}

fn collectImportWatchFiles(
    allocator: std.mem.Allocator,
    watch_files: *std.ArrayListUnmanaged([]const u8),
    seen_realpaths: *std.StringHashMapUnmanaged(void),
    project_root_abs: []const u8,
    file_abs: []const u8,
) !void {
    if (seen_realpaths.contains(file_abs)) {
        return;
    }

    const seen_key = try allocator.dupe(u8, file_abs);
    errdefer allocator.free(seen_key);
    try seen_realpaths.put(allocator, seen_key, {});

    const watch_path = try relativizeWatchPath(allocator, project_root_abs, file_abs);
    try appendOwnedUniquePath(allocator, watch_files, watch_path);

    const file = try std.fs.openFileAbsolute(file_abs, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    var imported = try parseJakefileSource(allocator, source, file_abs);
    defer imported.deinit(allocator);

    const file_dir = std.fs.path.dirname(file_abs) orelse ".";
    for (imported.imports) |directive| {
        const import_abs = try resolveImportAbsolutePath(allocator, directive.path, file_dir);
        defer allocator.free(import_abs);
        try collectImportWatchFiles(allocator, watch_files, seen_realpaths, project_root_abs, import_abs);
    }
}

pub fn isParseError(err: anyerror) bool {
    return err == parser_mod.ParseError.UnexpectedToken or
        err == parser_mod.ParseError.UnexpectedEof or
        err == parser_mod.ParseError.InvalidSyntax or
        err == parser_mod.ParseError.InvalidTimeoutFormat or
        err == parser_mod.ParseError.InvalidTimeoutValue;
}

fn parseJakefileSource(allocator: std.mem.Allocator, source: []const u8, path: []const u8) !Jakefile {
    var lex = Lexer.init(source);
    var p = Parser.init(allocator, &lex);
    return p.parseJakefile() catch |err| {
        if (p.getLastError()) |info| {
            printParseError(path, source, info);
        }
        return err;
    };
}

fn collectExternalWatchFiles(
    allocator: std.mem.Allocator,
    watch_files: *std.ArrayListUnmanaged([]const u8),
    project_root_abs: []const u8,
    base_dir: []const u8,
) !void {
    const external_files = try external_mod.detectExternalFiles(allocator, base_dir);
    defer {
        var mutable_files = external_files;
        mutable_files.deinit(allocator);
    }

    if (external_files.makefile) |makefile| {
        const path = try joinBasePath(allocator, base_dir, makefile);
        defer allocator.free(path);

        const watch_path = if (std.fs.path.isAbsolute(path))
            try relativizeWatchPath(allocator, project_root_abs, path)
        else
            try allocator.dupe(u8, path);
        try appendOwnedUniquePath(allocator, watch_files, watch_path);
    }

    if (external_files.justfile) |justfile| {
        const path = try joinBasePath(allocator, base_dir, justfile);
        defer allocator.free(path);

        const watch_path = if (std.fs.path.isAbsolute(path))
            try relativizeWatchPath(allocator, project_root_abs, path)
        else
            try allocator.dupe(u8, path);
        try appendOwnedUniquePath(allocator, watch_files, watch_path);
    }
}

fn resolveImportAbsolutePath(allocator: std.mem.Allocator, path: []const u8, base_dir: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        return try allocator.dupe(u8, path);
    }

    const joined = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, path });
    defer allocator.free(joined);

    return try std.fs.cwd().realpathAlloc(allocator, joined);
}

fn relativizeWatchPath(allocator: std.mem.Allocator, project_root_abs: []const u8, path_abs: []const u8) ![]u8 {
    if (!std.fs.path.isAbsolute(path_abs)) {
        return try allocator.dupe(u8, path_abs);
    }

    return std.fs.path.relative(allocator, project_root_abs, path_abs);
}

fn joinBasePath(allocator: std.mem.Allocator, base_dir: []const u8, file_name: []const u8) ![]u8 {
    if (base_dir.len == 0 or std.mem.eql(u8, base_dir, ".")) {
        return try allocator.dupe(u8, file_name);
    }

    return try std.fs.path.join(allocator, &[_][]const u8{ base_dir, file_name });
}

fn appendOwnedUniquePath(allocator: std.mem.Allocator, watch_files: *std.ArrayListUnmanaged([]const u8), path: []u8) !void {
    for (watch_files.items) |existing| {
        if (std.mem.eql(u8, existing, path)) {
            allocator.free(path);
            return;
        }
    }

    try watch_files.append(allocator, path);
}

fn deinitOwnedStringList(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged([]const u8)) void {
    for (list.items) |item| {
        allocator.free(item);
    }
    list.deinit(allocator);
}

fn printImportError(err: anyerror) void {
    const stderr = compat.getStdErr();
    var buf: [512]u8 = undefined;
    const msg = switch (err) {
        error.CircularImport => "Circular import detected",
        error.FileNotFound => "Imported file not found",
        error.ParseError => "Failed to parse imported file",
        else => @errorName(err),
    };
    // Name the offending import path when we captured it (ImportError values
    // carry no payload); falls back to the bare message otherwise.
    const err_msg = if (import_mod.lastFailedImport()) |path|
        std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Import failed: {s}: \"{s}\"\n", .{ msg, path }) catch return
    else
        std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Import failed: {s}\n", .{msg}) catch return;
    stderr.writeAll(err_msg) catch {};
}

fn printExternalWarning(err: anyerror) void {
    const stderr = compat.getStdErr();
    var buf: [512]u8 = undefined;
    const warning = std.fmt.bufPrint(&buf, args_mod.ansi.warn_prefix ++ "Failed to load external build files: {s}\n", .{@errorName(err)}) catch return;
    stderr.writeAll(warning) catch {};
}

fn printParseError(path: []const u8, source: []const u8, info: parser_mod.ErrorInfo) void {
    const stderr = compat.getStdErr();
    var buf: [2048]u8 = undefined;
    const msg = info.formatDetailedMessage(source, &buf);

    stderr.writeAll(args_mod.ansi.err_prefix) catch {};
    stderr.writeAll("Failed to parse Jakefile") catch {};
    if (path.len > 0) {
        stderr.writeAll(" '") catch {};
        stderr.writeAll(path) catch {};
        stderr.writeAll("'") catch {};
    }
    stderr.writeAll("\n") catch {};
    stderr.writeAll(msg) catch {};
    stderr.writeAll("\n") catch {};
}
