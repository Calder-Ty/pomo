//! Source file that exposes the executable's API and test suite to users,
//! Autodoc, and the build system.

/// Key state of a PomoTimer, Used to calculate current status
pub const PomoRecord = struct {
    /// Start time of the PomoTimer
    start_time: i64,
    /// Length of the work time
    long_seconds: i64,
    /// Length of Resting Time
    short_seconds: i64,

    pub fn init(long: i64, short: i64) PomoRecord {
        const start_time = std.time.timestamp();
        return .{
            .start_time = start_time,
            .long_seconds = long,
            .short_seconds = short,
        };
    }

    pub fn status(self: @This(), current: i64) PomoStatus {
        // Calculate the current state based off current time
        var delta = current - self.start_time;

        // What session are we in?
        if (delta < self.long_seconds) {
            // First Session
        }

        // Identify # of sessions that have passed
        var work_sessions: u8 = 0;
        var session_state = PomoState.working;
        var time_limit = self.long_seconds;
        while (delta > time_limit) {
            delta -|= time_limit;
            if (session_state == .working) {
                session_state = .resting;
                work_sessions +|= 1;
                // Every 4 work sessions take an extra long break
                if (work_sessions % 4 != 0) time_limit = self.short_seconds;
            } else {
                session_state = .working;
                // Every 4 work sessions take an extra long break
                time_limit = self.long_seconds;
            }
        }
        return .{
            .state = session_state,
            .seconds_remaining = time_limit - delta,
            .sessions_complete = work_sessions,
        };
    }

    test status {
        var pomo = PomoRecord.init(100, 10);
        // To make it work, set the start time direclty
        pomo.start_time = 0;

        try std.testing.expectEqual(.working, pomo.status(10).state);
        try std.testing.expectEqual(90, pomo.status(10).seconds_remaining);
        try std.testing.expectEqual(0, pomo.status(10).sessions_complete);

        try std.testing.expectEqual(.resting, pomo.status(105).state);
        try std.testing.expectEqual(5, pomo.status(105).seconds_remaining);
        try std.testing.expectEqual(1, pomo.status(105).sessions_complete);

        try std.testing.expectEqual(.resting, pomo.status(435).state);
        try std.testing.expectEqual(95, pomo.status(435).seconds_remaining);
        try std.testing.expectEqual(4, pomo.status(435).sessions_complete);
    }
};

/// Current Status of the Pomo Timer
pub const PomoStatus = struct {
    state: PomoState,
    seconds_remaining: i64,
    sessions_complete: u8,

    pub fn serialize(self: @This(), writer: anytype) !void {
        try writer.print("{d} {d} {d}", .{
            @intFromEnum(self.state),
            self.seconds_remaining,
            self.sessions_complete,
        });
    }
};

const PomoState = enum(u1) { working, resting };

const std = @import("std");
const testing = std.testing;

test {
    _ = PomoRecord;
}
