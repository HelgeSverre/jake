// Test: Spinner with pipe polling to detect output
// This shows how to keep spinner running until output is detected

const std = @import("std");
const posix = std.posix;

fn getStdErr() std.fs.File {
    if (@hasDecl(std.fs.File, "stderr")) {
        return std.fs.File.stderr();
    } else {
        return std.io.getStdErr();
    }
}

const SPINNER_FRAMES = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
const ROSE = "\x1b[38;2;232;121;153m";
const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const GRAY = "\x1b[90m";

const SpinnerState = struct {
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    paused: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    needs_clear: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

fn spinnerLoop(state: *SpinnerState, name: []const u8) void {
    const stderr = getStdErr();
    var frame_idx: usize = 0;

    while (!state.done.load(.seq_cst)) {
        if (!state.paused.load(.seq_cst)) {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "\r   {s}{s}{s} {s}\x1b[K", .{
                ROSE,
                SPINNER_FRAMES[frame_idx % SPINNER_FRAMES.len],
                RESET,
                name,
            }) catch continue;
            stderr.writeAll(msg) catch {};
            state.needs_clear.store(true, .seq_cst);
            frame_idx +%= 1;
        }
        std.Thread.sleep(80 * std.time.ns_per_ms);
    }
}

pub fn main() !void {
    const stderr = getStdErr();
    const allocator = std.heap.page_allocator;

    try stderr.writeAll("===== PIPE+POLL SPINNER TEST =====\n\n");

    // Spawn test command
    var child = std.process.Child.init(
        &[_][]const u8{
            "/bin/sh", "-c",
            "sleep 0.3; echo 'Running tests...'; sleep 0.2; echo 'Test 1: passed'; sleep 0.2; echo 'Test 2: passed'; sleep 0.2; echo 'All tests passed!'",
        },
        allocator,
    );

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    _ = try child.spawn();

    // Start spinner
    var state = SpinnerState{};
    const spinner_thread = try std.Thread.spawn(.{}, spinnerLoop, .{ &state, "test" });

    const start_time = std.time.nanoTimestamp();

    // Get file descriptors for polling
    const stdout_fd = child.stdout.?.handle;
    const stderr_fd = child.stderr.?.handle;

    var poll_fds = [_]posix.pollfd{
        .{ .fd = stdout_fd, .events = posix.POLL.IN, .revents = 0 },
        .{ .fd = stderr_fd, .events = posix.POLL.IN, .revents = 0 },
    };

    var buffer: [4096]u8 = undefined;
    var child_done = false;

    while (!child_done) {
        // Poll with 50ms timeout
        const ready = posix.poll(&poll_fds, 50) catch 0;

        if (ready > 0) {
            // Data available - pause spinner and clear line first
            if (!state.paused.load(.seq_cst)) {
                state.paused.store(true, .seq_cst);
                // Wait a tiny bit for spinner to stop, then clear
                std.Thread.sleep(5 * std.time.ns_per_ms);
                if (state.needs_clear.load(.seq_cst)) {
                    try stderr.writeAll("\r\x1b[K");
                    state.needs_clear.store(false, .seq_cst);
                }
            }

            // Read and print available data
            if (poll_fds[0].revents & posix.POLL.IN != 0) {
                const n = child.stdout.?.read(&buffer) catch 0;
                if (n > 0) {
                    try stderr.writeAll(buffer[0..n]);
                }
            }
            if (poll_fds[1].revents & posix.POLL.IN != 0) {
                const n = child.stderr.?.read(&buffer) catch 0;
                if (n > 0) {
                    try stderr.writeAll(buffer[0..n]);
                }
            }

            // Check for hangup/error (EOF)
            if ((poll_fds[0].revents & posix.POLL.HUP != 0) and
                (poll_fds[1].revents & posix.POLL.HUP != 0))
            {
                child_done = true;
            }
        }
    }

    // Wait for child to fully exit
    _ = child.wait() catch {};

    // Stop spinner
    state.done.store(true, .seq_cst);
    spinner_thread.join();

    // Clear any spinner remnants
    if (state.needs_clear.load(.seq_cst)) {
        try stderr.writeAll("\r\x1b[K");
    }

    const end_time = std.time.nanoTimestamp();
    const duration_s = @as(f64, @floatFromInt(@divFloor(end_time - start_time, 1_000_000))) / 1000.0;

    // Final status
    var result_buf: [256]u8 = undefined;
    const result_msg = try std.fmt.bufPrint(&result_buf, "\n   {s}✓{s} test     {s}{d:.2}s{s}\n", .{ GREEN, RESET, GRAY, duration_s, RESET });
    try stderr.writeAll(result_msg);
    try stderr.writeAll("\n===== END TEST =====\n");
}
