// Jake Cache - File hash tracking for incremental builds

const std = @import("std");
const glob_mod = @import("glob.zig");

pub const Cache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    hashes: std.StringHashMap(Hash),

    pub const Hash = struct {
        content_hash: [32]u8,
        mtime: i128,
    };

    pub fn init(allocator: std.mem.Allocator) Cache {
        return .{
            .allocator = allocator,
            .cache_dir = ".jake",
            .hashes = std.StringHashMap(Hash).init(allocator),
        };
    }

    pub fn deinit(self: *Cache) void {
        // Free all allocated keys
        var iter = self.hashes.keyIterator();
        while (iter.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.hashes.deinit();
    }

    /// Check if a file has changed since last run
    pub fn isStale(self: *Cache, path: []const u8) !bool {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) return true;
            return err;
        };
        defer file.close();

        const current_hash = try self.computeHash(file);

        if (self.hashes.get(path)) |cached| {
            // Check if hash matches
            return !std.mem.eql(u8, &cached.content_hash, &current_hash);
        }

        // No cached hash, file is stale (needs building)
        return true;
    }

    /// Check if any file matching glob pattern has changed
    pub fn isGlobStale(self: *Cache, pattern: []const u8) !bool {
        // Check if pattern contains glob chars
        if (glob_mod.isGlobPattern(pattern)) {
            // Expand the glob pattern to actual file paths
            const files = glob_mod.expandGlob(self.allocator, pattern) catch {
                // If expansion fails, consider stale
                return true;
            };
            defer {
                for (files) |f| self.allocator.free(f);
                self.allocator.free(files);
            }

            // If no files match, consider stale (might need to build)
            if (files.len == 0) {
                return true;
            }

            // Check if any matched file is stale
            for (files) |file| {
                if (try self.isStale(file)) {
                    return true;
                }
            }
            return false;
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

        // Check if key already exists to avoid duplicating it
        if (self.hashes.getPtr(path)) |value_ptr| {
            // Key exists, just update the value
            value_ptr.* = hash_entry;
        } else {
            // New key, allocate and insert
            const key = try self.allocator.dupe(u8, path);
            errdefer self.allocator.free(key);
            try self.hashes.put(key, hash_entry);
        }
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

            // Check if key already exists to avoid duplicating it
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

test "cache detects content change" {
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

    // Modify the file
    {
        const file = try std.fs.cwd().createFile("test.txt", .{});
        try file.writeAll("modified content");
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
