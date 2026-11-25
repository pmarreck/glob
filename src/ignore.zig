//! .gitignore file/scoping adapter. All wildcard matching remains in globlike.
const std = @import("std");
const globlike = @import("globlike");

const Rule = struct {
	pattern: globlike.Pattern,
	negated: bool,
	directory_only: bool,
	basename_only: bool,
};
const Context = struct {
	base: []const u8,
	parent: ?*Context,
	rules: []Rule,
};

pub const Filter = struct {
	contexts: std.StringHashMapUnmanaged(*Context) = .empty,

	pub fn deinit(self: *Filter) void {
		var iterator = self.contexts.valueIterator();
		while (iterator.next()) |ctx| for (ctx.*.rules) |*rule| rule.pattern.deinit();
	}

	fn context(self: *Filter, init: std.process.Init, base: []const u8) anyerror!*Context {
		if (self.contexts.get(base)) |cached| return cached;
		const arena = init.arena.allocator();
		const owned_base = try arena.dupe(u8, base);
		const ctx = try arena.create(Context);
		const marker = try std.fs.path.join(arena, &.{ base, ".git" });
		const repository_root = blk: {
			_ = std.Io.Dir.cwd().statFile(init.io, marker, .{}) catch break :blk false;
			break :blk true;
		};
		const parent = if (!repository_root) if (std.fs.path.dirname(base)) |dir| try self.context(init, dir) else null else null;
		ctx.* = .{ .base = owned_base, .parent = parent, .rules = &.{} };
		try self.contexts.put(arena, owned_base, ctx);
		const path = try std.fs.path.join(arena, &.{ base, ".gitignore" });
		const stat = std.Io.Dir.cwd().statFile(init.io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
			error.FileNotFound, error.NotDir => return ctx,
			else => return err,
		};
		// Git does not read symlinked ignore files. Never open a FIFO/device here.
		if (stat.kind != .file) return ctx;
		const contents = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(4 * 1024 * 1024));
		defer init.gpa.free(contents);
		var rules: std.ArrayListUnmanaged(Rule) = .empty;
		var lines = std.mem.splitScalar(u8, contents, '\n');
		while (lines.next()) |raw| {
			var line = std.mem.trimEnd(u8, raw, "\r");
			while (line.len > 0 and line[line.len - 1] == ' ') {
				var backslashes: usize = 0;
				var at = line.len - 1;
				while (at > 0 and line[at - 1] == '\\') : (at -= 1) backslashes += 1;
				if (backslashes % 2 == 1) break;
				line = line[0 .. line.len - 1];
			}
			if (line.len == 0 or line[0] == '#') continue;
			const negated = line[0] == '!';
			if (negated) line = line[1..];
			if (line.len == 0) continue;
			const directory_only = line[line.len - 1] == '/';
			if (directory_only) line = line[0 .. line.len - 1];
			const anchored = std.mem.startsWith(u8, line, "/");
			if (anchored) line = line[1..];
			if (line.len == 0) continue;
			const basename_only = !anchored and std.mem.indexOfScalar(u8, line, '/') == null;
			const source = try gitGlobSource(arena, line);
			if (source == null) continue; // A dangling escape never matches in Git.
			const compiled = try globlike.compile(init.gpa, source.?, .{});
			switch (compiled) {
				.pattern => |pattern| try rules.append(arena, .{ .pattern = pattern, .negated = negated, .directory_only = directory_only, .basename_only = basename_only }),
				.diagnostic => {}, // Invalid ignore patterns never match.
			}
		}
		ctx.rules = rules.items;
		return ctx;
	}

	fn matches(ctx: *Context, path: []const u8, is_directory: bool) anyerror!bool {
		var ignored = if (ctx.parent) |parent| try matches(parent, path, is_directory) else false;
		const offset = if (std.mem.eql(u8, ctx.base, "/")) 1 else ctx.base.len + 1;
		if (path.len < offset) return ignored;
		const relative = path[offset..];
		for (ctx.rules) |*rule| {
			if (rule.directory_only and !is_directory) continue;
			const subject = if (rule.basename_only) std.fs.path.basename(relative) else relative;
			switch (rule.pattern.matches(subject)) {
				.matched => |matched| if (matched) { ignored = !rule.negated; },
				.diagnostic => return error.IgnoreMatchFailed,
			}
		}
		return ignored;
	}

	pub fn isIgnored(self: *Filter, init: std.process.Init, absolute: []const u8, is_directory: bool) !bool {
		const parent = std.fs.path.dirname(absolute) orelse return false;
		return matches(try self.context(init, parent), absolute, is_directory);
	}

	/// A literal traversal root must not bypass an excluded ancestor directory.
	/// Return the first pruned frontier, without opening any of its contents.
	pub fn excludedRoot(self: *Filter, init: std.process.Init, absolute: []const u8) !?[]const u8 {
		var boundary: usize = 0;
		var ancestor: ?[]const u8 = absolute;
		while (ancestor) |base| {
			const marker = try std.fs.path.join(init.arena.allocator(), &.{ base, ".git" });
			const repository_root = blk: {
				_ = std.Io.Dir.cwd().statFile(init.io, marker, .{}) catch break :blk false;
				break :blk true;
			};
			if (repository_root) { boundary = base.len; break; }
			ancestor = std.fs.path.dirname(base);
		}
		var end: usize = if (boundary > 0) boundary + 1 else 1;
		while (end < absolute.len) : (end += 1) {
			if (absolute[end] == '/' and try self.isIgnored(init, absolute[0..end], true)) return absolute[0..end];
		}
		if (absolute.len > @max(1, boundary) and try self.isIgnored(init, absolute, true)) return absolute;
		return null;
	}
};

/// Git rule syntax is narrower than the public CLI's globlike syntax. Quote
/// its literal regex/extglob markers and normalize non-component star runs;
/// globlike remains the compiler and matcher, including classes and globstar.
fn gitGlobSource(allocator: std.mem.Allocator, line: []const u8) !?[]const u8 {
	var source: std.ArrayListUnmanaged(u8) = .empty;
	try source.appendSlice(allocator, "glob:");
	var at: usize = 0;
	while (at < line.len) {
		const byte = line[at];
		if (byte == '\\') {
			if (at + 1 == line.len) return null;
			try source.appendSlice(allocator, line[at .. at + 2]);
			at += 2;
		} else if (byte == '*') {
			var end = at + 1;
			while (end < line.len and line[end] == '*') : (end += 1) {}
			const globstar = end - at == 2 and (at == 0 or line[at - 1] == '/') and (end == line.len or line[end] == '/');
			try source.appendSlice(allocator, if (globstar) "**" else "*");
			at = end;
		} else {
			if (std.mem.indexOfScalar(u8, "%()|", byte) != null) try source.append(allocator, '\\');
			try source.append(allocator, byte);
			at += 1;
		}
	}
	return source.items;
}
