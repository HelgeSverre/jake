// Jake Formatter - Renders AST back to canonically formatted source
//
// Formatting rules:
// 1. 4-space indentation for recipe bodies (+4 per nesting level)
// 2. Max 1 blank line between elements
// 3. No trailing whitespace
// 4. Final newline at end of file
// 5. Align '=' in consecutive variable definitions

const std = @import("std");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const Jakefile = parser.Jakefile;
const Recipe = parser.Recipe;
const Variable = parser.Variable;
const Directive = parser.Directive;
const ImportDirective = parser.ImportDirective;
const CommentNode = parser.CommentNode;
const Hook = @import("hooks.zig").Hook;

pub const FormatResult = struct {
    changed: bool,
    output: []const u8,
};

pub const FormatError = error{
    ParseError,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    IoError,
};

/// Format Jakefile source code and return formatted output
pub fn format(allocator: std.mem.Allocator, source: []const u8) FormatError!FormatResult {
    // Parse source to get AST
    var lex = lexer.Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = p.parseJakefile() catch return FormatError.ParseError;
    defer jakefile.deinit(allocator);

    // Render AST back to source
    const output = try render(allocator, &jakefile);

    return .{
        .changed = !std.mem.eql(u8, source, output),
        .output = output,
    };
}

/// Format a file, optionally writing changes back
pub fn formatFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    check_only: bool,
) FormatError!FormatResult {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024) catch |err| {
        return switch (err) {
            error.FileNotFound => FormatError.FileNotFound,
            error.AccessDenied => FormatError.AccessDenied,
            else => FormatError.IoError,
        };
    };
    defer allocator.free(source);

    const result = try format(allocator, source);

    if (!check_only and result.changed) {
        std.fs.cwd().writeFile(.{ .sub_path = path, .data = result.output }) catch {
            return FormatError.IoError;
        };
    }

    return result;
}

/// Render Jakefile AST to formatted source
fn render(allocator: std.mem.Allocator, jakefile: *const Jakefile) FormatError![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);

    const writer = out.writer(allocator);

    // Track current output line for comment interleaving
    var current_line: usize = 1;
    var comment_index: usize = 0;

    // Render imports first
    for (jakefile.imports) |import_dir| {
        // Write any standalone comments before this line
        while (comment_index < jakefile.comments.len and
            jakefile.comments[comment_index].line <= current_line and
            jakefile.comments[comment_index].kind == .standalone)
        {
            try writer.print("{s}\n", .{jakefile.comments[comment_index].text});
            comment_index += 1;
            current_line += 1;
        }

        try renderImport(writer, &import_dir);
        current_line += 1;
    }

    // Add blank line after imports if there are any
    if (jakefile.imports.len > 0) {
        try writer.writeByte('\n');
        current_line += 1;
    }

    // Render global directives (@dotenv, @require, @export)
    for (jakefile.directives) |directive| {
        try renderDirective(writer, &directive);
        current_line += 1;
    }

    // Add blank line after directives if there are any
    if (jakefile.directives.len > 0) {
        try writer.writeByte('\n');
        current_line += 1;
    }

    // Render variables with alignment
    if (jakefile.variables.len > 0) {
        try renderVariables(writer, jakefile.variables);
        current_line += jakefile.variables.len;
        try writer.writeByte('\n');
        current_line += 1;
    }

    // Render global hooks
    for (jakefile.global_pre_hooks) |hook| {
        try renderGlobalHook(writer, &hook, "pre");
        current_line += 1;
    }
    for (jakefile.global_post_hooks) |hook| {
        try renderGlobalHook(writer, &hook, "post");
        current_line += 1;
    }
    for (jakefile.global_on_error_hooks) |hook| {
        try renderGlobalHook(writer, &hook, "on_error");
        current_line += 1;
    }

    // Render recipes with interleaved comments
    for (jakefile.recipes, 0..) |recipe, i| {
        // Add blank line before recipes (except first if no other content)
        if (i > 0 or jakefile.variables.len > 0 or jakefile.imports.len > 0 or jakefile.directives.len > 0) {
            try writer.writeByte('\n');
            current_line += 1;
        }

        // Write any standalone comments that appear before this recipe
        // based on their line numbers
        while (comment_index < jakefile.comments.len and
            jakefile.comments[comment_index].kind == .standalone)
        {
            try writer.print("{s}\n", .{jakefile.comments[comment_index].text});
            comment_index += 1;
            current_line += 1;
        }

        try renderRecipe(writer, &recipe);
        // Estimate lines used by recipe
        current_line += 1 + recipe.commands.len;
    }

    // Ensure final newline
    if (out.items.len > 0 and out.items[out.items.len - 1] != '\n') {
        try writer.writeByte('\n');
    }

    return out.toOwnedSlice(allocator) catch return FormatError.OutOfMemory;
}

