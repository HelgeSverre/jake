// Test piping output and polling to detect when to pause spinner
// This simulates what we'd need to do in executor.zig

const std = @import("std");

const SPINNER_FRAMES = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
const ROSE = "\x1b[38;2;232;121;153m";
const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const GRAY = "\x1b[90m";

pub fn main() !void {
    const stderr = std.io.getStdErr().writer();
    const allocator = std.heap.page_allocator;

    // Spawn a test command that produces output
    var child = std.process.Child.init(
        &[_][]const u8{ "/bin/sh", "-c",
            "echo 'Running tests...'; sleep 0.3; echo 'Test 1: passed'; sleep 0.2; echo 'Test 2: passed'; sleep 0.2; echo 'All tests passed!'"
        },
        allocator,
    );

    // Use pipes instead of inherit
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    _ = try child.spawn();

    var spinner_frame: usize = 0;
    var spinner_visible = true;
    var buffer: [4096]u8 = undefined;

    const start_time = std.time.nanoTimestamp();

    // Poll loop
    while (true) {
        // Check if child has output ready (non-blocking)
        const stdout_ready = child.stdout.?.poll();
        const stderr_ready = child.stderr.?.poll();

        const has_stdout = stdout_ready.ready_count > 0;
        const has_stderr = stderr_ready.ready_count > 0;

        if (has_stdout or has_stderr) {
            // Output detected - pause spinner first
            if (spinner_visible) {
                try stderr.writeAll("\r\x1b[K"); // Clear spinner line
                spinner_visible = false;
            }

            // Print the output
            if (has_stdout) {
                const n = try child.stdout.?.read(&buffer);
                if (n > 0) {
                    try stderr.writeAll(buffer[0..n]);
                }
            }
            if (has_stderr) {
                const n = try child.stderr.?.read(&buffer);
                if (n > 0) {
                    try stderr.writeAll(buffer[0..n]);
                }
            }
        } else {
            // No output - show spinner
            if (!spinner_visible) {
                spinner_visible = true;
            }

            try stderr.print("\r   {s}{s}{s} test\x1b[K", .{
                ROSE,
                SPINNER_FRAMES[spinner_frame % SPINNER_FRAMES.len],
                RESET
            });
            spinner_frame += 1;
        }

        // Check if process has exited
        const term = child.wait() catch break;
        if (term == .Exited or term == .Signal) {
            break;
        }

        std.time.sleep(50 * std.time.ns_per_ms);
    }

    // Clean up
    if (spinner_visible) {
        try stderr.writeAll("\r\x1b[K");
    }

    const end_time = std.time.nanoTimestamp();
    const duration_s = @as(f64, @floatFromInt(@divFloor(end_time - start_time, 1_000_000))) / 1000.0;

    // Final status
    try stderr.print("\n   {s}✓{s} test     {s}{d:.2}s{s}\n", .{ GREEN, RESET, GRAY, duration_s, RESET });
}
