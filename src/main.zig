const std = @import("std");
const builtin = @import("builtin");
const globlike = @import("globlike");
const brace = @import("brace.zig");

const version = "0.3.0";

const OutputFormat = enum { newline, space, nul, double_quote };

const Options = struct {
	ignore_case: bool = false,
	include_dotfiles: bool = false,
	batch: bool = false,
	dry_run: bool = false,
	format: OutputFormat = .newline,
	saw_space: bool = false,
	saw_nul: bool = false,
};

const help =
	\\glob: A utility for controlled glob expansion
	\\
	\\USAGE:
	\\  glob [OPTIONS] PATTERN                   Expand patterns and print results
	\\  glob [OPTIONS] COMMAND [ARG...]          Run a command with expanded arguments
	\\  glob -h, --help                          Show this help
	\\  glob --about                             Show version and compiled platform
	\\
	\\OPTIONS:
	\\  -i, --ignore-case                Case-insensitive pattern matching
	\\  --dotglob, --dotfiles            Include dotfiles in matches
	\\  --all                            No restrictions (includes dotfiles)
	\\  --batch                          Run a command in ARG_MAX-safe chunks
	\\  --dry-run, --debug               Show the expanded command without running it
	\\  --double-quote                   Double-quoted, newline-separated output
	\\  -n                               Shell-escaped, space-separated output
	\\  -0                               NUL-separated output
	\\
	\\Patterns that match nothing are omitted. Direct mode exits 1 when nothing
	\\matches. Output is sorted in locale-independent code-point order. Command mode
	\\preserves argument order and sorts only the members expanded from each pattern.
	\\Pattern matching is provided by globlike, including `%r{...}` inline regex
	\\excerpts.
;