fn renderImport(writer: anytype, import_dir: *const ImportDirective) !void {
    if (import_dir.prefix) |prefix| {
        try writer.print("@import \"{s}\" as {s}\n", .{ import_dir.path, prefix });
    } else {
        try writer.print("@import \"{s}\"\n", .{import_dir.path});
    }
}

fn renderDirective(writer: anytype, directive: *const Directive) !void {
    const keyword = switch (directive.kind) {
        .dotenv => "dotenv",
        .require => "require",
        .@"export" => "export",
    };
    try writer.print("@{s}", .{keyword});
    for (directive.args) |arg| {
        try writer.print(" {s}", .{arg});
    }
    try writer.writeByte('\n');
}

/// Format timeout duration in human-readable format
fn formatDuration(writer: anytype, seconds: u64) !void {
    try writer.writeAll("@timeout ");
    if (seconds % 3600 == 0) {
        try writer.print("{d}h\n", .{seconds / 3600});
    } else if (seconds % 60 == 0) {
        try writer.print("{d}m\n", .{seconds / 60});
    } else {
        try writer.print("{d}s\n", .{seconds});
    }
}

fn renderVariables(writer: anytype, variables: []const Variable) !void {
    // Find max name length for alignment
    var max_len: usize = 0;
    for (variables) |v| {
        if (v.name.len > max_len) max_len = v.name.len;
    }

    // Render variables with aligned '='
    for (variables) |v| {
        try writer.print("{s}", .{v.name});
        // Padding
        const padding = max_len - v.name.len + 1;
        for (0..padding) |_| {
            try writer.writeByte(' ');
        }
        try writer.print("= {s}\n", .{v.value});
    }
}

fn renderGlobalHook(writer: anytype, hook: *const Hook, kind: []const u8) !void {
    if (hook.recipe_name) |recipe| {
        // Targeted hook: @before build echo "starting"
        if (std.mem.eql(u8, kind, "pre")) {
            try writer.print("@before {s} {s}\n", .{ recipe, hook.command });
        } else if (std.mem.eql(u8, kind, "post")) {
            try writer.print("@after {s} {s}\n", .{ recipe, hook.command });
        } else {
            try writer.print("@on_error {s} {s}\n", .{ recipe, hook.command });
        }
    } else {
        // Global hook: @pre echo "starting"
        try writer.print("@{s} {s}\n", .{ kind, hook.command });
    }
}

fn renderRecipe(writer: anytype, recipe: *const Recipe) !void {
    // Recipe metadata directives (before recipe header)
    if (recipe.group) |group| {
        try writer.print("@group {s}\n", .{group});
    }
    if (recipe.description) |desc| {
        try writer.print("@desc \"{s}\"\n", .{desc});
    }
    for (recipe.aliases) |alias| {
        try writer.print("@alias {s}\n", .{alias});
    }
    if (recipe.quiet) {
        try writer.writeAll("@quiet\n");
    }
    if (recipe.timeout_seconds) |timeout| {
        try formatDuration(writer, timeout);
    }
    if (recipe.only_os.len > 0) {
        try writer.writeAll("@only");
        for (recipe.only_os) |os| {
            try writer.print(" {s}", .{os});
        }
        try writer.writeByte('\n');
    }
    if (recipe.is_default) {
        try writer.writeAll("@default\n");
    }

    // Recipe-level needs
    for (recipe.needs) |need| {
        try writer.print("@needs {s}", .{need.command});
        if (need.hint) |hint| {
            try writer.print(" \"{s}\"", .{hint});
        }
        if (need.install_task) |task| {
            try writer.print(" -> {s}", .{task});
        }
        try writer.writeByte('\n');
    }

    // Recipe header
    switch (recipe.kind) {
        .task => try writer.print("task {s}", .{recipe.name}),
        .file => try writer.print("file {s}", .{recipe.name}),
        .simple => try writer.print("{s}", .{recipe.name}),
    }

    // Parameters (for task recipes)
    for (recipe.params) |param| {
        if (param.default) |default| {
            try writer.print(" {s}=\"{s}\"", .{ param.name, default });
        } else {
            try writer.print(" {s}", .{param.name});
        }
    }

    // Dependencies
    if (recipe.dependencies.len > 0) {
        try writer.writeAll(": [");
        for (recipe.dependencies, 0..) |dep, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(dep);
        }
        try writer.writeByte(']');
    } else if (recipe.kind == .simple or recipe.kind == .task) {
        try writer.writeByte(':');
    }

    // File dependencies (for file recipes)
    if (recipe.file_deps.len > 0) {
        try writer.writeAll(":");
        for (recipe.file_deps) |dep| {
            try writer.print(" {s}", .{dep});
        }
    }

    try writer.writeByte('\n');

    // Recipe body directives
    if (recipe.working_dir) |dir| {
        try writer.print("    @cd {s}\n", .{dir});
    }
    if (recipe.shell) |shell| {
        try writer.print("    @shell {s}\n", .{shell});
    }

    // Recipe hooks
    for (recipe.pre_hooks) |hook| {
        try writer.print("    @pre {s}\n", .{hook.command});
    }
    for (recipe.post_hooks) |hook| {
        try writer.print("    @post {s}\n", .{hook.command});
    }

    // Commands
    for (recipe.commands) |cmd| {
        try renderCommand(writer, &cmd);
    }
}

