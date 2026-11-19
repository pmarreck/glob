const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default: ReleaseFast)") orelse .ReleaseFast;
	const globlike = b.dependency("globlike", .{ .target = target, .optimize = optimize });
	const executable = b.addExecutable(.{
		.name = "glob",
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = target,
			.optimize = optimize,
			.imports = &.{.{ .name = "globlike", .module = globlike.module("globlike") }},
		}),
	});
	b.installArtifact(executable);
}
