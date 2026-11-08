//! File modification tracking for file-target recipes.

const std = @import("std");
const glob_mod = @import("../util/glob.zig");

pub const Cache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    hashes: std.StringHashMap(Hash),
    dirty: ?std.StringHashMap(void) = null,

    pub const Hash = struct {
        content_hash: [32]u8,
        mtime: i128,
    };

    // Stored alongside ordinary file entries; an absent aggregate is stale.
    const glob_key_prefix = "\x01jake-glob:";
    const scoped_key_prefix = "\x01jake-scope:";

    fn globKey(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
        return std.mem.concat(allocator, u8, &.{ glob_key_prefix, pattern });
    }

    fn globFingerprint(allocator: std.mem.Allocator, pattern: []const u8) !Hash {
        const files = try glob_mod.expandGlob(allocator, pattern);
        defer {
            for (files) |file| allocator.free(file);
            allocator.free(files);
        }
        if (files.len == 0) return error.FileNotFound;
        std.mem.sort([]const u8, files, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(pattern);
        hasher.update("\x00");
        for (files) |path| {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();
            const stat = try file.stat();
            var file_hasher = std.crypto.hash.sha2.Sha256.init(.{});
            var buffer: [8192]u8 = undefined;
            while (true) {
                const count = try file.read(&buffer);
                if (count == 0) break;
                file_hasher.update(buffer[0..count]);
            }
            const digest = file_hasher.finalResult();
            hasher.update(path);
            hasher.update("\x00");
            hasher.update(&digest);
            hasher.update("\x00");
            _ = stat;
        }
        return .{ .content_hash = hasher.finalResult(), .mtime = 0 };
    }

    fn patternFingerprint(self: *Cache, pattern: []const u8) !Hash {
        if (glob_mod.isGlobPattern(pattern)) return globFingerprint(self.allocator, pattern);
        const file = try std.fs.cwd().openFile(pattern, .{});
        defer file.close();
        return .{ .content_hash = try self.computeHash(file), .mtime = 0 };
    }

    fn scopedKey(allocator: std.mem.Allocator, scope: []const u8, pattern: []const u8) ![]u8 {
        return std.mem.concat(allocator, u8, &.{ scoped_key_prefix, scope, "\x1f", pattern });
    }

    pub fn isScopedPatternStale(self: *Cache, scope: []const u8, pattern: []const u8) !bool {
        const key = try scopedKey(self.allocator, scope, pattern);
        defer self.allocator.free(key);
        const cached = self.hashes.get(key) orelse return true;
        const current = self.patternFingerprint(pattern) catch return true;
        return !std.mem.eql(u8, &cached.content_hash, &current.content_hash);
    }

    pub fn updateScopedPattern(self: *Cache, scope: []const u8, pattern: []const u8) !void {
        const key = try scopedKey(self.allocator, scope, pattern);
        defer self.allocator.free(key);
        const fingerprint = try self.patternFingerprint(pattern);
        try self.putHash(key, fingerprint);
    }

    pub fn init(allocator: std.mem.Allocator) Cache {
        return .{
            .allocator = allocator,
            .cache_dir = ".jake",
            .hashes = std.StringHashMap(Hash).init(allocator),
        };
    }

    pub fn clone(self: *const Cache, allocator: std.mem.Allocator) !Cache {
        var copy = Cache.init(allocator);
        errdefer copy.deinit();

        var iter = self.hashes.iterator();
        while (iter.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            errdefer allocator.free(key);
            try copy.hashes.put(key, entry.value_ptr.*);
        }

        return copy;
    }

    pub fn fork(self: *const Cache, allocator: std.mem.Allocator) !Cache {
        var copy = try self.clone(allocator);
        copy.dirty = std.StringHashMap(void).init(allocator);
        return copy;
    }

    pub fn mergeChangesFrom(self: *Cache, forked: *const Cache) !void {
        const dirty = forked.dirty orelse return;
        var iter = dirty.keyIterator();
        while (iter.next()) |key_ptr| {
            const value = forked.hashes.get(key_ptr.*) orelse continue;
            try self.putHash(key_ptr.*, value);
        }
    }

    pub fn mergeFrom(self: *Cache, other: *const Cache) !void {
        var iter = other.hashes.iterator();
        while (iter.next()) |entry| try self.putHash(entry.key_ptr.*, entry.value_ptr.*);
    }

    pub fn deinit(self: *Cache) void {
        var iter = self.hashes.keyIterator();
        while (iter.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.hashes.deinit();
        if (self.dirty) |*dirty| {
            var dirty_iter = dirty.keyIterator();
            while (dirty_iter.next()) |key_ptr| self.allocator.free(key_ptr.*);
            dirty.deinit();
        }
    }

    fn putHash(self: *Cache, key: []const u8, value: Hash) !void {
        if (self.hashes.getPtr(key)) |existing| existing.* = value else {
            const owned = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(owned);
            try self.hashes.put(owned, value);
        }
        if (self.dirty) |*dirty| if (!dirty.contains(key)) {
            const owned = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(owned);
            try dirty.put(owned, {});
        };
    }

    /// Check if a file has changed since its hash was last recorded.
    ///
    /// A file's mtime is metadata, not a content version: copies and source
    /// checkouts can restore it, and some filesystems coalesce rapid writes.
    /// Compare the content hash on every cached lookup so a same-mtime edit
    /// cannot cause a file target to be falsely treated as fresh.
    pub fn isStale(self: *Cache, path: []const u8) !bool {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) return true;
            return err;
        };
        defer file.close();

        if (self.hashes.get(path)) |cached| {
            const current_hash = try self.computeHash(file);
            return !std.mem.eql(u8, &cached.content_hash, &current_hash);
        }

        // No cached hash, file is stale (needs building)
        return true;
    }

    /// Check if any file matching glob pattern has changed
    pub fn isGlobStale(self: *Cache, pattern: []const u8) !bool {
        if (glob_mod.isGlobPattern(pattern)) {
            const key = try globKey(self.allocator, pattern);
            defer self.allocator.free(key);
            const cached = self.hashes.get(key) orelse return true;
            const current = globFingerprint(self.allocator, pattern) catch return true;
            return !std.mem.eql(u8, &cached.content_hash, &current.content_hash);
        }
        return self.isStale(pattern);
    }

    /// Update the cached hash for a file
    pub fn update(self: *Cache, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const hash = try self.computeHash(file);

        const hash_entry = Hash{
            .content_hash = hash,
            .mtime = stat.mtime,
        };

        try self.putHash(path, hash_entry);
    }

    /// Update one or more cache entries from a literal path or glob pattern.
    pub fn updatePattern(self: *Cache, pattern: []const u8) !void {
        if (!glob_mod.isGlobPattern(pattern)) {
            return self.update(pattern);
        }

        const files = try glob_mod.expandGlob(self.allocator, pattern);
        defer {
            for (files) |file| {
                self.allocator.free(file);
            }
            self.allocator.free(files);
        }

        for (files) |file| {
            try self.update(file);
        }
        const key = try globKey(self.allocator, pattern);
        defer self.allocator.free(key);
        const fingerprint = try globFingerprint(self.allocator, pattern);
        try self.putHash(key, fingerprint);
    }

    fn computeHash(self: *Cache, file: std.fs.File) ![32]u8 {
        _ = self;
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});

        var buffer: [8192]u8 = undefined;
        while (true) {
            const bytes_read = try file.read(&buffer);
            if (bytes_read == 0) break;
            hasher.update(buffer[0..bytes_read]);
        }

        return hasher.finalResult();
    }

    /// Load cache from disk
    pub fn load(self: *Cache) !void {
        const cache_file = std.fs.cwd().openFile(".jake/cache", .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer cache_file.close();

        // Simple format: path\0hash\0mtime\n repeated
        const content = try cache_file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            var parts = std.mem.splitScalar(u8, line, '\x00');
            const path = parts.next() orelse continue;
            const hash_hex = parts.next() orelse continue;
            const mtime_str = parts.next() orelse continue;

            var hash: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&hash, hash_hex) catch continue;
            const mtime = std.fmt.parseInt(i128, mtime_str, 10) catch continue;

            const hash_entry = Hash{
                .content_hash = hash,
                .mtime = mtime,
            };

            if (self.hashes.getPtr(path)) |value_ptr| {
                value_ptr.* = hash_entry;
            } else {
                const key = try self.allocator.dupe(u8, path);
                errdefer self.allocator.free(key);
                try self.hashes.put(key, hash_entry);
            }
        }
    }

    /// Save cache to disk
    pub fn save(self: *Cache) !void {
        std.fs.cwd().makeDir(".jake") catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const cache_file = try std.fs.cwd().createFile(".jake/cache", .{});
        defer cache_file.close();

        var iter = self.hashes.iterator();
        while (iter.next()) |entry| {
            // Write key
            cache_file.writeAll(entry.key_ptr.*) catch continue;
            cache_file.writeAll("\x00") catch continue;
            // Write hash as hex
            var hex_buf: [64]u8 = undefined;
            for (entry.value_ptr.content_hash, 0..) |byte, i| {
                _ = std.fmt.bufPrint(hex_buf[i * 2 ..][0..2], "{x:0>2}", .{byte}) catch break;
            }
            cache_file.writeAll(hex_buf[0..64]) catch continue;
            cache_file.writeAll("\x00") catch continue;
            // Write mtime
            var mtime_buf: [32]u8 = undefined;
            const mtime = std.fmt.bufPrint(&mtime_buf, "{d}\n", .{entry.value_ptr.mtime}) catch continue;
            cache_file.writeAll(mtime) catch continue;
        }
    }
};

