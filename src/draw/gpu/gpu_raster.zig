const zdawn = @import("zdawn");
const wgpu = zdawn.wgpu;
const GraphicsContext = zdawn.GraphicsContext;

pub const GpuRasterizer = struct {
    gctx: *GraphicsContext,
};
