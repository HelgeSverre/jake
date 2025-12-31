// Jake Upgrade - Self-update functionality
//
// Downloads and installs the latest Jake release from GitHub.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Error Types
// ============================================================================

pub const UpgradeError = error{
    NetworkError,
    HttpError,
    InvalidResponse,
    JsonParseError,
    ChecksumMismatch,
    NoReleaseFound,
    UnsupportedPlatform,
    PermissionDenied,
    FileSystemError,
    VersionParseError,
    AlreadyLatest,
    OutOfMemory,
    InvalidUri,
    TlsError,
    ConnectionRefused,
    EndOfStream,
};

// ============================================================================
// Version Parsing and Comparison
// ============================================================================

pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
    commits_ahead: ?u32 = null, // For "0.4.0-5-gabcdef" format

    /// Parse a version string like "0.4.0", "v0.5.0", or "0.4.0-5-gabcdef"
    pub fn parse(version_str: []const u8) !Version {
        var str = version_str;

        // Strip leading 'v' if present
        if (str.len > 0 and str[0] == 'v') {
            str = str[1..];
        }

        // Check for git describe format: "0.4.0-5-gabcdef"
        var commits_ahead: ?u32 = null;
        if (std.mem.indexOf(u8, str, "-")) |dash_pos| {
            const suffix = str[dash_pos + 1 ..];
            // Check if it's commits-ahead format (number-g...)
            if (std.mem.indexOf(u8, suffix, "-g")) |g_pos| {
                commits_ahead = std.fmt.parseInt(u32, suffix[0..g_pos], 10) catch null;
                str = str[0..dash_pos];
            }
        }

        var parts = std.mem.splitScalar(u8, str, '.');
        const major_str = parts.next() orelse return error.VersionParseError;
        const minor_str = parts.next() orelse "0";
        const patch_str = parts.next() orelse "0";

        const major = std.fmt.parseInt(u32, major_str, 10) catch return error.VersionParseError;
        const minor = std.fmt.parseInt(u32, minor_str, 10) catch return error.VersionParseError;
        const patch = std.fmt.parseInt(u32, patch_str, 10) catch return error.VersionParseError;

        return .{
            .major = major,
            .minor = minor,
            .patch = patch,
            .commits_ahead = commits_ahead,
        };
    }

    /// Compare two versions. Returns ordering.
    pub fn compare(self: Version, other: Version) std.math.Order {
        if (self.major != other.major) return std.math.order(self.major, other.major);
        if (self.minor != other.minor) return std.math.order(self.minor, other.minor);
        if (self.patch != other.patch) return std.math.order(self.patch, other.patch);

        // Dev versions (with commits_ahead) are newer than release versions
        const self_commits = self.commits_ahead orelse 0;
        const other_commits = other.commits_ahead orelse 0;
        return std.math.order(self_commits, other_commits);
    }

    /// Returns true if self is newer than other
    pub fn isNewerThan(self: Version, other: Version) bool {
        return self.compare(other) == .gt;
    }

    /// Format version as string (e.g., "0.4.0" or "0.4.0-5")
    pub fn format(self: Version, buf: []u8) []const u8 {
        if (self.commits_ahead) |commits| {
            return std.fmt.bufPrint(buf, "{d}.{d}.{d}-{d}", .{
                self.major,
                self.minor,
                self.patch,
                commits,
            }) catch "?.?.?";
        }
        return std.fmt.bufPrint(buf, "{d}.{d}.{d}", .{
            self.major,
            self.minor,
            self.patch,
        }) catch "?.?.?";
    }
};

// ============================================================================
// Release Information
// ============================================================================

pub const ReleaseInfo = struct {
    tag: []const u8,
    version: Version,
    download_url: []const u8,
    checksum_url: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ReleaseInfo) void {
        self.allocator.free(self.tag);
        self.allocator.free(self.download_url);
        self.allocator.free(self.checksum_url);
    }
};

// ============================================================================
// Options
// ============================================================================

pub const Options = struct {
    check_only: bool = false,
    skip_verify: bool = false,
    verbose: bool = false,
};

// ============================================================================
// Constants
// ============================================================================

const GITHUB_API_URL = "https://api.github.com/repos/HelgeSverre/jake/releases/latest";
const GITHUB_DOWNLOAD_BASE = "https://github.com/HelgeSverre/jake/releases/download";

// ============================================================================
// Platform Detection
// ============================================================================

