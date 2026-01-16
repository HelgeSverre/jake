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

pub const ProjectType = enum {
    node,
    rust,
    go,
    python,
    zig_lang,
    unknown,

    pub fn name(self: ProjectType) []const u8 {
        return switch (self) {
            .node => "Node.js",
            .rust => "Rust",
            .go => "Go",
            .python => "Python",
            .zig_lang => "Zig",
            .unknown => "unknown",
        };
    }
};

pub const Template = enum {
    starter,
    blank,
    node,
    go,
    rust,
    python,
    zig_lang,
};

pub const Options = struct {
    template: ?Template = null,
    force: bool = false,
    path: ?[]const u8 = null,
    yes: bool = false,
};

const starter_template = @embedFile("templates/starter.jake");
const blank_template = @embedFile("templates/blank.jake");
const node_template = @embedFile("templates/node.jake");
const go_template = @embedFile("templates/go.jake");
const rust_template = @embedFile("templates/rust.jake");
const python_template = @embedFile("templates/python.jake");
const zig_template = @embedFile("templates/zig.jake");

pub fn detectProjectType(dir: std.fs.Dir) ProjectType {
    if (dir.access("package.json", .{})) |_| return .node else |_| {}
    if (dir.access("Cargo.toml", .{})) |_| return .rust else |_| {}
    if (dir.access("go.mod", .{})) |_| return .go else |_| {}
    if (dir.access("pyproject.toml", .{})) |_| return .python else |_| {}
    if (dir.access("requirements.txt", .{})) |_| return .python else |_| {}
    if (dir.access("build.zig", .{})) |_| return .zig_lang else |_| {}
    return .unknown;
}

fn templateForProjectType(pt: ProjectType) Template {
    return switch (pt) {
        .node => .node,
        .rust => .rust,
        .go => .go,
        .python => .python,
        .zig_lang => .zig_lang,
        .unknown => .starter,
    };
}

fn getTemplateContent(template: Template) []const u8 {
    return switch (template) {
        .starter => starter_template,
        .blank => blank_template,
        .node => node_template,
        .go => go_template,
        .rust => rust_template,
        .python => python_template,
        .zig_lang => zig_template,
    };
}

fn getTemplateName(template: Template) []const u8 {
    return switch (template) {
        .starter => "starter",
        .blank => "blank",
        .node => "node",
        .go => "go",
        .rust => "rust",
        .python => "python",
        .zig_lang => "zig",
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

    const template = if (options.template) |t| t else blk: {
        const project_type = detectProjectType(dir);
        const detected_template = templateForProjectType(project_type);
        if (project_type != .unknown) {
            try writer.print("Detected {s} project, using '{s}' template.\n", .{ project_type.name(), getTemplateName(detected_template) });
        }
        break :blk detected_template;
    };

    const content = getTemplateContent(template);
    const template_name = getTemplateName(template);

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
        \\    Create a new Jakefile from a template. Auto-detects project type
        \\    if no template is specified.
        \\
        \\OPTIONS:
        \\    -t, --template <NAME>    Template to use (see TEMPLATES below)
        \\    -f, --force              Overwrite existing Jakefile
        \\    -p, --path <PATH>        Path for the Jakefile (default: ./Jakefile)
        \\    -y, --yes                Accept defaults, skip prompts
        \\    -h, --help               Show this help message
        \\
        \\TEMPLATES:
        \\    starter    A comprehensive starting template with common tasks
        \\    blank      A minimal template with just a default task
        \\    node       Node.js/npm project template
        \\    go         Go project template
        \\    rust       Rust/Cargo project template
        \\    python     Python project template
        \\    zig        Zig project template
        \\
        \\AUTO-DETECTION:
        \\    If no template is specified, Jake detects the project type:
        \\    - package.json     → node template
        \\    - Cargo.toml       → rust template
        \\    - go.mod           → go template
        \\    - pyproject.toml   → python template
        \\    - build.zig        → zig template
        \\
        \\EXAMPLES:
        \\    jake init                      Auto-detect project and create Jakefile
        \\    jake init --template=blank     Create minimal Jakefile
        \\    jake init --template=node      Create Node.js Jakefile
        \\    jake init --force              Overwrite existing Jakefile
        \\    jake init --path=build.jake    Create Jakefile with custom name
    );
}

test "Template enum values" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(Template.starter));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(Template.blank));
    try std.testing.expectEqual(@as(usize, 2), @intFromEnum(Template.node));
    try std.testing.expectEqual(@as(usize, 3), @intFromEnum(Template.go));
    try std.testing.expectEqual(@as(usize, 4), @intFromEnum(Template.rust));
    try std.testing.expectEqual(@as(usize, 5), @intFromEnum(Template.python));
    try std.testing.expectEqual(@as(usize, 6), @intFromEnum(Template.zig_lang));
}

test "ProjectType enum values" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(ProjectType.node));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(ProjectType.rust));
    try std.testing.expectEqual(@as(usize, 2), @intFromEnum(ProjectType.go));
    try std.testing.expectEqual(@as(usize, 3), @intFromEnum(ProjectType.python));
    try std.testing.expectEqual(@as(usize, 4), @intFromEnum(ProjectType.zig_lang));
    try std.testing.expectEqual(@as(usize, 5), @intFromEnum(ProjectType.unknown));
}

