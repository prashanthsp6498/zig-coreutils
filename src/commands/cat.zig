// SPDX-License-Identifier: MIT

pub const enabled: bool = true;

pub const command: Command = .{
    .name = "cat",

    .short_help =
    \\Usage: {NAME} [OPTION]... [FILE]...
    \\Concatenate FILE(s) to standard output.
    \\
    \\Available options
    \\  -h, --help               display the help and exit
    \\      --version            output version information and exit
    \\
    ,

    .extended_help =
    \\Example:
    \\  cat FILE
    \\
    ,

    .execute = impl.execute,
};

// namespace required to prevent tests of disabled commands from being analyzed
const impl = struct {
    fn execute(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        system: System,
        exe_path: []const u8,
    ) Command.Error!void {
        var options = try parseArguments(allocator, io, args, exe_path);
        defer {
            options.paths.deinit(allocator);
        }
        return simplecat(allocator, io, system, options);
    }

    fn simplecat(
        allocator: std.mem.Allocator,
        io: IO,
        system: System,
        options: CatOptions,
    ) !void {
        for (options.paths.items) |path| {
            const file: System.File = blk: {
                const file_to_read_or_error = system.cwd().openFile(path, .{ .mode = .read_only });
                break :blk file_to_read_or_error catch |err| {
                    // print error message and continue for next
                    command.printErrorAlloc(
                        allocator,
                        io,
                        "failed to open {s} : {t}",
                        .{ path, err },
                    ) catch continue;
                };
            };
            defer file.close();
            var buff: [1024]u8 = undefined;
            while (true) {
                const total_read = file.readAll(buff[0..]) catch |err| {
                    command.printErrorAlloc(
                        allocator,
                        io,
                        "failed to read {s} : {t}",
                        .{ path, err },
                    ) catch continue;
                };
                if (total_read == 0) {
                    break;
                }
                try io.stdoutWriteAll(buff[0..total_read]);
            }
        }
    }

    const CatOptions = struct {
        number_all: bool = false,
        show_tabs: bool = false,
        show_ends: bool = false,
        paths: std.ArrayList([]const u8) = .empty,
        pub fn format(options: CatOptions, writer: *std.Io.Writer) !void {
            _ = options;
            try writer.writeAll("CatOptions {}");
        }
    };

    fn parseArguments(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        exe_path: []const u8,
    ) !CatOptions {
        var opt_arg: ?Arg = try args.nextWithHelpOrVersion(true);

        var cat_options: CatOptions = .{};

        const State = union(enum) {
            normal,
            invalid_argument: Argument,

            const Argument = union(enum) {
                slice: []const u8,
                character: u8,
            };
        };

        var state: State = .normal;

        outer: while (opt_arg) |*arg| : (opt_arg = args.next()) {
            switch (arg.arg_type) {
                .longhand => |longhand| {
                    if (state != .normal) {
                        @branchHint(.cold);
                        state = .{ .invalid_argument = .{ .slice = longhand } };
                        break :outer;
                    }
                },
                .longhand_with_value => |longhand_with_value| {
                    @branchHint(.cold);
                    std.debug.assert(state == .normal);
                    state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                    break :outer;
                },
                .shorthand => |*shorthand| {
                    if (state != .normal) {
                        @branchHint(.cold);
                        std.debug.assert(state == .normal);
                        state = .{ .invalid_argument = .{ .slice = shorthand.value } };
                        break :outer;
                    }
                    while (shorthand.next()) |char| {
                        switch (char) {
                            'n' => {
                                cat_options.number_all = true;
                            },
                            else => break :outer,
                        }
                    }
                },
                .positional => {
                    if (state != .normal) {
                        @branchHint(.cold);
                        state = .{ .invalid_argument = .{ .slice = arg.raw } };
                        break :outer;
                    }

                    try cat_options.paths.append(allocator, arg.raw);
                },
            }
        }

        return switch (state) {
            .normal => cat_options,
            .invalid_argument => |invalid_arg| switch (invalid_arg) {
                .slice => |slice| command.printInvalidUsageAlloc(
                    allocator,
                    io,
                    exe_path,
                    "unrecognized option: '{s}'",
                    .{slice},
                ),
                .character => |character| command.printInvalidUsageAlloc(
                    allocator,
                    io,
                    exe_path,
                    "unrecognized short option: '{c}'",
                    .{character},
                ),
            },
        };
    }

    test "cat no args" {
        try command.testExecute(&.{}, .{});
    }

    test "cat help" {
        try command.testHelp(true);
    }

    test "cat version" {
        try command.testVersion();
    }

    test "cat fuzz" {
        try command.testFuzz(.{
            .expect_stdout_output_on_success = true,
        });
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const log = std.log.scoped(.cat);

const std = @import("std");
