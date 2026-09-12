//! Forward termination signals to spawned children before jake exits.
//!
//! Without this, Ctrl-C orphans process trees: jake installs no handler, dies
//! on the default disposition, and never touches its children. The terminal's
//! own group-wide SIGINT papers over it for plain recipes, but children that
//! jake deliberately puts in their own process group (`@timeout`, `--web`,
//! anything with a cancellation flag set `child.pgid = 0`) never see it and
//! keep running, reparented to init.

const std = @import("std");
const builtin = @import("builtin");

const enabled = builtin.os.tag != .windows and builtin.os.tag != .wasi;

/// Live child PIDs. Fixed-size so the signal handler only touches atomics —
/// allocation and locks are not async-signal-safe.
/// ponytail: 64 slots covers `-j` up to any sane core count; children past the
/// limit simply are not tracked (same behaviour as before this module existed).
var tracked: [64]std.atomic.Value(i32) = @splat(std.atomic.Value(i32).init(0));

/// Record a freshly spawned child so a signal can reach it.
pub fn track(pid: i32) void {
    if (!enabled or pid <= 0) return;
    for (&tracked) |*slot| {
        if (slot.cmpxchgStrong(0, pid, .acq_rel, .acquire) == null) return;
    }
}

/// Drop a child that has been reaped.
pub fn untrack(pid: i32) void {
    if (!enabled or pid <= 0) return;
    for (&tracked) |*slot| {
        if (slot.cmpxchgStrong(pid, 0, .acq_rel, .acquire) == null) return;
    }
}

/// Forward `sig` to every live child. Targets the child's process group first
/// (negative pid) so shell wrappers take their own children down with them,
/// then the child itself in case it never became a group leader.
fn forward(sig: u8) void {
    for (&tracked) |*slot| {
        const pid = slot.load(.acquire);
        if (pid <= 0) continue;
        std.posix.kill(-pid, sig) catch {};
        std.posix.kill(pid, sig) catch {};
    }
}

fn handler(sig: i32) callconv(.c) void {
    const signo: u8 = @intCast(sig);
    forward(signo);

    // Restore the default disposition and re-raise, so jake's own exit status
    // reports the signal the way every other well-behaved program does.
    const restore = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(signo, &restore, null);
    std.posix.raise(signo) catch {};
}

/// Install handlers for the signals that mean "stop now". Safe to call twice.
pub fn install() void {
    if (!enabled) return;
    const act = std.posix.Sigaction{
        .handler = .{ .handler = handler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    for ([_]u8{ std.posix.SIG.INT, std.posix.SIG.TERM, std.posix.SIG.HUP }) |sig| {
        std.posix.sigaction(sig, &act, null);
    }
}

test "track and untrack reuse slots" {
    if (!enabled) return error.SkipZigTest;
    for (&tracked) |*slot| slot.store(0, .release);

    track(111);
    track(222);
    try std.testing.expectEqual(@as(i32, 111), tracked[0].load(.acquire));
    try std.testing.expectEqual(@as(i32, 222), tracked[1].load(.acquire));

    untrack(111);
    try std.testing.expectEqual(@as(i32, 0), tracked[0].load(.acquire));

    track(333);
    try std.testing.expectEqual(@as(i32, 333), tracked[0].load(.acquire));

    // Invalid pids are ignored rather than occupying a slot.
    track(0);
    track(-5);
    try std.testing.expectEqual(@as(i32, 0), tracked[2].load(.acquire));

    for (&tracked) |*slot| slot.store(0, .release);
}

test "track is a no-op once every slot is full" {
    if (!enabled) return error.SkipZigTest;
    for (&tracked, 0..) |*slot, i| slot.store(@intCast(i + 1), .release);

    track(9999); // must not overwrite an existing entry
    for (&tracked, 0..) |*slot, i| {
        try std.testing.expectEqual(@as(i32, @intCast(i + 1)), slot.load(.acquire));
    }

    for (&tracked) |*slot| slot.store(0, .release);
}
