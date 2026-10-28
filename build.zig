const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default: ReleaseFast)") orelse .ReleaseFast;
	const globlike = b.dependency("globlike", .{ .target = target, .optimize = optimize });
	const engine = b.addExecutable(.{
		.name = "glob-engine",
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/engine.zig"),
			.target = target,
			.optimize = optimize,
			.imports = &.{.{ .name = "globlike", .module = globlike.module("globlike") }},
		}),
	});
	b.installArtifact(engine);
}