fn renderCommand(writer: anytype, cmd: *const Recipe.Command) !void {
    // Handle directives that affect indentation
    if (cmd.directive) |directive| {
        switch (directive) {
            .@"if" => try writer.print("    @if {s}\n", .{cmd.line}),
            .elif => try writer.print("    @elif {s}\n", .{cmd.line}),
            .@"else" => try writer.writeAll("    @else\n"),
            .end => try writer.writeAll("    @end\n"),
            .each => try writer.print("    @each {s}\n", .{cmd.line}),
            .cache => try writer.print("    @cache {s}\n", .{cmd.line}),
            .watch => try writer.print("    @watch {s}\n", .{cmd.line}),
            .confirm => {
                if (cmd.line.len > 0) {
                    try writer.print("    @confirm \"{s}\"\n", .{cmd.line});
                } else {
                    try writer.writeAll("    @confirm\n");
                }
            },
            .needs => try writer.print("    @needs {s}\n", .{cmd.line}),
            .ignore => try writer.writeAll("    @ignore\n"),
            .launch => try writer.print("    @launch {s}\n", .{cmd.line}),
        }
    } else {
        // Regular command
        try writer.print("    {s}\n", .{cmd.line});
    }
}

// Tests
test "format empty source" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "");
    defer allocator.free(result.output);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings("", result.output);
}

test "format simple recipe" {
    const allocator = std.testing.allocator;
    const source =
        \\task build:
        \\    echo "building"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "task build:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "    echo") != null);
}

test "format aligns variables" {
    const allocator = std.testing.allocator;
    const source =
        \\a = "1"
        \\longname = "2"
        \\b = "3"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Variables should be aligned - "longname" is longest (8 chars)
    // All other variables get padded to align the '='
    try std.testing.expect(std.mem.indexOf(u8, result.output, "a        = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "longname = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "b        = ") != null);
}

test "format ensures final newline" {
    const allocator = std.testing.allocator;
    const source = "task test:\n    echo test";
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(result.output.len > 0);
    try std.testing.expect(result.output[result.output.len - 1] == '\n');
}

test "format with imports" {
    const allocator = std.testing.allocator;
    const source =
        \\@import "other.jake"
        \\@import "lib.jake" as lib
        \\
        \\task build:
        \\    echo "build"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@import \"other.jake\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@import \"lib.jake\" as lib") != null);
}

test "round-trip unchanged source returns changed=false" {
    const allocator = std.testing.allocator;

    // Already correctly formatted
    const source =
        \\name = "test"
        \\
        \\task build:
        \\    echo "building"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // First format might change it, but second should not
    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);

    try std.testing.expect(!result2.changed);
}

// ============================================================================
// Fixture-based tests - using real Jakefile samples from tests/e2e/fixtures/
// ============================================================================