test "ProjectType.name returns correct names" {
    try std.testing.expectEqualStrings("Node.js", ProjectType.node.name());
    try std.testing.expectEqualStrings("Rust", ProjectType.rust.name());
    try std.testing.expectEqualStrings("Go", ProjectType.go.name());
    try std.testing.expectEqualStrings("Python", ProjectType.python.name());
    try std.testing.expectEqualStrings("Zig", ProjectType.zig_lang.name());
    try std.testing.expectEqualStrings("unknown", ProjectType.unknown.name());
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

test "getTemplateContent returns non-empty for node" {
    const content = getTemplateContent(.node);
    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "npm") != null);
}

test "getTemplateContent returns non-empty for go" {
    const content = getTemplateContent(.go);
    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "go build") != null);
}

test "getTemplateContent returns non-empty for rust" {
    const content = getTemplateContent(.rust);
    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "cargo") != null);
}

test "getTemplateContent returns non-empty for python" {
    const content = getTemplateContent(.python);
    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "pytest") != null);
}

test "getTemplateContent returns non-empty for zig_lang" {
    const content = getTemplateContent(.zig_lang);
    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "zig build") != null);
}

test "getTemplateName returns correct names" {
    try std.testing.expectEqualStrings("starter", getTemplateName(.starter));
    try std.testing.expectEqualStrings("blank", getTemplateName(.blank));
    try std.testing.expectEqualStrings("node", getTemplateName(.node));
    try std.testing.expectEqualStrings("go", getTemplateName(.go));
    try std.testing.expectEqualStrings("rust", getTemplateName(.rust));
    try std.testing.expectEqualStrings("python", getTemplateName(.python));
    try std.testing.expectEqualStrings("zig", getTemplateName(.zig_lang));
}

test "templateForProjectType returns correct mappings" {
    try std.testing.expectEqual(Template.node, templateForProjectType(.node));
    try std.testing.expectEqual(Template.rust, templateForProjectType(.rust));
    try std.testing.expectEqual(Template.go, templateForProjectType(.go));
    try std.testing.expectEqual(Template.python, templateForProjectType(.python));
    try std.testing.expectEqual(Template.zig_lang, templateForProjectType(.zig_lang));
    try std.testing.expectEqual(Template.starter, templateForProjectType(.unknown));
}

test "Options has correct defaults" {
    const opts = Options{};
    try std.testing.expectEqual(@as(?Template, null), opts.template);
    try std.testing.expectEqual(false, opts.force);
    try std.testing.expectEqual(@as(?[]const u8, null), opts.path);
    try std.testing.expectEqual(false, opts.yes);
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
    var buf: [8192]u8 = undefined;
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
    try std.testing.expect(std.mem.indexOf(u8, output, "--yes") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "TEMPLATES:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "starter") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "blank") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "node") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "rust") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "python") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "AUTO-DETECTION:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "EXAMPLES:") != null);
}

test "detectProjectType detects Node.js project" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "package.json", .data = "{}" });
    try std.testing.expectEqual(ProjectType.node, detectProjectType(tmp_dir.dir));
}

test "detectProjectType detects Rust project" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "Cargo.toml", .data = "" });
    try std.testing.expectEqual(ProjectType.rust, detectProjectType(tmp_dir.dir));
}

test "detectProjectType detects Go project" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "go.mod", .data = "" });
    try std.testing.expectEqual(ProjectType.go, detectProjectType(tmp_dir.dir));
}

test "detectProjectType detects Python project with pyproject.toml" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "pyproject.toml", .data = "" });
    try std.testing.expectEqual(ProjectType.python, detectProjectType(tmp_dir.dir));
}

test "detectProjectType detects Python project with requirements.txt" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "requirements.txt", .data = "" });
    try std.testing.expectEqual(ProjectType.python, detectProjectType(tmp_dir.dir));
}

test "detectProjectType detects Zig project" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "build.zig", .data = "" });
    try std.testing.expectEqual(ProjectType.zig_lang, detectProjectType(tmp_dir.dir));
}

test "detectProjectType returns unknown for empty directory" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try std.testing.expectEqual(ProjectType.unknown, detectProjectType(tmp_dir.dir));
}

test "run auto-detects Node.js project" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "package.json", .data = "{}" });

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try runInDir(std.testing.allocator, .{}, stream.writer(), tmp_dir.dir);

    const content = try tmp_dir.dir.readFileAlloc(std.testing.allocator, "Jakefile", 1024 * 1024);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "npm") != null);

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Detected Node.js project") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "'node' template") != null);
}

test "run uses starter template for unknown project type" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try runInDir(std.testing.allocator, .{}, stream.writer(), tmp_dir.dir);

    const content = try tmp_dir.dir.readFileAlloc(std.testing.allocator, "Jakefile", 1024 * 1024);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "task build:") != null);

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Detected") == null);
}