pub fn main(init: std.process.Init) !u8 {
	var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
	defer iterator.deinit();
	_ = iterator.next();

	var raw: std.ArrayListUnmanaged([]const u8) = .empty;
	while (iterator.next()) |arg| try raw.append(init.arena.allocator(), arg);
	if (raw.items.len == 0) {
		try stderr(init, "Error: No arguments provided\n");
		try stderr(init, help);
		return 2;
	}
	if (std.mem.eql(u8, raw.items[0], "-h") or std.mem.eql(u8, raw.items[0], "--help")) {
		try stdout(init, help);
		return 0;
	}
	if (std.mem.eql(u8, raw.items[0], "--about")) {
		try printAbout(init);
		return 0;
	}

	var options: Options = .{};
	var parsed: std.ArrayListUnmanaged([]const u8) = .empty;
	for (raw.items) |arg| {
		if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--ignore-case")) {
			options.ignore_case = true;
		} else if (std.mem.eql(u8, arg, "--dotglob") or std.mem.eql(u8, arg, "--dotfiles") or std.mem.eql(u8, arg, "--all")) {
			options.include_dotfiles = true;
		} else if (std.mem.eql(u8, arg, "--batch")) {
			options.batch = true;
		} else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "--debug")) {
			options.dry_run = true;
		} else if (std.mem.eql(u8, arg, "--double-quote")) {
			options.format = .double_quote;
		} else if (std.mem.eql(u8, arg, "-n")) {
			options.saw_space = true;
			if (options.format != .double_quote) options.format = .space;
		} else if (std.mem.eql(u8, arg, "-0")) {
			options.saw_nul = true;
			if (options.format != .double_quote) options.format = .nul;
		} else {
			try parsed.append(init.arena.allocator(), arg);
		}
	}
	if (options.format == .double_quote) {
		if (options.saw_space) try stderr(init, "Warning: -n is ignored when --double-quote is used\n");
		if (options.saw_nul) try stderr(init, "Warning: -0 is ignored when --double-quote is used\n");
	}
	if (parsed.items.len == 0) {
		try stderr(init, "Error: No arguments provided after option parsing\n");
		try stderr(init, help);
		return 2;
	}

	var expanded_args: std.ArrayListUnmanaged([]const u8) = .empty;
	var brace_was_expanded = false;
	for (parsed.items) |arg| {
		const expansion = try brace.expand(init.arena.allocator(), arg);
		if (expansion.items.len > 1) brace_was_expanded = true;
		try expanded_args.appendSlice(init.arena.allocator(), expansion.items);
	}

	var command_name: ?[]const u8 = null;
	if (expanded_args.items.len > 0 and !hasDataExtension(expanded_args.items[0]) and isExecutable(init, expanded_args.items[0])) {
		command_name = expanded_args.items[0];
		_ = expanded_args.orderedRemove(0);
	}
	if (command_name != null and options.format == .double_quote) {
		try stderr(init, "Error: --double-quote cannot be used with command execution\n");
		return 2;
	}
	if (command_name == null and options.dry_run) {
		try stderr(init, "Error: --dry-run/--debug requires a command\n");
		return 2;
	}
	if (command_name == null and options.batch) {
		try stderr(init, "Error: --batch requires a command\n");
		return 2;
	}

	var found = false;
	var patterns: std.ArrayListUnmanaged([]const u8) = .empty;
	var processed: std.ArrayListUnmanaged([]const u8) = .empty;
	for (expanded_args.items) |arg| {
		if (command_name != null and std.mem.startsWith(u8, arg, "-")) {
			try processed.append(init.arena.allocator(), arg);
			continue;
		}
		if (isPattern(arg)) {
			try patterns.append(init.arena.allocator(), arg);
			const matches = expandPattern(init, arg, options.ignore_case, options.include_dotfiles) catch return 2;
			std.mem.sort([]const u8, matches.items, {}, lessThanString);
			if (matches.items.len > 0) {
				found = true;
				try processed.appendSlice(init.arena.allocator(), matches.items);
			}
		} else {
			found = true;
			try processed.append(init.arena.allocator(), arg);
		}
	}

	if (!options.include_dotfiles and !brace_was_expanded and patterns.items.len > 0) {
		if (try excludedDotfileMatched(init, patterns.items, options.ignore_case)) {
			try stderr(init, "\x1b[33mNote: dotfiles were excluded. Use --dotglob or --all to include them.\x1b[0m\n");
		}
	}

	if (!found) {
		if (patterns.items.len > 0) {
			try stderr(init, "Error: No matches found for pattern(s): ");
			for (patterns.items, 0..) |pattern, index| {
				if (index > 0) try stderr(init, " ");
				try stderr(init, pattern);
			}
			try stderr(init, "\n");
		} else {
			try stderr(init, "Error: No matches found\n");
		}
		return 1;
	}

	if (command_name) |command| {
		if (options.dry_run) {
			try stderr(init, "\x1b[33m");
			try writeShellEscaped(init, std.Io.File.stderr(), command);
			for (processed.items) |arg| {
				try stderr(init, " ");
				try writeShellEscaped(init, std.Io.File.stderr(), arg);
			}
			try stderr(init, "\x1b[0m\n");
			return 0;
		}
		if (options.batch) return runBatched(init, command, processed.items);
		if (argBudget(init)) |budget| {
			const bytes = argumentBytes(command, processed.items);
			if (bytes > budget.safe) {
				var buffer: [256]u8 = undefined;
				const message = try std.fmt.bufPrint(&buffer, "Error: expanded arguments exceed safe ARG_MAX budget ({d} bytes > {d}; system ARG_MAX {d}). Re-run with --batch.\n", .{ bytes, budget.safe, budget.maximum });
				try stderr(init, message);
				return 2;
			}
		}
		return runCommand(init, command, processed.items);
	}

	std.mem.sort([]const u8, processed.items, {}, lessThanString);
	try writeResults(init, processed.items, options.format);
	return 0;
}

fn stdout(init: std.process.Init, message: []const u8) !void {
	try std.Io.File.stdout().writeStreamingAll(init.io, message);
}

fn stderr(init: std.process.Init, message: []const u8) !void {
	try std.Io.File.stderr().writeStreamingAll(init.io, message);
}

fn printAbout(init: std.process.Init) !void {
	const os = switch (builtin.target.os.tag) {
		.linux => "linux",
		.macos => "macos",
		.windows => "mswin",
		else => "unknown",
	};
	const arch = switch (builtin.target.cpu.arch) {
		.x86_64 => "amd64",
		.aarch64 => "arm64",
		else => "unknown",
	};
	var buffer: [192]u8 = undefined;
	const message = if (builtin.target.os.tag == .linux)
		try std.fmt.bufPrint(&buffer, "glob {s} — controlled pathname expansion; PF={s}-{s} VARIANT={s}\n", .{ version, os, arch, if (builtin.target.abi.isMusl()) "musl" else "gnu" })
	else
		try std.fmt.bufPrint(&buffer, "glob {s} — controlled pathname expansion; PF={s}-{s}\n", .{ version, os, arch });
	try stdout(init, message);
}

fn isPattern(value: []const u8) bool {
	if (std.mem.startsWith(u8, value, "glob:") or std.mem.startsWith(u8, value, "regex:")) return true;
	if (std.mem.indexOf(u8, value, "%r") != null) return true;
	for (value, 0..) |byte, index| {
		if (byte == '*' or byte == '?' or byte == '[') return true;
		if ((byte == '+' or byte == '@' or byte == '!') and index + 1 < value.len and value[index + 1] == '(') return true;
	}
	return false;
}