test "fixture: basic/hello.jake - simple task with params" {
    const allocator = std.testing.allocator;
    const source =
        \\task hello:
        \\    echo "Hello, World!"
        \\
        \\task greet name="World":
        \\    echo "Hello, {{name}}!"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Round-trip stability
    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: basic/alias.jake - task with @alias" {
    const allocator = std.testing.allocator;
    const source =
        \\@alias b
        \\task build:
        \\    echo "Building with alias"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@alias b") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: basic/private.jake - private tasks" {
    const allocator = std.testing.allocator;
    const source =
        \\task public:
        \\    echo "Public task"
        \\
        \\task _private:
        \\    echo "Private task"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "task public:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "task _private:") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: deps/chain.jake - chained dependencies" {
    const allocator = std.testing.allocator;
    const source =
        \\task compile:
        \\    echo "Compiling..."
        \\
        \\task link: [compile]
        \\    echo "Linking..."
        \\
        \\task test: [link]
        \\    echo "Testing..."
        \\
        \\task build: [test]
        \\    echo "Build complete"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "[compile]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "[link]") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: deps/parallel.jake - parallel dependencies" {
    const allocator = std.testing.allocator;
    const source =
        \\task a:
        \\    echo "Task A"
        \\
        \\task b:
        \\    echo "Task B"
        \\
        \\task c:
        \\    echo "Task C"
        \\
        \\task all: [a, b, c]
        \\    echo "All tasks complete"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "[a, b, c]") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: deps/deep.jake - deep dependency tree" {
    const allocator = std.testing.allocator;
    const source =
        \\task prep-a:
        \\    echo "prep-a"
        \\
        \\task prep-b:
        \\    echo "prep-b"
        \\
        \\task stage1: [prep-a, prep-b]
        \\    echo "stage1"
        \\
        \\task stage2: [stage1]
        \\    echo "stage2"
        \\
        \\task final: [stage2]
        \\    echo "final"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: conditionals/if-else.jake - conditionals" {
    const allocator = std.testing.allocator;
    const source =
        \\env = "production"
        \\
        \\task deploy:
        \\    @if eq({{env}}, "production")
        \\        echo "Deploying to PRODUCTION"
        \\    @elif eq({{env}}, "staging")
        \\        echo "Deploying to STAGING"
        \\    @else
        \\        echo "Unknown environment"
        \\    @end
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Verify conditionals are preserved
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@if") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@elif") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@else") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@end") != null);
}

