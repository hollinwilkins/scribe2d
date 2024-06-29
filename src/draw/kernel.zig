const f32x3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

const f32x4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

export fn test_color(color: f32x3, out_color: *f32x4) void {
    out_color.* = f32x4{
        .x = color.x,
        .y = color.y,
        .z = color.z,
        .w = 1.0,
    };
}

export fn saxpy(y: [*]addrspace(.global) f32, x: [*]addrspace(.global) const f32, a: f32) callconv(.Kernel) void {
    const gid = @workGroupId(0) * @workGroupSize(0) + @workItemId(0);
    y[gid] += x[gid] * a;
}