/// Get the artifact name for the current platform
pub fn getArtifactName() ![]const u8 {
    const os = builtin.os.tag;
    const arch = builtin.cpu.arch;

    return switch (os) {
        .linux => switch (arch) {
            .x86_64 => "jake-linux-x86_64",
            .aarch64 => "jake-linux-aarch64",
            else => error.UnsupportedPlatform,
        },
        .macos => switch (arch) {
            .x86_64 => "jake-macos-x86_64",
            .aarch64 => "jake-macos-aarch64",
            else => error.UnsupportedPlatform,
        },
        .windows => switch (arch) {
            .x86_64 => "jake-windows-x86_64.exe",
            else => error.UnsupportedPlatform,
        },
        else => error.UnsupportedPlatform,
    };
}

/// Get the path to the currently running executable
fn getSelfPath(allocator: std.mem.Allocator) ![]const u8 {
    return std.fs.selfExePathAlloc(allocator);
}

// ============================================================================
// HTTP Client (uses curl for simplicity and cross-platform support)
// ============================================================================

/// Perform an HTTP GET request and return the response body using curl
fn httpGet(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    // Use curl for HTTP requests - reliable and available on all target platforms
    var child = std.process.Child.init(
        &.{
            "curl",
            "-sSL", // Silent, show errors, follow redirects
            "-H",
            "User-Agent: jake-updater/1.0",
            "-H",
            "Accept: application/vnd.github.v3+json",
            url,
        },
        allocator,
    );
    child.stderr_behavior = .Ignore;
    child.stdout_behavior = .Pipe;

    _ = child.spawn() catch return error.NetworkError;

    const stdout = child.stdout orelse return error.NetworkError;
    const body = stdout.readToEndAlloc(allocator, 2 * 1024 * 1024) catch return error.NetworkError;
    errdefer allocator.free(body);

    const result = child.wait() catch return error.NetworkError;

    if (result.Exited != 0) {
        allocator.free(body);
        return error.HttpError;
    }

    return body;
}

/// Download a file to disk with progress reporting using curl
fn downloadToFile(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_path: []const u8,
    writer: anytype,
) !void {
    writer.writeAll("Downloading... ") catch {};

    // Use curl for downloading - follows redirects, handles HTTPS
    var child = std.process.Child.init(
        &.{
            "curl",
            "-sSL", // Silent, show errors, follow redirects
            "-o",
            dest_path,
            url,
        },
        allocator,
    );
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    _ = child.spawn() catch return error.NetworkError;
    const result = child.wait() catch return error.NetworkError;

    if (result.Exited != 0) {
        return error.HttpError;
    }

    writer.writeAll("done\n") catch {};
}

// ============================================================================
// GitHub API
// ============================================================================

/// Fetch latest release info from GitHub API
fn fetchGitHubRelease(allocator: std.mem.Allocator) !ReleaseInfo {
    const json_data = try httpGet(allocator, GITHUB_API_URL);
    defer allocator.free(json_data);

    return parseReleaseInfo(allocator, json_data);
}

/// Parse GitHub API JSON response
fn parseReleaseInfo(allocator: std.mem.Allocator, json_data: []const u8) !ReleaseInfo {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_data, .{}) catch {
        return error.JsonParseError;
    };
    defer parsed.deinit();

    // Ensure root is an object
    if (parsed.value != .object) return error.InvalidResponse;
    const root = parsed.value.object;

    // Get tag name - must be a string, not null
    const tag_value = root.get("tag_name") orelse return error.InvalidResponse;
    if (tag_value != .string) return error.InvalidResponse;
    const tag = tag_value.string;

    // Get artifact name for this platform
    const artifact_name = try getArtifactName();

    // Find our platform's asset in the assets array - must be an array
    const assets_value = root.get("assets") orelse return error.InvalidResponse;
    if (assets_value != .array) return error.InvalidResponse;
    const assets = assets_value.array;

    var download_url: ?[]const u8 = null;
    for (assets.items) |asset| {
        // Each asset must be an object
        if (asset != .object) continue;
        const obj = asset.object;

        // Get name - must be a string
        const name_value = obj.get("name") orelse continue;
        if (name_value != .string) continue;
        const name = name_value.string;

        if (std.mem.eql(u8, name, artifact_name)) {
            // Get download URL - must be a string
            const url_value = obj.get("browser_download_url") orelse continue;
            if (url_value != .string) continue;
            download_url = url_value.string;
            break;
        }
    }

    if (download_url == null) {
        return error.NoReleaseFound;
    }

    // Build checksum URL
    var checksum_url_buf: [256]u8 = undefined;
    const checksum_url = std.fmt.bufPrint(&checksum_url_buf, "{s}/{s}/checksums.txt", .{
        GITHUB_DOWNLOAD_BASE,
        tag,
    }) catch return error.OutOfMemory;

    return ReleaseInfo{
        .tag = allocator.dupe(u8, tag) catch return error.OutOfMemory,
        .version = try Version.parse(tag),
        .download_url = allocator.dupe(u8, download_url.?) catch return error.OutOfMemory,
        .checksum_url = allocator.dupe(u8, checksum_url) catch return error.OutOfMemory,
        .allocator = allocator,
    };
}