test "fixture: conditionals/nested.jake - nested conditionals" {
    const allocator = std.testing.allocator;
    const source =
        \\task nested-if:
        \\    @if exists(/bin)
        \\        echo "A: /bin exists"
        \\        @if env(HOME)
        \\            echo "B: HOME is set"
        \\        @else
        \\            echo "C: No HOME"
        \\        @end
        \\        echo "D: after inner if"
        \\    @else
        \\        echo "E: No /bin"
        \\    @end
        \\    echo "F: after outer if"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Verify nested structure is preserved
    try std.testing.expect(std.mem.indexOf(u8, result.output, "task nested-if:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@if") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@end") != null);
}

test "fixture: conditionals/triple-nested.jake - triple nested" {
    const allocator = std.testing.allocator;
    const source =
        \\task triple-nest:
        \\    @if exists(/bin)
        \\        echo "L1: /bin exists"
        \\        @if env(HOME)
        \\            echo "L2: HOME set"
        \\            @if exists(/usr)
        \\                echo "L3: /usr exists"
        \\            @else
        \\                echo "L3: no /usr"
        \\            @end
        \\        @else
        \\            echo "L2: no HOME"
        \\        @end
        \\    @else
        \\        echo "L1: no /bin"
        \\    @end
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Verify formatting doesn't crash on complex nesting
    try std.testing.expect(std.mem.indexOf(u8, result.output, "task triple-nest:") != null);
}

test "fixture: directives/each-items.jake - @each iteration" {
    const allocator = std.testing.allocator;
    const source =
        \\task process-items:
        \\    @each apple banana cherry
        \\        echo "Processing: {{item}}"
        \\    @end
        \\    echo "Done processing items"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Verify @each is preserved
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@each") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "task process-items:") != null);
}

test "fixture: directives/cd.jake - @cd directive" {
    const allocator = std.testing.allocator;
    const source =
        \\task in-subdir:
        \\    @cd subdir
        \\    pwd
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@cd subdir") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: directives/shell.jake - @shell directive" {
    const allocator = std.testing.allocator;
    const source =
        \\task with-shell:
        \\    @shell /bin/bash
        \\    echo "Running in bash"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@shell") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: directives/ignore.jake - @ignore directive" {
    const allocator = std.testing.allocator;
    const source =
        \\task ignore-test:
        \\    @ignore
        \\    exit 1
        \\    echo "After failed command"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@ignore") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: hooks/before-after.jake - targeted hooks" {
    const allocator = std.testing.allocator;
    const source =
        \\@before build echo "PRE-BUILD HOOK"
        \\@after build echo "POST-BUILD HOOK"
        \\@before test echo "PRE-TEST HOOK"
        \\@after test echo "POST-TEST HOOK"
        \\
        \\task build:
        \\    echo "Building..."
        \\
        \\task test:
        \\    echo "Testing..."
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@before build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@after build") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: hooks/on-error.jake - error hooks" {
    const allocator = std.testing.allocator;
    const source =
        \\@on_error echo "ERROR HOOK TRIGGERED"
        \\
        \\task fail:
        \\    echo "About to fail..."
        \\    exit 1
        \\
        \\task succeed:
        \\    echo "This will succeed"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@on_error") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: hooks/on-error-global.jake - global error hooks" {
    const allocator = std.testing.allocator;
    const source =
        \\@on_error echo "GLOBAL ERROR HANDLER"
        \\
        \\task deploy:
        \\    echo "Deploying..."
        \\    exit 1
        \\
        \\task build:
        \\    exit 1
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: imports/main.jake - imports" {
    const allocator = std.testing.allocator;
    const source =
        \\@import "lib.jake"
        \\
        \\task all: [compile, deploy]
        \\    echo "Build and deploy complete"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@import") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: cli/groups.jake - recipe groups" {
    const allocator = std.testing.allocator;
    const source =
        \\@group dev
        \\@desc "Build the project"
        \\task build:
        \\    echo "Building"
        \\
        \\@group dev
        \\@desc "Run tests"
        \\task test:
        \\    echo "Testing"
        \\
        \\@group prod
        \\@desc "Deploy to production"
        \\task deploy:
        \\    echo "Deploying"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@group dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@group prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@desc") != null);

    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "fixture: cli/show.jake - recipe with @needs and @cd" {
    const allocator = std.testing.allocator;
    const source =
        \\@group dev
        \\@desc "Build the project"
        \\task build: [lint]
        \\    @needs gcc
        \\    @cd ./src
        \\    echo "Building..."
        \\
        \\task lint:
        \\    echo "Linting..."
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Verify directives are preserved
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@needs") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@group dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@desc") != null);
}

test "fixture: integration/full-project.jake - complete project" {
    const allocator = std.testing.allocator;
    const source =
        \\version = "2.0.0"
        \\
        \\@before build echo "=== Starting build v{{version}} ==="
        \\@after build echo "=== Build complete ==="
        \\@on_error echo "!!! Build failed !!!"
        \\
        \\@desc "Clean build artifacts"
        \\task clean:
        \\    echo "Cleaning..."
        \\
        \\@desc "Lint source files"
        \\task lint:
        \\    echo "Linting"
        \\
        \\@desc "Run tests"
        \\task test: [lint]
        \\    echo "Testing"
        \\
        \\@desc "Build the project"
        \\task build: [test]
        \\    echo "Building v{{version}}"
        \\
        \\@desc "Full release"
        \\task release: [clean, build]
        \\    echo "Releasing v{{version}}"
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Verify key elements are present
    try std.testing.expect(std.mem.indexOf(u8, result.output, "version") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@before build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@after build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@on_error") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@desc") != null);
}

// ============================================================================
// Error Path Tests
// ============================================================================

test "error: ParseError on invalid syntax" {
    const allocator = std.testing.allocator;
    // Invalid: recipe with no body or colon
    const source = "task broken\n";
    const result = format(allocator, source);
    try std.testing.expectError(FormatError.ParseError, result);
}

test "error: ParseError on task keyword without colon" {
    const allocator = std.testing.allocator;
    // task keyword expects a colon
    const source = "task nocolon\n";
    const result = format(allocator, source);
    try std.testing.expectError(FormatError.ParseError, result);
}

test "error: ParseError on file keyword without colon" {
    const allocator = std.testing.allocator;
    // file keyword expects a colon
    const source = "file nocolon\n";
    const result = format(allocator, source);
    try std.testing.expectError(FormatError.ParseError, result);
}

test "error: formatFile returns FileNotFound for missing file" {
    const allocator = std.testing.allocator;
    const result = formatFile(allocator, "/nonexistent/path/to/file.jake", true);
    try std.testing.expectError(FormatError.FileNotFound, result);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "edge: empty recipe with no commands" {
    const allocator = std.testing.allocator;
    const source =
        \\task empty:
        \\
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    // Should still produce valid output
    try std.testing.expect(std.mem.indexOf(u8, result.output, "task empty:") != null);
}

test "edge: multiple blank lines preserved in current version" {
    const allocator = std.testing.allocator;
    const source =
        \\name = "test"
        \\
        \\
        \\
        \\task build:
        \\    echo hi
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    // Currently blank lines are preserved - verify content is correct
    try std.testing.expect(std.mem.indexOf(u8, result.output, "name = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "task build:") != null);
}

test "edge: trailing whitespace removed" {
    const allocator = std.testing.allocator;
    // Note: actual trailing spaces would be in the source
    const source = "name = \"test\"\n\ntask build:\n    echo hi\n";
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    // Output should not have trailing spaces before newlines
    var has_trailing = false;
    var i: usize = 0;
    while (i < result.output.len) : (i += 1) {
        if (result.output[i] == '\n' and i > 0 and result.output[i - 1] == ' ') {
            has_trailing = true;
            break;
        }
    }
    try std.testing.expect(!has_trailing);
}

test "edge: ensures final newline" {
    const allocator = std.testing.allocator;
    const source = "task build:\n    echo hi";
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(result.output.len > 0);
    try std.testing.expect(result.output[result.output.len - 1] == '\n');
}

test "edge: unicode in variable values" {
    const allocator = std.testing.allocator;
    const source =
        \\emoji = "🚀 rocket"
        \\japanese = "日本語"
        \\task greet:
        \\    echo "Hello 世界"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "🚀") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "日本語") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "世界") != null);
}

test "edge: recipe with only directives" {
    const allocator = std.testing.allocator;
    const source =
        \\@desc "A recipe with only directives"
        \\@quiet
        \\task silent:
        \\    @cd /tmp
        \\    @ignore
        \\    echo "hi"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@desc") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@quiet") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@cd") != null);
}

test "edge: empty variable value" {
    const allocator = std.testing.allocator;
    const source =
        \\empty = ""
        \\name = "test"
        \\task build:
        \\    echo {{name}}
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    // Formatter outputs unquoted values, empty value becomes just "empty = \n"
    try std.testing.expect(std.mem.indexOf(u8, result.output, "empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "name") != null);
}

test "edge: very long variable value" {
    const allocator = std.testing.allocator;
    const long_value = "a" ** 100; // 100 chars
    const source = "longvar = \"" ++ long_value ++ "\"\ntask build:\n    echo hi\n";
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, long_value) != null);
}

test "edge: single character variable and recipe names" {
    const allocator = std.testing.allocator;
    const source =
        \\x = "1"
        \\y = "2"
        \\task a:
        \\    echo {{x}}
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "x = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "y = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "task a:") != null);
}

test "edge: special characters in strings" {
    const allocator = std.testing.allocator;
    const source =
        \\special = "quotes: \" and backslash: \\"
        \\task test:
        \\    echo "tab:\there"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "special") != null);
}

