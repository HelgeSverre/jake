// Jake Init - Scaffolding functionality
//
// Creates a new Jakefile from templates.

const std = @import("std");

pub const InitError = error{
    TemplateNotFound,
    InvalidTemplate,
    FileSystemError,
    FileExists,
};

pub const Template = enum {
    starter,
    blank,
};

pub const Options = struct {
    template: Template = .starter,
    force: bool = false,
    path: ?[]const u8 = null,
};

const starter_template = @embedFile("templates/starter.jake");
const blank_template = @embedFile("templates/blank.jake");

fn getTemplateContent(template: Template) []const u8 {
    return switch (template) {
        .starter => starter_template,
        .blank => blank_template,
    };
}

fn getTemplateName(template: Template) []const u8 {
    return switch (template) {
        .starter => "starter",
        .blank => "blank",
    };
}

pub fn run(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
) !void {
    return runInDir(allocator, options, writer, std.fs.cwd());
}

fn runInDir(
    allocator: std.mem.Allocator,
    options: Options,
    writer: anytype,
    dir: std.fs.Dir,
) !void {
    _ = allocator;
    const content = getTemplateContent(options.template);
    const template_name = getTemplateName(options.template);

    const file_path = if (options.path) |p|
        p
    else
        "Jakefile";

    // Check if file exists (unless force is true)
    if (!options.force) {
        const file = dir.openFile(file_path, .{}) catch null;
        if (file) |f| {
            defer f.close();
            return error.FileExists;
        }
    }

    // Write the Jakefile
    dir.writeFile(.{
        .sub_path = file_path,
        .data = content,
    }) catch |err| {
        if (err == error.PathAlreadyExists) {
            return error.FileExists;
        }
        return error.FileSystemError;
    };

    try writer.print("Created '{s}' using the '{s}' template.\n", .{ file_path, template_name });
    try writer.writeAll("\nRun 'jake' to execute the default task.\n");
    try writer.writeAll("Run 'jake --list' to see all available tasks.\n");
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\USAGE:
        \\    jake init [OPTIONS]
        \\
        \\DESCRIPTION:
        \\    Create a new Jakefile from a template.
        \\
        \\OPTIONS:
        \\    -t, --template <NAME>    Template to use (starter, blank)
        \\    -f, --force              Overwrite existing Jakefile
        \\    -p, --path <PATH>        Path for the Jakefile (default: ./Jakefile)
        \\    -h, --help               Show this help message
        \\
        \\TEMPLATES:
        \\    starter    A comprehensive starting template with common tasks
        \\    blank      A minimal template with just a default task
        \\
        \\EXAMPLES:
        \\    jake init                      Create Jakefile with starter template
        \\    jake init --template=blank     Create minimal Jakefile
        \\    jake init --force              Overwrite existing Jakefile
        \\    jake init --path=build.jake    Create Jakefile with custom name
    );
}

test "Template enum values" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(Template.starter));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(Template.blank));
}

test "getTemplateContent returns non-empty for starter" {
    const content = getTemplateContent(.starter);
    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "@dotenv") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "task build:") != null);
}

test "getTemplateContent returns non-empty for blank" {
    const content = getTemplateContent(.blank);
    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "task default:") != null);
}

test "getTemplateName returns correct names" {
    try std.testing.expectEqualStrings("starter", getTemplateName(.starter));
    try std.testing.expectEqualStrings("blank", getTemplateName(.blank));
}

test "Options has correct defaults" {
    const opts = Options{};
    try std.testing.expectEqual(Template.starter, opts.template);
    try std.testing.expectEqual(false, opts.force);
    try std.testing.expectEqual(@as(?[]const u8, null), opts.path);
}

test "run creates Jakefile with starter template" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try runInDir(std.testing.allocator, .{}, stream.writer(), tmp_dir.dir);

    // Verify file was created with correct content
    const content = try tmp_dir.dir.readFileAlloc(std.testing.allocator, "Jakefile", 1024 * 1024);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "@dotenv") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "task build:") != null);

    // Verify output message
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Created 'Jakefile'") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "'starter' template") != null);
}

test "run creates Jakefile with blank template" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try runInDir(std.testing.allocator, .{ .template = .blank }, stream.writer(), tmp_dir.dir);

    const content = try tmp_dir.dir.readFileAlloc(std.testing.allocator, "Jakefile", 1024 * 1024);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "task default:") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "Hello from jake!") != null);

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "'blank' template") != null);
}

test "run with custom path creates file at specified location" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try runInDir(std.testing.allocator, .{ .path = "custom.jake" }, stream.writer(), tmp_dir.dir);

    // Verify custom file was created
    const content = try tmp_dir.dir.readFileAlloc(std.testing.allocator, "custom.jake", 1024 * 1024);
    defer std.testing.allocator.free(content);
    try std.testing.expect(content.len > 0);

    // Verify output mentions custom path
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Created 'custom.jake'") != null);
}

test "run returns FileExists when file exists and force is false" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create existing file
    try tmp_dir.dir.writeFile(.{ .sub_path = "Jakefile", .data = "existing content" });

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const result = runInDir(std.testing.allocator, .{}, stream.writer(), tmp_dir.dir);
    try std.testing.expectError(error.FileExists, result);
}

test "run overwrites file when force is true" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create existing file with different content
    try tmp_dir.dir.writeFile(.{ .sub_path = "Jakefile", .data = "old content" });

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try runInDir(std.testing.allocator, .{ .force = true }, stream.writer(), tmp_dir.dir);

    // Verify file was overwritten with template content
    const content = try tmp_dir.dir.readFileAlloc(std.testing.allocator, "Jakefile", 1024 * 1024);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "@dotenv") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "old content") == null);
}

test "printHelp outputs usage information" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try printHelp(stream.writer());

    // Verify key sections are present
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "USAGE:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "jake init") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "OPTIONS:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--template") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--force") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--path") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "TEMPLATES:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "starter") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "blank") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "EXAMPLES:") != null);
}
