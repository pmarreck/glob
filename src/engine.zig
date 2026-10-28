const std = @import("std");
const globlike = @import("globlike");

const Exit = struct {
	const usage: u8 = 2;
	const runtime: u8 = 2;
};

pub fn main(init: std.process.Init) !u8 {
	var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
	defer args.deinit();
	_ = args.next();

	var case_insensitive = false;
	var dotglob = false;
	var pattern_source: ?[]const u8 = null;
	while (args.next()) |arg| {
		if (std.mem.eql(u8, arg, "--ignore-case")) {
			case_insensitive = true;
		} else if (std.mem.eql(u8, arg, "--dotglob")) {
			dotglob = true;
		} else if (pattern_source == null) {
			pattern_source = arg;
		} else {
			try stderr(init, "glob-engine: expected one pattern\n");
			return Exit.usage;
		}
	}

	const source = pattern_source orelse {
		try stderr(init, "glob-engine: missing pattern\n");
		return Exit.usage;
	};
	const compiled = try globlike.compile(init.gpa, source, .{ .case_insensitive = case_insensitive });
	var pattern = switch (compiled) {
		.diagnostic => |diagnostic| {
			try reportDiagnostic(init, "invalid pattern", diagnostic);
			return Exit.usage;
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
		try reportError(init, "cannot open current directory", err);
		return Exit.runtime;
	};
	defer directory.close(init.io);
	var walker = try directory.walk(init.gpa);
	defer walker.deinit();

	const explicit_current = std.mem.startsWith(u8, source, "./");
	while (walker.next(init.io) catch |err| {
		try reportError(init, "cannot traverse current directory", err);
		return Exit.runtime;
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
			entry.path;
		if (!dotglob and !dotPathAllowed(source, candidate)) continue;
		switch (pattern.matches(candidate)) {
			.matched => |matched| if (matched) {
				try std.Io.File.stdout().writeStreamingAll(init.io, candidate);
				try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
			},
			.diagnostic => |diagnostic| {
				try reportDiagnostic(init, "matching failed", diagnostic);
				return Exit.runtime;
			},
		}
	}
	return 0;
}

fn stderr(init: std.process.Init, message: []const u8) !void {
	try std.Io.File.stderr().writeStreamingAll(init.io, message);
}

fn reportError(init: std.process.Init, context: []const u8, err: anyerror) !void {
	var buffer: [512]u8 = undefined;
	const message = try std.fmt.bufPrint(&buffer, "glob-engine: {s}: {t}\n", .{ context, err });
	try stderr(init, message);
}

fn reportDiagnostic(init: std.process.Init, context: []const u8, diagnostic: globlike.Diagnostic) !void {
	var diagnostic_buffer: [512]u8 = undefined;
	const detail = diagnostic.message(&diagnostic_buffer);
	var message_buffer: [768]u8 = undefined;
	const message = if (diagnostic.offset) |offset|
		try std.fmt.bufPrint(&message_buffer, "glob-engine: {s} at byte {d}: {s}\n", .{ context, offset, detail })
	else
		try std.fmt.bufPrint(&message_buffer, "glob-engine: {s}: {s}\n", .{ context, detail });
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
	while (parts.next()) |part| {
		if (part.len > 1 and part[0] == '.' and !std.mem.eql(u8, part, "..")) return true;
	}
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