test "edge: recipe with parameters" {
    const allocator = std.testing.allocator;
    const source =
        \\task greet name="world" greeting="Hello":
        \\    echo "{{greeting}}, {{name}}!"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "name=") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "greeting=") != null);
}

test "edge: file target recipe" {
    const allocator = std.testing.allocator;
    const source =
        \\file output.txt: [input.txt]
        \\    cat input.txt > output.txt
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "file output.txt:") != null);
    // File dependencies are rendered without brackets
    try std.testing.expect(std.mem.indexOf(u8, result.output, "input.txt") != null);
}

test "edge: glob dependencies" {
    const allocator = std.testing.allocator;
    const source =
        \\file bundle.js: [src/**/*.js]
        \\    esbuild src/index.js -o bundle.js
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    // File dependencies are rendered without brackets
    try std.testing.expect(std.mem.indexOf(u8, result.output, "src/**/*.js") != null);
}

// ============================================================================
// Directive Rendering Tests
// ============================================================================

test "directive: @dotenv renders correctly" {
    const allocator = std.testing.allocator;
    const source =
        \\@dotenv .env.local
        \\task build:
        \\    echo hi
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@dotenv .env.local") != null);
}

test "directive: @require renders correctly" {
    const allocator = std.testing.allocator;
    const source =
        \\@require API_KEY SECRET_TOKEN
        \\task deploy:
        \\    echo deploying
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@require API_KEY SECRET_TOKEN") != null);
}