// ============================================================================
// Checksum Verification
// ============================================================================

/// Parse checksums.txt data and return checksum for current platform
/// Extracted for testability - handles the actual parsing logic
fn parseChecksumData(data: []const u8) ?[64]u8 {
    const artifact_name = getArtifactName() catch return null;

    // Parse checksums.txt format: "hash  filename" or "hash filename"
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0) continue;

        // Split on whitespace to get hash and filename
        var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
        const hash = parts.next() orelse continue;
        const filename = parts.next() orelse continue;

        if (std.mem.eql(u8, filename, artifact_name)) {
            if (hash.len == 64) {
                var result: [64]u8 = undefined;
                @memcpy(&result, hash);
                return result;
            }
        }
    }

    return null;
}

/// Fetch and parse checksums.txt, returning the checksum for our platform's binary
fn fetchChecksum(allocator: std.mem.Allocator, checksum_url: []const u8) !?[64]u8 {
    const data = httpGet(allocator, checksum_url) catch {
        return null; // Checksums might not exist for old releases
    };
    defer allocator.free(data);

    return parseChecksumData(data);
}

/// Verify a file's SHA256 checksum matches expected value
fn verifyChecksum(file_path: []const u8, expected_hex: [64]u8) !bool {
    const file = std.fs.cwd().openFile(file_path, .{}) catch return error.FileSystemError;
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [8192]u8 = undefined;

    while (true) {
        const bytes_read = file.read(&buffer) catch return error.FileSystemError;
        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }

    const actual = hasher.finalResult();

    // Convert hash bytes to lowercase hex string
    var actual_hex: [64]u8 = undefined;
    for (actual, 0..) |byte, i| {
        _ = std.fmt.bufPrint(actual_hex[i * 2 ..][0..2], "{x:0>2}", .{byte}) catch return false;
    }

    return std.mem.eql(u8, &actual_hex, &expected_hex);
}

// ============================================================================
// Binary Replacement
// ============================================================================

/// Replace the running binary with a new one
fn replaceBinary(allocator: std.mem.Allocator, new_binary_path: []const u8) !void {
    const self_path = try getSelfPath(allocator);
    defer allocator.free(self_path);

    if (builtin.os.tag == .windows) {
        // Windows: Cannot replace running executable directly
        // Rename current to .old, move new into place
        const old_path = std.fmt.allocPrint(allocator, "{s}.old", .{self_path}) catch return error.OutOfMemory;
        defer allocator.free(old_path);

        // Delete any existing .old file
        std.fs.cwd().deleteFile(old_path) catch {};

        // Rename current -> .old
        std.fs.cwd().rename(self_path, old_path) catch return error.PermissionDenied;

        // Move new -> current
        std.fs.cwd().rename(new_binary_path, self_path) catch return error.FileSystemError;
    } else {
        // Unix: Atomic rename works even on running binary
        std.fs.cwd().rename(new_binary_path, self_path) catch |err| {
            if (err == error.AccessDenied) return error.PermissionDenied;
            return error.FileSystemError;
        };

        // Ensure executable permission
        const file = std.fs.cwd().openFile(self_path, .{ .mode = .read_only }) catch return error.FileSystemError;
        defer file.close();
        file.chmod(0o755) catch {};
    }
}

// ============================================================================
// Main Entry Point
// ============================================================================

