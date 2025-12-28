// Jake Cache - File hash tracking for incremental builds

const std = @import("std");

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
        // Simple implementation: check if pattern contains glob chars
        if (std.mem.indexOfAny(u8, pattern, "*?") != null) {
            // For now, always consider glob patterns stale
            // TODO: Implement proper glob matching
            return true;
        }
        return self.isStale(pattern);
    }

    /// Update the cached hash for a file
    pub fn update(self: *Cache, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const hash = try self.computeHash(file);

        const key = try self.allocator.dupe(u8, path);
        try self.hashes.put(key, .{
            .content_hash = hash,
            .mtime = stat.mtime,
        });
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

            const key = try self.allocator.dupe(u8, path);
            try self.hashes.put(key, .{
                .content_hash = hash,
                .mtime = mtime,
            });
        }
    }

    /// Save cache to disk
    pub fn save(self: *Cache) !void {
        std.fs.cwd().makeDir(".jake") catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const cache_file = try std.fs.cwd().createFile(".jake/cache", .{});
        defer cache_file.close();

        var writer = cache_file.writer();
        var iter = self.hashes.iterator();
        while (iter.next()) |entry| {
            try writer.print("{s}\x00{s}\x00{d}\n", .{
                entry.key_ptr.*,
                std.fmt.fmtSliceHexLower(&entry.value_ptr.content_hash),
                entry.value_ptr.mtime,
            });
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