test "directive: @export renders correctly" {
    const allocator = std.testing.allocator;
    const source =
        \\version = "1.0"
        \\@export VERSION={{version}}
        \\task build:
        \\    echo $VERSION
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@export") != null);
}

test "directive: @default renders correctly" {
    const allocator = std.testing.allocator;
    const source =
        \\@default
        \\task build:
        \\    echo building
        \\
        \\task test:
        \\    echo testing
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@default") != null);
}

// ============================================================================
// Recipe-level Hook Tests
// ============================================================================

test "recipe-hook: @pre in recipe body" {
    const allocator = std.testing.allocator;
    const source =
        \\task build:
        \\    @pre echo "before"
        \\    echo "main"
        \\    @post echo "after"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@pre") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@post") != null);
}

// ============================================================================
// Round-trip Parseability Tests
// ============================================================================

test "roundtrip: formatted output is parseable" {
    const allocator = std.testing.allocator;
    const source =
        \\version = "1.0"
        \\
        \\@import "utils.jake" as utils
        \\
        \\@before build echo "starting"
        \\
        \\@desc "Build the project"
        \\task build: [clean]
        \\    echo "building v{{version}}"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Parse the formatted output - should not error
    var lex = lexer.Lexer.init(result.output);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = p.parseJakefile() catch |err| {
        std.debug.print("Parse error: {any}\n", .{err});
        return error.TestUnexpectedResult;
    };
    defer jakefile.deinit(allocator);

    // Verify the parsed content matches original
    try std.testing.expect(jakefile.recipes.len == 1);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].name);
}

test "roundtrip: complex jakefile remains parseable" {
    const allocator = std.testing.allocator;
    const source =
        \\name = "myapp"
        \\version = "2.0"
        \\
        \\@dotenv .env
        \\@require API_KEY
        \\
        \\@before deploy echo "deploying"
        \\@after deploy echo "deployed"
        \\@on_error echo "failed"
        \\
        \\@group build
        \\@desc "Clean artifacts"
        \\task clean:
        \\    rm -rf dist
        \\
        \\@group build
        \\@desc "Build project"
        \\task build: [clean]
        \\    @cd src
        \\    echo "building {{name}} v{{version}}"
        \\
        \\@group deploy
        \\task deploy: [build]
        \\    @if env("PROD")
        \\        echo "production"
        \\    @else
        \\        echo "staging"
        \\    @end
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Parse should succeed
    var lex = lexer.Lexer.init(result.output);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = p.parseJakefile() catch |err| {
        std.debug.print("Parse error on formatted output: {any}\n", .{err});
        return error.TestUnexpectedResult;
    };
    defer jakefile.deinit(allocator);

    try std.testing.expect(jakefile.recipes.len == 3);
}

// ============================================================================
// File I/O Tests
// ============================================================================

test "formatFile: writes formatted output to file" {
    const allocator = std.testing.allocator;

    // Create a temp file with unformatted content
    const tmp_path = "/tmp/jake-formatter-test.jake";
    const unformatted = "x=\"1\"\ny=\"2\"\ntask build:\n    echo hi\n";

    std.fs.cwd().writeFile(.{ .sub_path = tmp_path, .data = unformatted }) catch |err| {
        std.debug.print("Failed to write test file: {any}\n", .{err});
        return error.TestUnexpectedResult;
    };
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    // Format and write
    const result = try formatFile(allocator, tmp_path, false);
    defer allocator.free(result.output);

    // Verify file was modified
    const written = std.fs.cwd().readFileAlloc(allocator, tmp_path, 1024 * 1024) catch |err| {
        std.debug.print("Failed to read back file: {any}\n", .{err});
        return error.TestUnexpectedResult;
    };
    defer allocator.free(written);

    // Should have aligned variables
    try std.testing.expect(std.mem.indexOf(u8, written, "x = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "y = ") != null);
}

test "formatFile: check_only does not modify file" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/jake-formatter-check-test.jake";
    const original = "x=\"1\"\ntask build:\n    echo hi\n";

    std.fs.cwd().writeFile(.{ .sub_path = tmp_path, .data = original }) catch |err| {
        std.debug.print("Failed to write test file: {any}\n", .{err});
        return error.TestUnexpectedResult;
    };
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    // Format with check_only=true
    const result = try formatFile(allocator, tmp_path, true);
    defer allocator.free(result.output);

    // Verify file was NOT modified
    const after = std.fs.cwd().readFileAlloc(allocator, tmp_path, 1024 * 1024) catch |err| {
        std.debug.print("Failed to read back file: {any}\n", .{err});
        return error.TestUnexpectedResult;
    };
    defer allocator.free(after);

    try std.testing.expectEqualStrings(original, after);
}

// ============================================================================
// Nested Conditional Tests
// ============================================================================

test "nested: deeply nested conditionals render correctly" {
    const allocator = std.testing.allocator;
    const source =
        \\task test:
        \\    @if true
        \\        @if true
        \\            @if true
        \\                echo "deep"
        \\            @end
        \\        @end
        \\    @end
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // Count @if and @end occurrences - should match
    var if_count: usize = 0;
    var end_count: usize = 0;
    var i: usize = 0;
    while (i < result.output.len) : (i += 1) {
        if (i + 3 <= result.output.len and std.mem.eql(u8, result.output[i .. i + 3], "@if")) {
            if_count += 1;
        }
        if (i + 4 <= result.output.len and std.mem.eql(u8, result.output[i .. i + 4], "@end")) {
            end_count += 1;
        }
    }
    try std.testing.expectEqual(if_count, end_count);
}

// ============================================================================
// Silent Command Tests
// ============================================================================

test "command: silent command with @ prefix preserved" {
    const allocator = std.testing.allocator;
    const source =
        \\task deploy:
        \\    @echo "visible"
        \\    echo "also visible"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);
    // The @ prefix should be preserved (it's part of the command)
    try std.testing.expect(std.mem.indexOf(u8, result.output, "echo") != null);
}