fn hasDataExtension(value: []const u8) bool {
	const extensions = [_][]const u8{ ".jpg", ".jpeg", ".png", ".gif", ".pdf", ".mp4", ".avi", ".mp3", ".wav", ".doc", ".docx", ".txt", ".log", ".csv" };
	for (extensions) |extension| if (std.mem.endsWith(u8, value, extension)) return true;
	return false;
}

fn isExecutable(init: std.process.Init, candidate: []const u8) bool {
	if (std.mem.indexOfScalar(u8, candidate, '/') != null) return executableFile(init, candidate);
	const path = init.environ_map.get("PATH") orelse return false;
	var parts = std.mem.splitScalar(u8, path, ':');
	while (parts.next()) |part| {
		const directory = if (part.len == 0) "." else part;
		const joined = std.fs.path.join(init.arena.allocator(), &.{ directory, candidate }) catch return false;
		if (executableFile(init, joined)) return true;
	}
	return false;
}

fn executableFile(init: std.process.Init, path: []const u8) bool {
	std.Io.Dir.cwd().access(init.io, path, .{ .execute = true }) catch return false;
	const stat = std.Io.Dir.cwd().statFile(init.io, path, .{}) catch return false;
	return stat.kind != .directory;
}

fn expandPattern(init: std.process.Init, source: []const u8, case_insensitive: bool, dotglob: bool) !std.ArrayListUnmanaged([]const u8) {
	const compiled = try globlike.compile(init.gpa, source, .{ .case_insensitive = case_insensitive });
	var pattern = switch (compiled) {
		.diagnostic => |diagnostic| {
			try reportDiagnostic(init, "invalid pattern", diagnostic);
			return error.InvalidPattern;
		},
		.pattern => |value| value,
	};
	defer pattern.deinit();

	const absolute_root = absoluteTraversalRoot(source);
	const root_path = absolute_root orelse ".";
	var directory = (if (absolute_root != null)
		std.Io.Dir.openDirAbsolute(init.io, root_path, .{ .iterate = true })
	else
		std.Io.Dir.cwd().openDir(init.io, root_path, .{ .iterate = true })) catch |err| {
		try reportError(init, "cannot open traversal root", err);
		return error.TraversalFailed;
	};
	defer directory.close(init.io);
	var walker = try directory.walk(init.gpa);
	defer walker.deinit();

	var matches: std.ArrayListUnmanaged([]const u8) = .empty;
	const explicit_current = std.mem.startsWith(u8, source, "./");
	while (walker.next(init.io) catch |err| {
		try reportError(init, "cannot traverse directory", err);
		return error.TraversalFailed;
	}) |entry| {
		if (std.mem.indexOfScalar(u8, entry.path, '\n') != null) continue;
		const candidate = if (absolute_root) |root|
			if (std.mem.eql(u8, root, "/"))
				try std.fmt.allocPrint(init.arena.allocator(), "/{s}", .{entry.path})
			else
				try std.fmt.allocPrint(init.arena.allocator(), "{s}/{s}", .{ root, entry.path })
		else if (explicit_current)
			try std.fmt.allocPrint(init.arena.allocator(), "./{s}", .{entry.path})
		else
			try init.arena.allocator().dupe(u8, entry.path);
		if (!dotglob and !dotPathAllowed(source, candidate)) continue;
		switch (pattern.matches(candidate)) {
			.matched => |matched| if (matched) try matches.append(init.arena.allocator(), candidate),
			.diagnostic => |diagnostic| {
				try reportDiagnostic(init, "matching failed", diagnostic);
				return error.InvalidPattern;
			},
		}
	}
	return matches;
}

fn excludedDotfileMatched(init: std.process.Init, patterns: []const []const u8, case_insensitive: bool) !bool {
	for (patterns) |pattern| {
		const basename = std.fs.path.basename(pattern);
		if (std.mem.startsWith(u8, basename, ".")) continue;
		const matches = expandPattern(init, pattern, case_insensitive, true) catch return false;
		for (matches.items) |member| if (std.mem.startsWith(u8, std.fs.path.basename(member), ".")) return true;
	}
	return false;
}