/// Run the upgrade process
pub fn run(
    allocator: std.mem.Allocator,
    current_version_str: []const u8,
    options: Options,
    writer: anytype,
) !void {
    // Parse current version
    const current_version = Version.parse(current_version_str) catch {
        writer.writeAll("Warning: Could not parse current version\n") catch {};
        return error.VersionParseError;
    };

    writer.writeAll("Checking for updates...\n") catch {};

    // Fetch latest release info
    var release = try fetchGitHubRelease(allocator);
    defer release.deinit();

    // Display version info
    var current_buf: [32]u8 = undefined;
    var latest_buf: [32]u8 = undefined;
    const current_str = current_version.format(&current_buf);
    const latest_str = release.version.format(&latest_buf);

    writer.print("Current version: {s}\n", .{current_str}) catch {};
    writer.print("Latest version:  {s}\n", .{latest_str}) catch {};

    // Check if update is needed
    if (!release.version.isNewerThan(current_version)) {
        return error.AlreadyLatest;
    }

    // Check-only mode
    if (options.check_only) {
        writer.writeAll("\nUpdate available! Run 'jake upgrade' to install.\n") catch {};
        return;
    }

    writer.writeAll("\n") catch {};

    // Create temp file for download
    var tmp_path_buf: [256]u8 = undefined;
    const tmp_path = std.fmt.bufPrint(&tmp_path_buf, "/tmp/jake-upgrade-{d}", .{
        std.time.milliTimestamp(),
    }) catch return error.OutOfMemory;

    // Download the binary
    try downloadToFile(allocator, release.download_url, tmp_path, writer);

    // Verify checksum (unless skipped)
    if (!options.skip_verify) {
        writer.writeAll("Verifying checksum... ") catch {};

        if (try fetchChecksum(allocator, release.checksum_url)) |expected| {
            const valid = try verifyChecksum(tmp_path, expected);
            if (!valid) {
                // Clean up temp file
                std.fs.cwd().deleteFile(tmp_path) catch {};
                writer.writeAll("FAILED\n") catch {};
                return error.ChecksumMismatch;
            }
            writer.writeAll("done\n") catch {};
        } else {
            writer.writeAll("skipped (no checksum available)\n") catch {};
        }
    }

    // Replace binary
    writer.writeAll("Installing... ") catch {};
    try replaceBinary(allocator, tmp_path);
    writer.writeAll("done\n") catch {};

    writer.print("\nSuccessfully upgraded to jake {s}!\n", .{latest_str}) catch {};
}

// ============================================================================
// Tests
// ============================================================================

test "Version.parse basic semver" {
    const v = try Version.parse("1.2.3");
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 2), v.minor);
    try std.testing.expectEqual(@as(u32, 3), v.patch);
    try std.testing.expect(v.commits_ahead == null);
}

test "Version.parse with v prefix" {
    const v = try Version.parse("v0.5.0");
    try std.testing.expectEqual(@as(u32, 0), v.major);
    try std.testing.expectEqual(@as(u32, 5), v.minor);
    try std.testing.expectEqual(@as(u32, 0), v.patch);
}

test "Version.parse git describe format" {
    const v = try Version.parse("0.4.0-5-gabcdef");
    try std.testing.expectEqual(@as(u32, 0), v.major);
    try std.testing.expectEqual(@as(u32, 4), v.minor);
    try std.testing.expectEqual(@as(u32, 0), v.patch);
    try std.testing.expectEqual(@as(u32, 5), v.commits_ahead.?);
}

test "Version.parse minimal" {
    const v = try Version.parse("1");
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 0), v.minor);
    try std.testing.expectEqual(@as(u32, 0), v.patch);
}

test "Version.compare equal versions" {
    const v1 = try Version.parse("0.4.0");
    const v2 = try Version.parse("0.4.0");
    try std.testing.expectEqual(std.math.Order.eq, v1.compare(v2));
}

test "Version.compare major difference" {
    const v1 = try Version.parse("1.0.0");
    const v2 = try Version.parse("2.0.0");
    try std.testing.expect(v2.isNewerThan(v1));
    try std.testing.expect(!v1.isNewerThan(v2));
}

test "Version.compare minor difference" {
    const v1 = try Version.parse("0.4.0");
    const v2 = try Version.parse("0.5.0");
    try std.testing.expect(v2.isNewerThan(v1));
}

test "Version.compare patch difference" {
    const v1 = try Version.parse("0.4.0");
    const v2 = try Version.parse("0.4.1");
    try std.testing.expect(v2.isNewerThan(v1));
}

