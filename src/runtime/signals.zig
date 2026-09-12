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

/// Set to the received signal number once a handler has begun forwarding.
/// A child spawned after `forward()` already scanned past its slot would
/// otherwise be missed entirely, so `track` consults this and kills its own
/// child instead of relying on a scan that has already gone by.
var terminating: std.atomic.Value(u8) = .init(0);

/// Slot index meaning "not tracked"; passing it to `untrack` is a no-op.
pub const no_slot: usize = std.math.maxInt(usize);

/// Record a freshly spawned child so a signal can reach it. Returns a handle
/// to hand back to `untrack`, or `no_slot` if the child was not tracked.
///
/// The handle is a slot index, not a pid: a pid is recycled the moment it is
/// reaped, so clearing by value can wipe another thread's live child that the
/// kernel handed the same number.
pub fn track(pid: i32) usize {
    if (!enabled or pid <= 0) return no_slot;
    for (&tracked, 0..) |*slot, i| {
        if (slot.cmpxchgStrong(0, pid, .acq_rel, .acquire) == null) {
            // A handler may have run between spawn and here, or scanned past
            // this slot while it was still empty. Either way the signal never
            // reached this child, so deliver it now.
            const sig = terminating.load(.acquire);
            if (sig != 0) {
                kill(pid, sig);
                slot.store(0, .release);
                return no_slot;
            }
            return i;
        }
    }
    return no_slot;
}

/// Drop a child that has been reaped, by the handle `track` returned, and
/// disarm the handle.
///
/// The handle is consumed rather than copied so a second call cannot clear the
/// slot again: slots are reused, so a stale repeat would wipe whichever child
/// landed there next. Callers therefore pair an eager `untrack` at the reap
/// with a `defer` for the early-return paths, and only one of them does work.
pub fn untrack(handle: *usize) void {
    const slot = handle.*;
    if (!enabled or slot >= tracked.len) return;
    handle.* = no_slot;
    tracked[slot].store(0, .release);
}

/// Signal one child: its process group first (negative pid) so shell wrappers
/// take their own children down with them, then the child itself in case it
/// never became a group leader.
///
/// pid 1 is rejected because `kill(-1, ...)` means "every process we may
/// signal" — a stray 1 in the table would take down the user's session.
fn kill(pid: i32, sig: u8) void {
    if (pid <= 1) return;
    std.posix.kill(-pid, sig) catch {};
    std.posix.kill(pid, sig) catch {};
}

/// Forward `sig` to every live child.
fn forward(sig: u8) void {
    for (&tracked) |*slot| {
        const pid = slot.load(.acquire);
        if (pid <= 0) continue;
        kill(pid, sig);
    }
}

fn handler(sig: i32) callconv(.c) void {
    const signo: u8 = @intCast(sig);
    // Publish before scanning, so a child tracked concurrently with the scan
    // gets signalled by its own thread rather than silently missed.
    terminating.store(signo, .release);
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
    const signos = [_]u8{ std.posix.SIG.INT, std.posix.SIG.TERM, std.posix.SIG.HUP };

    // Block the siblings while a handler runs. Without this a SIGTERM landing
    // mid-SIGINT nests a second handler, whose re-raise kills jake before the
    // outer one restores its own default disposition.
    var mask = std.posix.sigemptyset();
    for (signos) |sig| std.posix.sigaddset(&mask, sig);

    const act = std.posix.Sigaction{
        .handler = .{ .handler = handler },
        .mask = mask,
        .flags = 0,
    };
    for (signos) |sig| std.posix.sigaction(sig, &act, null);
}

test "track returns distinct slots and untrack frees them" {
    if (!enabled) return error.SkipZigTest;
    for (&tracked) |*slot| slot.store(0, .release);
    defer for (&tracked) |*slot| slot.store(0, .release);

    var a = track(111);
    const b = track(222);
    try std.testing.expectEqual(@as(usize, 0), a);
    try std.testing.expectEqual(@as(usize, 1), b);
    try std.testing.expectEqual(@as(i32, 111), tracked[0].load(.acquire));
    try std.testing.expectEqual(@as(i32, 222), tracked[1].load(.acquire));

    untrack(&a);
    try std.testing.expectEqual(@as(i32, 0), tracked[0].load(.acquire));
    try std.testing.expectEqual(@as(i32, 222), tracked[1].load(.acquire));

    // The freed slot is reused by the next child.
    try std.testing.expectEqual(@as(usize, 0), track(333));
    try std.testing.expectEqual(@as(i32, 333), tracked[0].load(.acquire));

    // Invalid pids are ignored rather than occupying a slot.
    try std.testing.expectEqual(no_slot, track(0));
    try std.testing.expectEqual(no_slot, track(-5));
    try std.testing.expectEqual(@as(i32, 0), tracked[2].load(.acquire));
}

test "a repeated untrack cannot clear the child that reused the slot" {
    if (!enabled) return error.SkipZigTest;
    for (&tracked) |*slot| slot.store(0, .release);
    defer for (&tracked) |*slot| slot.store(0, .release);

    // Thread A tracks pid 4242, reaps it, and frees its slot.
    var a = track(4242);
    untrack(&a);
    try std.testing.expectEqual(no_slot, a);

    // Thread B spawns a child that lands in the slot A just freed - and that
    // the kernel may even have handed the same recycled pid.
    var b = track(4242);
    try std.testing.expectEqual(@as(usize, 0), b);

    // A's deferred second untrack must be inert, not clear B's live child.
    untrack(&a);
    try std.testing.expectEqual(@as(i32, 4242), tracked[b].load(.acquire));

    untrack(&b);
    try std.testing.expectEqual(@as(i32, 0), tracked[0].load(.acquire));
}

test "track is a no-op once every slot is full" {
    if (!enabled) return error.SkipZigTest;
    for (&tracked, 0..) |*slot, i| slot.store(@intCast(i + 1), .release);
    defer for (&tracked) |*slot| slot.store(0, .release);

    try std.testing.expectEqual(no_slot, track(9999)); // must not overwrite
    for (&tracked, 0..) |*slot, i| {
        try std.testing.expectEqual(@as(i32, @intCast(i + 1)), slot.load(.acquire));
    }
}

test "a child tracked after the handler fired is not left in the table" {
    if (!enabled) return error.SkipZigTest;
    for (&tracked) |*slot| slot.store(0, .release);
    terminating.store(std.posix.SIG.INT, .release);
    defer {
        terminating.store(0, .release);
        for (&tracked) |*slot| slot.store(0, .release);
    }

    // pid 1 is rejected by kill(), so this exercises the bookkeeping without
    // signalling anything real: the slot is claimed, then released again.
    try std.testing.expectEqual(no_slot, track(1));
    try std.testing.expectEqual(@as(i32, 0), tracked[0].load(.acquire));
}