fn writeResults(init: std.process.Init, items: []const []const u8, format: OutputFormat) !void {
	const out = std.Io.File.stdout();
	for (items) |item| switch (format) {
		.newline => {
			try out.writeStreamingAll(init.io, item);
			try out.writeStreamingAll(init.io, "\n");
		},
		.nul => {
			try out.writeStreamingAll(init.io, item);
			try out.writeStreamingAll(init.io, "\x00");
		},
		.space => {
			try writeShellEscaped(init, out, item);
			try out.writeStreamingAll(init.io, " ");
		},
		.double_quote => {
			try out.writeStreamingAll(init.io, "\"");
			for (item) |byte| {
				if (byte == '"') try out.writeStreamingAll(init.io, "\\\"") else try out.writeStreamingAll(init.io, &.{byte});
			}
			try out.writeStreamingAll(init.io, "\"\n");
		},
	};
	if (format == .space) try out.writeStreamingAll(init.io, "\n");
}

fn writeShellEscaped(init: std.process.Init, file: std.Io.File, value: []const u8) !void {
	if (value.len == 0) {
		try file.writeStreamingAll(init.io, "''");
		return;
	}
	for (value) |byte| {
		const safe = std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-' or byte == '.' or byte == '/' or byte == ':' or byte == ',' or byte == '=' or byte == '+' or byte == '%';
		if (!safe) try file.writeStreamingAll(init.io, "\\");
		try file.writeStreamingAll(init.io, &.{byte});
	}
}

fn runCommand(init: std.process.Init, command: []const u8, args: []const []const u8) !u8 {
	var argv: std.ArrayListUnmanaged([]const u8) = .empty;
	try argv.append(init.arena.allocator(), command);
	try argv.appendSlice(init.arena.allocator(), args);
	var child = std.process.spawn(init.io, .{ .argv = argv.items }) catch |err| {
		try reportError(init, "cannot execute command", err);
		return 127;
	};
	return termExitCode(try child.wait(init.io));
}

fn termExitCode(term: std.process.Child.Term) u8 {
	return switch (term) {
		.exited => |code| code,
		.signal => |signal| @intCast(@min(255, 128 + @intFromEnum(signal))),
		.stopped => |signal| @intCast(@min(255, 128 + @intFromEnum(signal))),
		.unknown => 1,
	};
}

const Budget = struct { maximum: usize, safe: usize };

fn argBudget(init: std.process.Init) ?Budget {
	var maximum: usize = 0;
	if (init.environ_map.get("GLOB_ARG_MAX")) |value| {
		maximum = std.fmt.parseInt(usize, value, 10) catch return null;
	} else maximum = switch (builtin.target.os.tag) {
		.linux => 2 * 1024 * 1024,
		.macos => 256 * 1024,
		else => return null,
	};
	var buffer = maximum / 10;
	if (buffer < 4096) buffer = 4096;
	return .{ .maximum = maximum, .safe = if (maximum > buffer) maximum - buffer else maximum };
}

fn argumentBytes(command: []const u8, args: []const []const u8) usize {
	var total = command.len + 1;
	for (args) |arg| total += arg.len + 1;
	return total;
}

fn runBatched(init: std.process.Init, command: []const u8, args: []const []const u8) !u8 {
	const budget = argBudget(init) orelse {
		try stderr(init, "Warning: ARG_MAX unavailable; batching one argument per command\n");
		var overall: u8 = 0;
		for (args, 0..) |arg, index| {
			const code = try runCommand(init, command, &.{arg});
			if (code != 0) overall = code;
			try reportBatch(init, index + 1, args.len);
		}
		return overall;
	};
	const base_size = command.len + 1;
	var chunk_budget = budget.safe / 2;
	if (chunk_budget <= base_size) chunk_budget = budget.safe;

	var chunks: std.ArrayListUnmanaged(struct { start: usize, end: usize }) = .empty;
	var start: usize = 0;
	var size = base_size;
	for (args, 0..) |arg, index| {
		const item_size = arg.len + 1;
		if (item_size + base_size > budget.safe) {
			try stderr(init, "Error: argument too long for system ARG_MAX; cannot batch safely: ");
			try stderr(init, arg);
			try stderr(init, "\n");
			return 2;
		}
		if (index > start and size + item_size > chunk_budget) {
			try chunks.append(init.arena.allocator(), .{ .start = start, .end = index });
			start = index;
			size = base_size;
		}
		size += item_size;
	}
	if (start < args.len) try chunks.append(init.arena.allocator(), .{ .start = start, .end = args.len });
	if (chunks.items.len > 1) {
		var buffer: [128]u8 = undefined;
		const prefix = if (argumentBytes(command, args) > budget.safe) "Results > ARG_MAX; batching results" else "Batching results";
		try stderr(init, try std.fmt.bufPrint(&buffer, "{s} into {d} batches:\n", .{ prefix, chunks.items.len }));
	}
	var overall: u8 = 0;
	for (chunks.items, 0..) |chunk, index| {
		const code = try runCommand(init, command, args[chunk.start..chunk.end]);
		if (code != 0) overall = code;
		try reportBatch(init, index + 1, chunks.items.len);
	}
	return overall;
}