test "Version.compare dev vs release" {
    const release = try Version.parse("0.4.0");
    const dev = try Version.parse("0.4.0-5-gabcdef");

    // Dev build (5 commits ahead) is newer than release
    try std.testing.expect(dev.isNewerThan(release));
}

test "Version.compare release vs dev of next version" {
    const dev = try Version.parse("0.4.0-5-gabcdef");
    const next_release = try Version.parse("0.5.0");

    // 0.5.0 is newer than 0.4.0-5-g...
    try std.testing.expect(next_release.isNewerThan(dev));
}

test "getArtifactName returns valid name" {
    const name = try getArtifactName();
    try std.testing.expect(std.mem.startsWith(u8, name, "jake-"));
}

test "Version.format" {
    const v = try Version.parse("1.2.3");
    var buf: [32]u8 = undefined;
    const str = v.format(&buf);
    try std.testing.expectEqualStrings("1.2.3", str);
}

test "Version.format with commits_ahead" {
    const v = try Version.parse("0.4.0-5-gabcdef");
    var buf: [32]u8 = undefined;
    const str = v.format(&buf);
    try std.testing.expectEqualStrings("0.4.0-5", str);
}

// ============================================================================
// Failure Mode Tests
// ============================================================================

// --- JSON Parsing Failure Tests ---

test "parseReleaseInfo fails on empty response" {
    const result = parseReleaseInfo(std.testing.allocator, "");
    try std.testing.expectError(error.JsonParseError, result);
}

test "parseReleaseInfo fails on invalid JSON" {
    const result = parseReleaseInfo(std.testing.allocator, "not valid json {{{");
    try std.testing.expectError(error.JsonParseError, result);
}

test "parseReleaseInfo fails on JSON missing tag_name" {
    const json =
        \\{"assets": []}
    ;
    const result = parseReleaseInfo(std.testing.allocator, json);
    try std.testing.expectError(error.InvalidResponse, result);
}

test "parseReleaseInfo fails on JSON missing assets" {
    const json =
        \\{"tag_name": "v1.0.0"}
    ;
    const result = parseReleaseInfo(std.testing.allocator, json);
    try std.testing.expectError(error.InvalidResponse, result);
}

test "parseReleaseInfo fails on empty assets array" {
    const json =
        \\{"tag_name": "v1.0.0", "assets": []}
    ;
    const result = parseReleaseInfo(std.testing.allocator, json);
    try std.testing.expectError(error.NoReleaseFound, result);
}

test "parseReleaseInfo fails when platform asset not found" {
    // Assets exist but none match our platform
    const json =
        \\{"tag_name": "v1.0.0", "assets": [
        \\  {"name": "jake-unknown-platform", "browser_download_url": "http://example.com/file"}
        \\]}
    ;
    const result = parseReleaseInfo(std.testing.allocator, json);
    try std.testing.expectError(error.NoReleaseFound, result);
}

test "parseReleaseInfo fails on null values in JSON" {
    const json =
        \\{"tag_name": null, "assets": []}
    ;
    const result = parseReleaseInfo(std.testing.allocator, json);
    // Should fail because tag_name is null, not a string
    try std.testing.expect(result == error.InvalidResponse or result == error.JsonParseError);
}

test "parseReleaseInfo fails on assets being wrong type" {
    const json =
        \\{"tag_name": "v1.0.0", "assets": "not an array"}
    ;
    const result = parseReleaseInfo(std.testing.allocator, json);
    // Should fail when trying to access assets as array
    try std.testing.expect(result == error.InvalidResponse or result == error.JsonParseError);
}

test "parseReleaseInfo handles asset missing browser_download_url" {
    const artifact = comptime getArtifactName() catch "jake-linux-x86_64";
    const json = std.fmt.comptimePrint(
        \\{{"tag_name": "v1.0.0", "assets": [
        \\  {{"name": "{s}"}}
        \\]}}
    , .{artifact});
    const result = parseReleaseInfo(std.testing.allocator, json);
    // Asset found but no download URL - should report NoReleaseFound
    try std.testing.expectError(error.NoReleaseFound, result);
}

// --- Checksum Parsing Failure Tests ---

test "fetchChecksum returns null on empty checksums file" {
    // We can't easily test HTTP failures, but we can test the parsing
    // by directly calling the parsing logic
    const result = parseChecksumData("");
    try std.testing.expect(result == null);
}

