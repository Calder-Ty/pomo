//! A Linux Utility for keeping track of a pomodoro timer
//! This is more of a toy for me to play around with Unix Domain sockets
//! And Signal Handlers. I don't know if using a long running process is
//! really worth it.

pub fn main(init: std.process.Init) !void {
    const action: posix.Sigaction = .{
        .handler = .{ .handler = &handle_interrupt },
        .mask = @splat(0),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &action, null);
    // Become background process
    if (posix.errno(linux.fork()) != .SUCCESS) exit(0);
    _ = std.os.linux.setsid();

    // Not Session Leader
    if (posix.errno(linux.fork()) != .SUCCESS) exit(0);
    _ = umask(0);
    if (posix.errno(linux.chdir("/")) != .SUCCESS) exit(1);

    // Reroute STDOUT/STDERR to DEV NULL
    _ = linux.close(posix.STDIN_FILENO);
    const fd = linux.open("/dev/null", .{ .ACCMODE = .RDWR }, 0);
    if (posix.errno(fd) != .SUCCESS) exit(1);
    if (fd != posix.STDIN_FILENO) {
        return error.InvalidFileNo;
    }
    if (posix.errno(linux.dup2(posix.STDIN_FILENO, posix.STDOUT_FILENO)) != .SUCCESS) exit(1);
    if (posix.errno(linux.dup2(posix.STDIN_FILENO, posix.STDERR_FILENO)) != .SUCCESS) exit(1);
    try runServer(init.io);
}

export fn handle_interrupt(signal: linux.SIG) void {
    _ = signal;
    _ = linux.unlink(well_known_address);
    linux.exit(1);
}

// TODO: Handle if linked to libc
fn umask(mask: std.os.linux.mode_t) std.os.linux.mode_t {
    return @as(u32, @truncate(std.os.linux.syscall1(.umask, mask)));
}

fn runServer(io: Io) !void {
    var err = linux.socket(AF.UNIX, SOCK.STREAM, 0);
    if (posix.errno(err) != .SUCCESS) return error.FailedToOpenSocket;
    const fd = @as(i32, @truncate(@as(isize, @bitCast(err))));
    var addr: linux.sockaddr.un = undefined;
    addr.family = AF.UNIX;
    @memset(&addr.path, 0);
    // TODO: Truncate well_known_address if it is longer
    @memcpy(addr.path[0..well_known_address.len], well_known_address[0..]);

    err = linux.bind(fd, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
    if (posix.errno(err) != .SUCCESS) return error.FailedToBindToSocket;
    defer {
        _ = linux.close(fd);
        _ = linux.unlink(well_known_address);
    }

    log.debug("Listening on {s}...", .{well_known_address});
    err = linux.listen(fd, backlog);
    if (posix.errno(err) != .SUCCESS) return error.FailedToListenOnSocket;

    var timer: ?pomo.PomoRecord = null;

    while (true) {
        defer @memset(msg_bfr[0..], 0);
        err = linux.accept(fd, null, null);
        if (posix.errno(err) != .SUCCESS) return error.AcceptFailure;
        const cfd: i32 = @truncate(@as(isize, @bitCast(err)));
        const stream: Io.File = .{ .handle = cfd, .flags = .{ .nonblocking = false } };
        var writer = stream.writer(io, &res_bfr);
        var w = &writer.interface;
        log.debug("Connection!", .{});
        defer _ = linux.close(cfd);

        const n = posix.read(cfd, &msg_bfr) catch {
            _ = linux.write(cfd, "-1", 2);
            continue;
        };

        // Handle the message
        var tokens = std.mem.splitScalar(u8, msg_bfr[0..n], ' ');
        const cmd = tokens.first();
        if (std.mem.eql(u8, "start", cmd)) {
            log.debug("Recieved Start Command", .{});
            if (timer != null) {
                _ = linux.write(cfd, "5", 1);
                continue;
            }
            const long_str = tokens.next() orelse {
                _ = linux.write(cfd, "1", 1);
                continue;
            };
            const short_str = tokens.next() orelse {
                _ = linux.write(cfd, "2", 1);
                continue;
            };
            const long = std.fmt.parseInt(i64, long_str, 10) catch {
                _ = linux.write(cfd, "3", 1);
                continue;
            };
            const short = std.fmt.parseInt(i64, short_str, 10) catch {
                _ = linux.write(cfd, "4", 1);
                continue;
            };
            timer = .init(io, long, short);
            _ = linux.write(cfd, "0", 1);
        } else if (std.mem.eql(u8, "status", cmd)) {
            log.debug("Recieved message {s}", .{msg_bfr});
            if (timer) |t| {
                const status = t.status(Io.Timestamp.now(io, .real).toSeconds());
                log.debug("{any}", .{status});
                status.serialize(w) catch {
                    _ = w.write("-2") catch continue;
                    continue;
                };
                w.flush() catch continue;
            } else {
                _ = w.write("-1") catch continue;
                w.flush() catch continue;
                continue;
            }
        } else if (std.mem.eql(u8, "stop", cmd)) {
            timer = null;
            _ = w.write("0") catch continue;
            w.flush() catch continue;
            continue;
        } else if (std.mem.eql(u8, "kill", cmd)) {
            break;
        }
    }
}

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const pomo = @import("pomo.zig");
const well_known_address = "/tmp/.pomo";
comptime {
    // TODO: Make 108 derived from comptime
    if (well_known_address.len > 108 - 1) @compileError("well_known_address is too long!");
}

const Io = std.Io;
const SOCK = posix.SOCK;
const AF = posix.AF;
const backlog = 5;
const message_limit = 100;
var msg_bfr: [100]u8 = @splat(0);
var res_bfr: [100]u8 = @splat(0);
const log = std.log.scoped(.main);

const exit = std.process.exit;

test {
    _ = pomo.PomoRecord;
}