test "cache basic" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    // Test with non-existent file
    const stale = cache.isStale("nonexistent.txt") catch true;
    try std.testing.expect(stale);
}

// ============================================================================
// COMPREHENSIVE CACHE TESTS
// ============================================================================

// --- Hash Computation ---

test "cache init creates empty hash map" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    try std.testing.expectEqual(@as(usize, 0), cache.hashes.count());
}

test "cache uses .jake as default cache dir" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    try std.testing.expectEqualStrings(".jake", cache.cache_dir);
}

// --- Stale Detection ---

test "cache isStale returns true for missing file" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    const result = cache.isStale("definitely_does_not_exist_12345.txt");
    // Either returns true or an error - both are valid for a missing file
    if (result) |stale| {
        try std.testing.expect(stale);
    } else |_| {
        // Error is also acceptable
    }
}

test "cache isStale returns true for file not in cache" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    // Create a temporary file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile("test.txt", .{});
    try file.writeAll("test content");
    file.close();

    // Should be stale because not in cache
    const cwd = std.fs.cwd();
    const abs_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, "test.txt");
    defer std.testing.allocator.free(abs_path);

    // Change to tmp dir to test
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    const stale = try cache.isStale("test.txt");
    try std.testing.expect(stale);
}

// --- Cache Update ---