test "parseChecksumData returns null when no matching platform" {
    const data =
        \\abc123def456abc123def456abc123def456abc123def456abc123def456abc123de  jake-unknown-os
        \\def456abc123def456abc123def456abc123def456abc123def456abc123def456ab  jake-other-platform
    ;
    const result = parseChecksumData(data);
    try std.testing.expect(result == null);
}

test "parseChecksumData handles malformed lines gracefully" {
    const data =
        \\this line has no hash
        \\
        \\
        \\onlyonefield
    ;
    const result = parseChecksumData(data);
    try std.testing.expect(result == null);
}

test "parseChecksumData rejects wrong hash length" {
    const artifact = comptime getArtifactName() catch "jake-linux-x86_64";
    const data = std.fmt.comptimePrint(
        \\tooshort  {s}
    , .{artifact});
    const result = parseChecksumData(data);
    try std.testing.expect(result == null);
}

test "parseChecksumData accepts valid 64-char hash" {
    const artifact = comptime getArtifactName() catch "jake-linux-x86_64";
    const data = std.fmt.comptimePrint(
        \\abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890  {s}
    , .{artifact});
    const result = parseChecksumData(data);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", &result.?);
}

test "parseChecksumData handles multiple entries and finds correct one" {
    const artifact = comptime getArtifactName() catch "jake-linux-x86_64";
    const data = std.fmt.comptimePrint(
        \\1111111111111111111111111111111111111111111111111111111111111111  jake-wrong-platform
        \\2222222222222222222222222222222222222222222222222222222222222222  {s}
        \\3333333333333333333333333333333333333333333333333333333333333333  jake-another-wrong
    , .{artifact});
    const result = parseChecksumData(data);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("2222222222222222222222222222222222222222222222222222222222222222", &result.?);
}

test "parseChecksumData handles Windows line endings" {
    const artifact = comptime getArtifactName() catch "jake-linux-x86_64";
    const data = std.fmt.comptimePrint("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  {s}\r\n", .{artifact});
    const result = parseChecksumData(data);
    try std.testing.expect(result != null);
}

test "parseChecksumData handles tabs as separator" {
    const artifact = comptime getArtifactName() catch "jake-linux-x86_64";
    const data = std.fmt.comptimePrint("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t{s}", .{artifact});
    const result = parseChecksumData(data);
    try std.testing.expect(result != null);
}

// --- Checksum Verification Failure Tests ---

test "verifyChecksum fails on non-existent file" {
    const expected: [64]u8 = .{'a'} ** 64;
    const result = verifyChecksum("/tmp/definitely-does-not-exist-jake-test-12345", expected);
    try std.testing.expectError(error.FileSystemError, result);
}

test "verifyChecksum returns false on mismatched hash" {
    // Create a temp file with known content
    const tmp_path = "/tmp/jake-test-checksum-mismatch";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("test content for checksum");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    // Use a wrong checksum (all zeros)
    const wrong_checksum: [64]u8 = .{'0'} ** 64;
    const result = try verifyChecksum(tmp_path, wrong_checksum);
    try std.testing.expect(result == false);
}

test "verifyChecksum returns true on correct hash" {
    // Create a temp file with known content
    const tmp_path = "/tmp/jake-test-checksum-correct";
    const content = "hello world";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll(content);
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    // SHA256 of "hello world" is known
    const correct_checksum = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9".*;
    const result = try verifyChecksum(tmp_path, correct_checksum);
    try std.testing.expect(result == true);
}

test "verifyChecksum handles empty file" {
    const tmp_path = "/tmp/jake-test-checksum-empty";
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        file.close();
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    // SHA256 of empty string
    const empty_checksum = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".*;
    const result = try verifyChecksum(tmp_path, empty_checksum);
    try std.testing.expect(result == true);
}

// --- Version Parsing Failure Tests ---

test "Version.parse fails on empty string" {
    const result = Version.parse("");
    try std.testing.expectError(error.VersionParseError, result);
}

test "Version.parse fails on non-numeric major" {
    const result = Version.parse("abc.1.2");
    try std.testing.expectError(error.VersionParseError, result);
}

test "Version.parse fails on non-numeric minor" {
    const result = Version.parse("1.abc.2");
    try std.testing.expectError(error.VersionParseError, result);
}

test "Version.parse fails on non-numeric patch" {
    const result = Version.parse("1.2.abc");
    try std.testing.expectError(error.VersionParseError, result);
}

