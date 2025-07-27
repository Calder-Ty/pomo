//! A Linux Utility for keeping track of a pomodoro timer
//! This is more of a toy for me to play around with Unix Domain sockets
//! And Signal Handlers. I don't know if using a long running process is
//! really worth it.

pub fn main() !void {
    const action: posix.Sigaction = .{
        .handler = .{ .handler = &handle_interrupt },
        .mask = @splat(0),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &action, null);
    // Become background process
    if (try posix.fork() != 0) std.process.exit(0);
    _ = std.os.linux.setsid();

    // Not Session Leader
    if (try posix.fork() != 0) std.process.exit(0);
    _ = umask(0);
    try std.posix.chdir("/");

    // Reroute STDOUT/STDERR to DEV NULL
    std.posix.close(posix.STDIN_FILENO);
    const fd = try posix.open("/dev/null", .{ .ACCMODE = .RDWR }, 0);
    if (fd != posix.STDIN_FILENO) {
        return error.InvalidFileNo;
    }
    try std.posix.dup2(posix.STDIN_FILENO, posix.STDOUT_FILENO);
    try std.posix.dup2(posix.STDIN_FILENO, posix.STDERR_FILENO);
    try runServer();
}

export fn handle_interrupt(signal: i32) void {
    _ = signal;
    posix.unlink(well_known_address) catch {};
    posix.exit(1);
}

// TODO: Handle if linked to libc
fn umask(mask: std.os.linux.mode_t) std.os.linux.mode_t {
    return @as(std.os.linux.mode_t, std.os.linux.syscall1(.umask, mask));
}

fn runServer() !void {
    const fd = try posix.socket(AF.UNIX, SOCK.STREAM, 0);
    var addr: linux.sockaddr.un = undefined;
    addr.family = AF.UNIX;
    @memset(&addr.path, 0);
    // TODO: Truncate well_known_address if it is longer
    @memcpy(addr.path[0..well_known_address.len], well_known_address[0..]);

    try posix.bind(fd, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
    defer {
        posix.close(fd);
        posix.unlink(well_known_address) catch {
            @panic("ERROR UNLINKING SOCKET!");
        };
    }

    log.debug("Listening on {s}...", .{well_known_address});
    try posix.listen(fd, backlog);

    var timer: ?pomo.PomoRecord = null;

    while (true) {
        defer @memset(msg_bfr[0..], 0);
        const cfd = try posix.accept(fd, null, null, 0);
        const stream = std.net.Stream{ .handle = cfd };
        const writer = stream.writer();
        log.debug("Connection!", .{});
        defer posix.close(cfd);

        const n = posix.read(cfd, &msg_bfr) catch {
            _ = posix.write(cfd, "-1") catch continue;
            continue;
        };

        // Handle the message
        var tokens = std.mem.splitScalar(u8, msg_bfr[0..n], ' ');
        const cmd = tokens.first();
        if (std.mem.eql(u8, "start", cmd)) {
            log.debug("Recieved Start Command", .{});
            if (timer != null) {
                _ = posix.write(cfd, "5") catch continue;
                continue;
            }
            const long_str = tokens.next() orelse {
                _ = posix.write(cfd, "1") catch continue;
                continue;
            };
            const short_str = tokens.next() orelse {
                _ = posix.write(cfd, "2") catch continue;
                continue;
            };
            const long = std.fmt.parseInt(i64, long_str, 10) catch {
                _ = posix.write(cfd, "3") catch continue;
                continue;
            };
            const short = std.fmt.parseInt(i64, short_str, 10) catch {
                _ = posix.write(cfd, "4") catch continue;
                continue;
            };
            timer = .init(long, short);
            _ = posix.write(cfd, "0") catch continue;
        } else if (std.mem.eql(u8, "status", cmd)) {
            log.debug("Recieved message {s}", .{msg_bfr});
            if (timer) |t| {
                const status = t.status(std.time.timestamp());
                log.debug("{any}", .{status});
                status.serialize(writer) catch {
                    _ = writer.write("-2") catch continue;
                    continue;
                };
            } else {
                _ = writer.write("-1") catch continue;
                continue;
            }
        } else if (std.mem.eql(u8, "stop", cmd)) {
            timer = null;
            _ = writer.write("0") catch continue;
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

const SOCK = posix.SOCK;
const AF = posix.AF;
const backlog = 5;
const message_limit = 100;
var msg_bfr: [100]u8 = @splat(0);
const log = std.log.scoped(.main);

test {
    _ = pomo.PomoRecord;
}