test "cache update stores file hash" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    // Create a temporary file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile("test.txt", .{});
    try file.writeAll("test content");
    file.close();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    // Update cache
    try cache.update("test.txt");

    // Verify hash is stored
    try std.testing.expectEqual(@as(usize, 1), cache.hashes.count());
    try std.testing.expect(cache.hashes.contains("test.txt"));
}

test "cache isStale returns false after update" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    // Create a temporary file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile("test.txt", .{});
    try file.writeAll("test content");
    file.close();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    // Update cache
    try cache.update("test.txt");

    // Should not be stale now
    const stale = try cache.isStale("test.txt");
    try std.testing.expect(!stale);
}

test "cache update can be called multiple times" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    // Create a temporary file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile("test.txt", .{});
    try file.writeAll("test content");
    file.close();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    // Update cache multiple times
    try cache.update("test.txt");
    try cache.update("test.txt");
    try cache.update("test.txt");

    // Should still have only one entry
    try std.testing.expectEqual(@as(usize, 1), cache.hashes.count());
}

test "cache updatePattern expands glob matches" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    {
        const file = try std.fs.cwd().createFile("a.txt", .{});
        try file.writeAll("a");
        file.close();
    }
    {
        const file = try std.fs.cwd().createFile("b.txt", .{});
        try file.writeAll("b");
        file.close();
    }
    {
        const file = try std.fs.cwd().createFile("c.md", .{});
        try file.writeAll("c");
        file.close();
    }

    try cache.updatePattern("*.txt");

    try std.testing.expect(cache.hashes.contains("a.txt"));
    try std.testing.expect(cache.hashes.contains("b.txt"));
    try std.testing.expect(!cache.hashes.contains("*.txt"));
}