test "Version.parse handles version with only v prefix" {
    const result = Version.parse("v");
    try std.testing.expectError(error.VersionParseError, result);
}

test "Version.parse handles large version numbers" {
    const v = try Version.parse("999.888.777");
    try std.testing.expectEqual(@as(u32, 999), v.major);
    try std.testing.expectEqual(@as(u32, 888), v.minor);
    try std.testing.expectEqual(@as(u32, 777), v.patch);
}

test "Version.parse handles git describe with dirty suffix" {
    // Some systems append -dirty to git describe output
    const v = try Version.parse("0.4.0-5-gabcdef-dirty");
    // Should still parse the base version
    try std.testing.expectEqual(@as(u32, 0), v.major);
    try std.testing.expectEqual(@as(u32, 4), v.minor);
    try std.testing.expectEqual(@as(u32, 0), v.patch);
}

// --- Edge Case Tests ---

test "Version.compare handles same version different format" {
    const v1 = try Version.parse("v1.0.0");
    const v2 = try Version.parse("1.0.0");
    try std.testing.expectEqual(std.math.Order.eq, v1.compare(v2));
}

test "Version.compare handles zero versions" {
    const v1 = try Version.parse("0.0.0");
    const v2 = try Version.parse("0.0.1");
    try std.testing.expect(v2.isNewerThan(v1));
    try std.testing.expect(!v1.isNewerThan(v2));
}

test "Version.isNewerThan same version returns false" {
    const v = try Version.parse("1.2.3");
    try std.testing.expect(!v.isNewerThan(v));
}

test "getArtifactName returns consistent result" {
    // Should return same value when called multiple times
    const name1 = try getArtifactName();
    const name2 = try getArtifactName();
    try std.testing.expectEqualStrings(name1, name2);
}

test "getArtifactName contains os identifier" {
    const name = try getArtifactName();
    const has_os = std.mem.indexOf(u8, name, "linux") != null or
        std.mem.indexOf(u8, name, "macos") != null or
        std.mem.indexOf(u8, name, "windows") != null;
    try std.testing.expect(has_os);
}

test "getArtifactName contains arch identifier" {
    const name = try getArtifactName();
    const has_arch = std.mem.indexOf(u8, name, "x86_64") != null or
        std.mem.indexOf(u8, name, "aarch64") != null;
    try std.testing.expect(has_arch);
}

// --- ReleaseInfo Memory Management Tests ---

test "ReleaseInfo.deinit frees all allocated memory" {
    const json =
        \\{"tag_name": "v1.0.0", "assets": [
        \\  {"name": "jake-macos-aarch64", "browser_download_url": "http://example.com/file"},
        \\  {"name": "jake-linux-x86_64", "browser_download_url": "http://example.com/file2"},
        \\  {"name": "jake-macos-x86_64", "browser_download_url": "http://example.com/file3"},
        \\  {"name": "jake-linux-aarch64", "browser_download_url": "http://example.com/file4"},
        \\  {"name": "jake-windows-x86_64.exe", "browser_download_url": "http://example.com/file5"}
        \\]}
    ;
    var release = try parseReleaseInfo(std.testing.allocator, json);
    // Should not leak memory
    release.deinit();
}

// --- HTTP Error Simulation (via parsing layer) ---
// Since we can't easily mock curl, we test the parsing handles bad data

test "parseReleaseInfo handles truncated JSON gracefully" {
    const result = parseReleaseInfo(std.testing.allocator, "{\"tag_name\": \"v1.0");
    try std.testing.expectError(error.JsonParseError, result);
}

test "parseReleaseInfo handles HTTP error page HTML" {
    const html =
        \\<!DOCTYPE html>
        \\<html><body><h1>500 Internal Server Error</h1></body></html>
    ;
    const result = parseReleaseInfo(std.testing.allocator, html);
    try std.testing.expectError(error.JsonParseError, result);
}

test "parseReleaseInfo handles rate limit JSON response" {
    // GitHub returns this JSON when rate limited
    const rate_limit_json =
        \\{
        \\  "message": "API rate limit exceeded",
        \\  "documentation_url": "https://docs.github.com/rest"
        \\}
    ;
    const result = parseReleaseInfo(std.testing.allocator, rate_limit_json);
    // Missing tag_name, so should fail with InvalidResponse
    try std.testing.expectError(error.InvalidResponse, result);
}
