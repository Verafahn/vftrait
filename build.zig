const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vftrait = b.addModule("vftrait", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vftrait_test = b.addTest(.{ .root_module = vftrait });
    b.installArtifact(vftrait_test);

    const run = b.addRunArtifact(vftrait_test);
    const step = b.step("test", "Run the vftrait tests");
    step.dependOn(&run.step);

    const vftraits = b.addModule("vftraits", .{
        .root_source_file = b.path("src/traits/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vftrait", .module = vftrait },
        },
    });

    const vftraits_test = b.addTest(.{ .root_module = vftraits });
    b.installArtifact(vftraits_test);

    const run_vftraits = b.addRunArtifact(vftraits_test);
    step.dependOn(&run_vftraits.step);
}