test "cache glob fingerprint detects membership changes" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const old_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);
    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};
    try std.fs.cwd().writeFile(.{ .sub_path = "a.txt", .data = "a" });
    try std.fs.cwd().writeFile(.{ .sub_path = "b.txt", .data = "b" });
    try cache.updatePattern("*.txt");
    try std.testing.expect(!try cache.isGlobStale("*.txt"));
    try std.fs.cwd().deleteFile("b.txt");
    try std.testing.expect(try cache.isGlobStale("*.txt"));
    try std.fs.cwd().writeFile(.{ .sub_path = "c.txt", .data = "c" });
    try std.testing.expect(try cache.isGlobStale("*.txt"));
}

test "cache clone and merge preserve entries" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    {
        const file = try std.fs.cwd().createFile("test.txt", .{});
        try file.writeAll("test");
        file.close();
    }

    try cache.update("test.txt");

    var copy = try cache.clone(std.testing.allocator);
    defer copy.deinit();

    try std.testing.expect(copy.hashes.contains("test.txt"));

    {
        const file = try std.fs.cwd().createFile("other.txt", .{});
        try file.writeAll("other");
        file.close();
    }
    try copy.update("other.txt");
    try cache.mergeFrom(&copy);

    try std.testing.expect(cache.hashes.contains("test.txt"));
    try std.testing.expect(cache.hashes.contains("other.txt"));
}

// --- Load/Save Persistence ---

test "cache save creates cache directory" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    // Create a temporary directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    // Save (should create .jake directory)
    try cache.save();

    // Verify .jake directory exists
    var dir = try std.fs.cwd().openDir(".jake", .{});
    dir.close();
}

test "cache save and load roundtrip" {
    // Create temporary directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    // Create test file
    const file = try std.fs.cwd().createFile("test.txt", .{});
    try file.writeAll("test content");
    file.close();

    // Create and save cache
    {
        var cache = Cache.init(std.testing.allocator);
        defer cache.deinit();

        try cache.update("test.txt");
        try cache.save();
    }

    // Load cache in new instance
    {
        var cache2 = Cache.init(std.testing.allocator);
        defer cache2.deinit();

        try cache2.load();

        // Verify entry was loaded
        try std.testing.expectEqual(@as(usize, 1), cache2.hashes.count());
        try std.testing.expect(cache2.hashes.contains("test.txt"));

        // File should not be stale
        const stale = try cache2.isStale("test.txt");
        try std.testing.expect(!stale);
    }
}

test "cache load handles missing cache file" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    // Create temporary directory (no cache file)
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    // Load should succeed (just return empty)
    try cache.load();
    try std.testing.expectEqual(@as(usize, 0), cache.hashes.count());
}

// --- Content-based Hashing ---

test "cache detects content change after its mtime is restored" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    // Create temporary directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    // Create and cache file
    {
        const file = try std.fs.cwd().createFile("test.txt", .{});
        try file.writeAll("original content");
        file.close();
    }

    try cache.update("test.txt");

    // Verify not stale initially
    {
        const stale = try cache.isStale("test.txt");
        try std.testing.expect(!stale);
    }

    const original_times = try std.fs.cwd().openFile("test.txt", .{});
    const original_stat = try original_times.stat();
    original_times.close();

    // Rewrite with the same length, then restore the original timestamps. This
    // models source restoration and coarse-mtime filesystems without a sleep.
    {
        const file = try std.fs.cwd().createFile("test.txt", .{});
        try file.writeAll("changed! content");
        try file.updateTimes(original_stat.atime, original_stat.mtime);
        file.close();
    }

    // Should now be stale
    {
        const stale = try cache.isStale("test.txt");
        try std.testing.expect(stale);
    }
}

