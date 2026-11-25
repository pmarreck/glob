const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default: ReleaseFast)") orelse .ReleaseFast;
	const globlike = b.dependency("globlike", .{ .target = target, .optimize = optimize });
	const identity = b.addOptions();
	identity.addOption([]const u8, "revision", b.option([]const u8, "build-revision", "Git-derived build revision") orelse "unavailable");
	const executable = b.addExecutable(.{
		.name = "glob",
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = target,
			.optimize = optimize,
			.imports = &.{.{ .name = "globlike", .module = globlike.module("globlike") }},
		}),
	});
	executable.root_module.addOptions("build_identity", identity);
	b.installArtifact(executable);
}
