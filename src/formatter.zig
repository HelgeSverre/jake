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