// --- Hash Structure ---

test "cache Hash stores content hash and mtime" {
    const hash = Cache.Hash{
        .content_hash = [_]u8{0} ** 32,
        .mtime = 12345,
    };

    try std.testing.expectEqual(@as(i128, 12345), hash.mtime);
    try std.testing.expectEqual(@as(usize, 32), hash.content_hash.len);
}

// --- Glob Stale Detection ---

test "cache isGlobStale returns true for non-glob missing file" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    const result = cache.isGlobStale("nonexistent_file.txt");
    if (result) |stale| {
        try std.testing.expect(stale);
    } else |_| {
        // Error is also acceptable for missing file
    }
}

// --- Deinit ---

test "cache deinit frees allocated keys" {
    var cache = Cache.init(std.testing.allocator);

    // Create temporary directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    // Create test files
    {
        const file = try std.fs.cwd().createFile("test1.txt", .{});
        try file.writeAll("content1");
        file.close();
    }
    {
        const file = try std.fs.cwd().createFile("test2.txt", .{});
        try file.writeAll("content2");
        file.close();
    }

    try cache.update("test1.txt");
    try cache.update("test2.txt");

    // deinit should free all allocated keys without leaking
    cache.deinit();
}

// --- Multiple Files ---

test "cache handles multiple files" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    // Create temporary directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    // Create multiple test files
    const files = [_][]const u8{ "a.txt", "b.txt", "c.txt" };
    for (files) |filename| {
        const file = try std.fs.cwd().createFile(filename, .{});
        try file.writeAll(filename);
        file.close();
    }

    // Update all files
    for (files) |filename| {
        try cache.update(filename);
    }

    // Verify all are cached
    try std.testing.expectEqual(@as(usize, 3), cache.hashes.count());
    for (files) |filename| {
        try std.testing.expect(cache.hashes.contains(filename));
        const stale = try cache.isStale(filename);
        try std.testing.expect(!stale);
    }
}

test "cache fork merges only its writes and preserves a newer sibling fingerprint" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "input", .data = "old" });
    try tmp.dir.writeFile(.{ .sub_path = "other", .data = "other" });
    const input = try tmp.dir.realpathAlloc(allocator, "input");
    defer allocator.free(input);
    const other = try tmp.dir.realpathAlloc(allocator, "other");
    defer allocator.free(other);
    var committed = Cache.init(allocator);
    defer committed.deinit();
    try committed.update(input);
    var earlier = try committed.fork(allocator);
    defer earlier.deinit();
    var newer = try committed.fork(allocator);
    defer newer.deinit();
    try tmp.dir.writeFile(.{ .sub_path = "input", .data = "new" });
    var staged = Cache.init(allocator);
    defer staged.deinit();
    try staged.update(input);
    // Recipe publication uses mergeFrom on a worker view: it must track writes.
    try newer.mergeFrom(&staged);
    try committed.mergeChangesFrom(&newer);
    try earlier.update(other);
    try committed.mergeChangesFrom(&earlier);
    try std.testing.expect(!try committed.isStale(input));
    // Restoring old content must invalidate the newer record, not resurrect it.
    try tmp.dir.writeFile(.{ .sub_path = "input", .data = "old" });
    try std.testing.expect(try committed.isStale(input));
}

fn checkForkAllocations(allocator: std.mem.Allocator, path: []const u8) !void {
    var cache = Cache.init(allocator);
    defer cache.deinit();
    try cache.update(path);
    var forked = try cache.fork(allocator);
    defer forked.deinit();
    try forked.updateScopedPattern("consumer", path);
    try cache.mergeChangesFrom(&forked);
    try cache.updatePattern(path);
}

test "cache fork and scoped publication release all allocation-failure state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "input", .data = "input" });
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, "input");
    defer std.testing.allocator.free(path);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkForkAllocations, .{path});
}
