const std = @import("std");
const builtin = @import("builtin");
const globlike = @import("globlike");
const brace = @import("brace.zig");
const ignore = @import("ignore.zig");
const build_identity = @import("build_identity");

const version = "0.3.0";

const OutputFormat = enum { newline, space, nul, double_quote };

const Options = struct {
	ignore_case: bool = false,
	include_dotfiles: bool = false,
	include_gitignored: bool = false,
	mute: bool = false,
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
	\\  --hidden, --dotglob, --dotfiles   Include hidden paths and directories
	\\  --gitignore, --gitignored        Include paths excluded by .gitignore
	\\  --all                            Include hidden and gitignored paths
	\\  --mute                           Silence exclusion summaries (not errors)
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
		} else if (std.mem.eql(u8, arg, "--dotglob") or std.mem.eql(u8, arg, "--dotfiles") or std.mem.eql(u8, arg, "--hidden")) {
			options.include_dotfiles = true;
		} else if (std.mem.eql(u8, arg, "--gitignore") or std.mem.eql(u8, arg, "--gitignored")) {
			options.include_gitignored = true;
		} else if (std.mem.eql(u8, arg, "--all")) {
			options.include_dotfiles = true;
			options.include_gitignored = true;
		} else if (std.mem.eql(u8, arg, "--mute")) {
			options.mute = true;
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
	for (parsed.items) |arg| {
		const expansion = try brace.expand(init.arena.allocator(), arg);
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
	var skipped: SkipSummary = .{};
	var ignore_filter: ignore.Filter = .{};
	defer ignore_filter.deinit();
	var patterns: std.ArrayListUnmanaged([]const u8) = .empty;
	var processed: std.ArrayListUnmanaged([]const u8) = .empty;
	for (expanded_args.items) |arg| {
		if (command_name != null and std.mem.startsWith(u8, arg, "-")) {
			try processed.append(init.arena.allocator(), arg);
			continue;
		}
		if (isPattern(arg)) {
			try patterns.append(init.arena.allocator(), arg);
			const expansion = expandPattern(init, arg, options, &ignore_filter, &skipped) catch |err| {
				if (err != error.InvalidPattern and err != error.TraversalFailed) try reportError(init, "cannot apply exclusion rules", err);
				return 2;
			};
			const matches = expansion.matches;
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
		if (!options.mute) try skipped.report(init);
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
			if (!options.mute) try skipped.report(init);
			return 0;
		}
		if (options.batch) {
			const code = try runBatched(init, command, processed.items);
			if (!options.mute) try skipped.report(init);
			return code;
		}
		if (argBudget(init)) |budget| {
			const bytes = argumentBytes(command, processed.items);
			if (bytes > budget.safe) {
				var buffer: [256]u8 = undefined;
				const message = try std.fmt.bufPrint(&buffer, "Error: expanded arguments exceed safe ARG_MAX budget ({d} bytes > {d}; system ARG_MAX {d}). Re-run with --batch.\n", .{ bytes, budget.safe, budget.maximum });
				try stderr(init, message);
				if (!options.mute) try skipped.report(init);
				return 2;
			}
		}
		const code = try runCommand(init, command, processed.items);
		if (!options.mute) try skipped.report(init);
		return code;
	}

	std.mem.sort([]const u8, processed.items, {}, lessThanString);
	try writeResults(init, processed.items, options.format);
	if (!options.mute) try skipped.report(init);
	return 0;
}

fn stdout(init: std.process.Init, message: []const u8) !void {
	try std.Io.File.stdout().writeStreamingAll(init.io, message);
}

var stderr_line_start = true;
fn stderr(init: std.process.Init, message: []const u8) !void {
	var rest = message;
	while (rest.len > 0) {
		if (stderr_line_start and !std.mem.startsWith(u8, rest, "glob: ")) try std.Io.File.stderr().writeStreamingAll(init.io, "glob: ");
		const end = if (std.mem.indexOfScalar(u8, rest, '\n')) |at| at + 1 else rest.len;
		try std.Io.File.stderr().writeStreamingAll(init.io, rest[0..end]);
		stderr_line_start = rest[end - 1] == '\n';
		rest = rest[end..];
	}
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
		try std.fmt.bufPrint(&buffer, "glob {s} REV={s} — controlled pathname expansion; PF={s}-{s} VARIANT={s}\n", .{ version, build_identity.revision, os, arch, if (builtin.target.abi.isMusl()) "musl" else "gnu" })
	else
		try std.fmt.bufPrint(&buffer, "glob {s} REV={s} — controlled pathname expansion; PF={s}-{s}\n", .{ version, build_identity.revision, os, arch });
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

const Expansion = struct {
	matches: std.ArrayListUnmanaged([]const u8) = .empty,
};

const SkipReason = enum { hidden, gitignore };
const SkipSummary = struct {
	entries: std.StringHashMapUnmanaged(SkipReason) = .empty,
	hidden: usize = 0,
	gitignored: usize = 0,
	hidden_dirs: usize = 0,
	gitignored_dirs: usize = 0,
	fn record(self: *SkipSummary, init: std.process.Init, absolute: []const u8, reason: SkipReason, pruned: bool) !void {
		if (self.entries.contains(absolute)) return;
		try self.entries.put(init.arena.allocator(), try init.arena.allocator().dupe(u8, absolute), reason);
		switch (reason) {
			.hidden => { self.hidden += 1; if (pruned) self.hidden_dirs += 1; },
			.gitignore => { self.gitignored += 1; if (pruned) self.gitignored_dirs += 1; },
		}
	}
	fn report(self: *const SkipSummary, init: std.process.Init) !void {
		var buffer: [384]u8 = undefined;
		if (self.hidden > 0) try stderr(init, try std.fmt.bufPrint(&buffer, "skipped {d} hidden entries ({d} directory subtrees not scanned); use --hidden, --dotglob or --all to include them; --mute silences this summary.\n", .{ self.hidden, self.hidden_dirs }));
		if (self.gitignored > 0) try stderr(init, try std.fmt.bufPrint(&buffer, "skipped {d} .gitignore entries ({d} directory subtrees not scanned); use --gitignore or --gitignored to include them; --mute silences this summary.\n", .{ self.gitignored, self.gitignored_dirs }));
	}
};

fn expandPattern(init: std.process.Init, source: []const u8, options: Options, filter: *ignore.Filter, skipped: *SkipSummary) !Expansion {
	const compiled = try globlike.compile(init.gpa, source, .{ .case_insensitive = options.ignore_case });
	var pattern = switch (compiled) {
		.diagnostic => |diagnostic| {
			try reportDiagnostic(init, "invalid pattern", diagnostic);
			return error.InvalidPattern;
		},
		.pattern => |value| value,
	};
	defer pattern.deinit();

	const plan = traversalPlan(source, options.ignore_case);
	var directory = (if (std.fs.path.isAbsolute(plan.root))
		std.Io.Dir.openDirAbsolute(init.io, plan.root, .{ .iterate = true })
	else
		std.Io.Dir.cwd().openDir(init.io, plan.root, .{ .iterate = true })) catch |err| {
		if (err == error.FileNotFound or err == error.NotDir) return .{};
		try reportError(init, "cannot open traversal root", err);
		return error.TraversalFailed;
	};
	defer directory.close(init.io);
	const cwd_absolute = try std.Io.Dir.cwd().realPathFileAlloc(init.io, ".", init.gpa);
	defer init.gpa.free(cwd_absolute);
	const root_absolute = try std.fs.path.resolve(init.gpa, &.{ cwd_absolute, plan.root });
	defer init.gpa.free(root_absolute);
	if (!options.include_gitignored) {
		if (try filter.excludedRoot(init, root_absolute)) |excluded| {
			try skipped.record(init, excluded, .gitignore, true);
			return .{};
		}
	}
	var walker = try directory.walkSelectively(init.gpa);
	defer walker.deinit();

	var expansion: Expansion = .{};
	var candidate_buffer: std.ArrayListUnmanaged(u8) = .empty;
	defer candidate_buffer.deinit(init.gpa);
	while (walker.next(init.io) catch |err| {
		try reportError(init, "cannot traverse directory", err);
		return error.TraversalFailed;
	}) |entry| {
		if (std.mem.indexOfScalar(u8, entry.path, '\n') != null) continue;
		candidate_buffer.clearRetainingCapacity();
		try candidate_buffer.appendSlice(init.gpa, plan.prefix);
		if (plan.prefix.len > 0 and plan.prefix[plan.prefix.len - 1] != '/') try candidate_buffer.append(init.gpa, '/');
		try candidate_buffer.appendSlice(init.gpa, entry.path);
		const candidate = candidate_buffer.items;
		var can_descend = entry.kind == .directory and (plan.max_depth == null or entry.depth() < plan.max_depth.?);
		const hidden = !options.include_dotfiles and !dotPathAllowed(source, candidate);
		const hidden_descent = can_descend and !options.include_dotfiles and !dotPathAllowedInner(source, candidate, true);
		const absolute = try std.fs.path.join(init.gpa, &.{ root_absolute, entry.path });
		defer init.gpa.free(absolute);
		const gitignored = !hidden and !options.include_gitignored and try filter.isIgnored(init, absolute, entry.kind == .directory);
		if ((hidden or gitignored) and can_descend) {
			try skipped.record(init, absolute, if (hidden) .hidden else .gitignore, true);
			continue;
		}
		const matched = switch (pattern.matches(candidate)) {
			.matched => |matched| matched,
			.diagnostic => |diagnostic| {
				try reportDiagnostic(init, "matching failed", diagnostic);
				return error.InvalidPattern;
			},
		};
		if (hidden_descent) {
			can_descend = false;
			if (!matched) try skipped.record(init, absolute, .hidden, true);
		}
		if (hidden or gitignored) {
			if (matched) try skipped.record(init, absolute, if (hidden) .hidden else .gitignore, false);
			continue;
		}
		if (matched) try expansion.matches.append(init.arena.allocator(), try init.arena.allocator().dupe(u8, candidate));
		if (can_descend) walker.enter(init.io, entry) catch |err| {
			try reportError(init, "cannot traverse directory", err);
			return error.TraversalFailed;
		};
	}
	return expansion;
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
	return dotPathAllowedInner(pattern, path, false);
}

fn dotPathAllowedInner(pattern: []const u8, path: []const u8, needs_descendant: bool) bool {
	if (!hasHiddenComponent(path)) return true;
	if (std.mem.startsWith(u8, pattern, "regex:") or std.mem.indexOf(u8, pattern, "%r") != null) return false;
	const glob_pattern = if (std.mem.startsWith(u8, pattern, "glob:")) pattern[5..] else pattern;
	return dotComponentsAllowed(trimPathPrefix(glob_pattern), trimPathPrefix(path), needs_descendant);
}

fn dotComponentsAllowed(pattern: []const u8, path: []const u8, needs_descendant: bool) bool {
	if (path.len == 0) return !needs_descendant or pattern.len > 0;
	if (pattern.len == 0) return false;
	const pattern_end = std.mem.indexOfScalar(u8, pattern, '/') orelse pattern.len;
	const path_end = std.mem.indexOfScalar(u8, path, '/') orelse path.len;
	const pattern_component = pattern[0..pattern_end];
	const path_component = path[0..path_end];
	const pattern_rest = trimLeadingSlashes(pattern[pattern_end..]);
	const path_rest = trimLeadingSlashes(path[path_end..]);
	if (std.mem.eql(u8, pattern_component, "**")) {
		if (dotComponentsAllowed(pattern_rest, path, needs_descendant)) return true;
		if (path_component[0] == '.') return false;
		return dotComponentsAllowed(pattern, path_rest, needs_descendant);
	}
	if (path_component[0] == '.' and !std.mem.startsWith(u8, pattern_component, ".")) return false;
	return dotComponentsAllowed(pattern_rest, path_rest, needs_descendant);
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

const TraversalPlan = struct { root: []const u8, prefix: []const u8, max_depth: ?usize };

fn traversalPlan(source: []const u8, case_insensitive: bool) TraversalPlan {
	// This is a conservative filesystem work bound, never a second matcher.
	// Regex fragments, globstar and extglob repetition may consume an
	// unbounded number of separators; globlike still decides every match.
	if (std.mem.startsWith(u8, source, "regex:")) return .{ .root = ".", .prefix = "", .max_depth = null };
	const pattern = if (std.mem.startsWith(u8, source, "glob:")) source[5..] else source;
	const special = std.mem.indexOfAny(u8, pattern, "*?[%{\\+@!(") orelse pattern.len;
	const literal_end = if (case_insensitive) 0 else special;
	const slash = std.mem.lastIndexOfScalar(u8, pattern[0..literal_end], '/');
	const absolute = std.mem.startsWith(u8, pattern, "/");
	const prefix = if (slash) |at| pattern[0..if (at == 0) 1 else at] else if (absolute) "/" else if (std.mem.startsWith(u8, pattern, "./")) "." else "";
	const rest = if (prefix.len > 0) std.mem.trimStart(u8, pattern[prefix.len..], "/") else pattern;
	const recursive = std.mem.indexOf(u8, pattern, "**") != null or
		std.mem.indexOfScalar(u8, pattern, '%') != null or
		(std.mem.indexOfScalar(u8, rest, '(') != null and std.mem.indexOfScalar(u8, rest, '/') != null);
	return .{
		.root = if (prefix.len == 0) "." else prefix,
		.prefix = prefix,
		.max_depth = if (recursive) null else std.mem.countScalar(u8, rest, '/') + 1,
	};
}