fn reportBatch(init: std.process.Init, index: usize, count: usize) !void {
	var buffer: [128]u8 = undefined;
	if (index < count) {
		try stderr(init, try std.fmt.bufPrint(&buffer, "Batch {d}/{d} done (ETA ~{d}s)\n", .{ index, count, count - index }));
	} else {
		try stderr(init, try std.fmt.bufPrint(&buffer, "Batch {d}/{d} done\n", .{ index, count }));
	}
}

fn lessThanString(_: void, lhs: []const u8, rhs: []const u8) bool {
	return std.mem.lessThan(u8, lhs, rhs);
}

fn reportError(init: std.process.Init, context: []const u8, err: anyerror) !void {
	var buffer: [512]u8 = undefined;
	try stderr(init, try std.fmt.bufPrint(&buffer, "glob: {s}: {t}\n", .{ context, err }));
}

fn reportDiagnostic(init: std.process.Init, context: []const u8, diagnostic: globlike.Diagnostic) !void {
	var diagnostic_buffer: [512]u8 = undefined;
	const detail = diagnostic.message(&diagnostic_buffer);
	var message_buffer: [768]u8 = undefined;
	const message = if (diagnostic.offset) |offset|
		try std.fmt.bufPrint(&message_buffer, "glob: {s} at byte {d}: {s}\n", .{ context, offset, detail })
	else
		try std.fmt.bufPrint(&message_buffer, "glob: {s}: {s}\n", .{ context, detail });
	try stderr(init, message);
}

fn dotPathAllowed(pattern: []const u8, path: []const u8) bool {
	if (!hasHiddenComponent(path)) return true;
	if (std.mem.startsWith(u8, pattern, "regex:") or std.mem.indexOf(u8, pattern, "%r") != null) return false;
	const glob_pattern = if (std.mem.startsWith(u8, pattern, "glob:")) pattern[5..] else pattern;
	return dotComponentsAllowed(trimPathPrefix(glob_pattern), trimPathPrefix(path));
}

fn dotComponentsAllowed(pattern: []const u8, path: []const u8) bool {
	if (path.len == 0) return true;
	if (pattern.len == 0) return false;
	const pattern_end = std.mem.indexOfScalar(u8, pattern, '/') orelse pattern.len;
	const path_end = std.mem.indexOfScalar(u8, path, '/') orelse path.len;
	const pattern_component = pattern[0..pattern_end];
	const path_component = path[0..path_end];
	const pattern_rest = trimLeadingSlashes(pattern[pattern_end..]);
	const path_rest = trimLeadingSlashes(path[path_end..]);
	if (std.mem.eql(u8, pattern_component, "**")) {
		if (dotComponentsAllowed(pattern_rest, path)) return true;
		if (path_component[0] == '.') return false;
		return dotComponentsAllowed(pattern, path_rest);
	}
	if (path_component[0] == '.' and !std.mem.startsWith(u8, pattern_component, ".")) return false;
	return dotComponentsAllowed(pattern_rest, path_rest);
}

fn trimPathPrefix(path: []const u8) []const u8 {
	const without_current = if (std.mem.startsWith(u8, path, "./")) path[2..] else path;
	return trimLeadingSlashes(without_current);
}

fn trimLeadingSlashes(path: []const u8) []const u8 {
	return std.mem.trimStart(u8, path, "/");
}

fn hasHiddenComponent(path: []const u8) bool {
	var parts = std.mem.splitScalar(u8, path, '/');
	while (parts.next()) |part| if (part.len > 1 and part[0] == '.' and !std.mem.eql(u8, part, "..")) return true;
	return false;
}

fn absoluteTraversalRoot(pattern: []const u8) ?[]const u8 {
	if (pattern.len == 0 or pattern[0] != '/') return null;
	var special = pattern.len;
	for (pattern, 0..) |byte, index| {
		if (byte == '*' or byte == '?' or byte == '[' or byte == '%' or byte == '{') {
			special = index;
			break;
		}
	}
	const slash = std.mem.lastIndexOfScalar(u8, pattern[0..special], '/') orelse return "/";
	return if (slash == 0) "/" else pattern[0..slash];
}