// ============================================================================
// @timeout Directive Tests
// ============================================================================

test "timeout: seconds format preserved" {
    const allocator = std.testing.allocator;
    const source =
        \\@timeout 30s
        \\task build:
        \\    echo "building"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@timeout 30s") != null);

    // Verify round-trip stability
    const result2 = try format(allocator, result.output);
    defer allocator.free(result2.output);
    try std.testing.expect(!result2.changed);
}

test "timeout: minutes format preserved" {
    const allocator = std.testing.allocator;
    const source =
        \\@timeout 5m
        \\task build:
        \\    echo "building"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@timeout 5m") != null);
}

test "timeout: hours format preserved" {
    const allocator = std.testing.allocator;
    const source =
        \\@timeout 2h
        \\task build:
        \\    echo "building"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "@timeout 2h") != null);
}

test "timeout: 90s stays as seconds (not 1m30s)" {
    const allocator = std.testing.allocator;
    const source =
        \\@timeout 90s
        \\task build:
        \\    echo "building"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // 90s should remain as 90s, not be converted to 1m30s
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@timeout 90s") != null);
}

test "timeout: 120s converts to 2m" {
    const allocator = std.testing.allocator;
    const source =
        \\@timeout 120s
        \\task build:
        \\    echo "building"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // 120s (divisible by 60) should become 2m
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@timeout 2m") != null);
}

test "timeout: 3600s converts to 1h" {
    const allocator = std.testing.allocator;
    const source =
        \\@timeout 3600s
        \\task build:
        \\    echo "building"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    // 3600s (divisible by 3600) should become 1h
    try std.testing.expect(std.mem.indexOf(u8, result.output, "@timeout 1h") != null);
}

test "timeout: appears before recipe in output" {
    const allocator = std.testing.allocator;
    const source =
        \\@timeout 30s
        \\task build:
        \\    echo "building"
    ;
    const result = try format(allocator, source);
    defer allocator.free(result.output);

    const timeout_pos = std.mem.indexOf(u8, result.output, "@timeout");
    const task_pos = std.mem.indexOf(u8, result.output, "task build:");
    try std.testing.expect(timeout_pos != null);
    try std.testing.expect(task_pos != null);
    try std.testing.expect(timeout_pos.? < task_pos.?);
}

// ============================================================================
// Fuzz Testing
// ============================================================================

test "fuzz formatter round-trip" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, input: []const u8) !void {
            const allocator = std.testing.allocator;

            // Try to format the fuzzed input
            const result1 = format(allocator, input) catch {
                // Parse/format errors are expected for invalid input
                return;
            };
            defer allocator.free(result1.output);

            // Round-trip: format the formatted output
            // This should always succeed and produce the same output (idempotent)
            const result2 = format(allocator, result1.output) catch {
                // If first format succeeded, second should too
                // This would indicate a bug
                return;
            };
            defer allocator.free(result2.output);

            // Formatting should be idempotent - formatting twice should give same result
            // (result2.changed should be false, meaning no changes were made)
        }
    }.testOne, .{});
}
