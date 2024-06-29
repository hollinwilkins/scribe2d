const std = @import("std");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const DimensionsU32 = core.DimensionsU32;
const PointU32 = core.PointU32;

pub const Color = struct {
    pub const BLACK: Color = Color{.r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0};
    pub const RED: Color = Color{.r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0};
    pub const GREEN: Color = Color{.r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0};
    pub const BLUE: Color = Color{.r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0};

    r: f32 = 0.0,
    g: f32 = 0.0,
    b: f32 = 0.0,
    a: f32 = 0.0,

    pub fn lerp(self: @This(), other: @This(), t: f32) @This() {
        return @This(){
            .r = self.r + (other.r - self.r) * t,
            .g = self.r + (other.g - self.g) * t,
            .b = self.r + (other.b - self.b) * t,
            .a = self.r + (other.a - self.a) * t,
        };
    }
};

pub const ColorFormat = enum(u8) {
    rgba,
    srgba,
};

pub const ColorCodec = struct {
    pub const Rgba: ColorCodec = RgbaColorCodec.INSTANCE.colorCodec();
    pub const Srgba: ColorCodec = SrgbaColorCodec.INSTANCE.colorCodec();

    ctx: *const anyopaque,
    vtable: *const VTable,

    pub fn toRgba(self: *const @This(), color: Color) Color {
        return self.vtable.toRgba(self.ctx, color);
    }

    pub fn fromRgba(self: *const @This(), color: Color) Color {
        return self.vtable.fromRgba(self.ctx, color);
    }

    pub const VTable = struct {
        toRgba: *const fn (ctx: *const anyopaque, color: Color) Color,
        fromRgba: *const fn (ctx: *const anyopaque, color: Color) Color,
    };
};

pub const RgbaColorCodec = struct {
    pub const INSTANCE: *const RgbaColorCodec = &RgbaColorCodec{};
    pub const ColorCodecVTable: *const ColorCodec.VTable = &ColorCodec.VTable{
        .fromRgba = ColorCodecFunctions.fromRgba,
        .toRgba = ColorCodecFunctions.toRgba,
    };

    pub fn toRgba(color: Color) Color {
        return color;
    }

    pub fn fromRgba(color: Color) Color {
        return color;
    }

    pub fn colorCodec(self: *const @This()) ColorCodec {
        return ColorCodec {
            .ctx = @ptrCast(self),
            .vtable = ColorCodecVTable,
        };
    }

    const ColorCodecFunctions = struct {
        pub fn toRgba(_: *const anyopaque, color: Color) Color {
            return color;
        }

        pub fn fromRgba(_: *const anyopaque, color: Color) Color {
            return color;
        }
    };
};

pub const SrgbaColorCodec = struct {
    pub const INSTANCE: *const SrgbaColorCodec = &SrgbaColorCodec.create(DEFAULT_GAMMA);
    pub const DEFAULT_GAMMA: f32 = 2.4;
    pub const DEFAULT: SrgbaColorCodec = SrgbaColorCodec.create(DEFAULT_GAMMA);
    pub const ColorCodecVTable: *const ColorCodec.VTable = &ColorCodec.VTable{
        .fromRgba = ColorCodecFunctions.fromRgba,
        .toRgba = ColorCodecFunctions.toRgba,
    };

    gamma: f32,
    inverse_gamma: f32,

    pub fn create(gamma: f32) SrgbaColorCodec {
        return SrgbaColorCodec{
            .gamma = gamma,
            .inverse_gamma = 1.0 / gamma,
        };
    }

    pub fn toRgba(self: *const @This(), color: Color) Color {
        return Color{
            .r = self.toLinear(color.r),
            .g = self.toLinear(color.g),
            .b = self.toLinear(color.b),
            .a = self.toLinear(color.a),
        };
    }

    pub fn fromRgba(self: *const @This(), color: Color) Color {
        return Color{
            .r = self.fromLinear(color.r),
            .g = self.fromLinear(color.g),
            .b = self.fromLinear(color.b),
            .a = self.fromLinear(color.a),
        };
    }

    pub fn toLinear(self: *const @This(), component: f32) f32 {
        return std.math.pow(f32, component, self.gamma);
    }

    pub fn fromLinear(self: *const @This(), component: f32) f32 {
        return std.math.pow(f32, component, self.inverse_gamma);
    }

    pub fn colorCodec(self: *const @This()) ColorCodec {
        return ColorCodec{
            .ctx = @ptrCast(self),
            .vtable = ColorCodecVTable,
        };
    }

    const ColorCodecFunctions = struct {
        pub fn toRgba(ctx: *const anyopaque, color: Color) Color {
            const cc: *const SrgbaColorCodec = @ptrCast(@alignCast(ctx));
            return cc.toRgba(color);
        }

        pub fn fromRgba(ctx: *const anyopaque, color: Color) Color {
            const cc: *const SrgbaColorCodec = @ptrCast(@alignCast(ctx));
            return cc.fromRgba(color);
        }
    };
};

pub const TextureCodec = struct {
    pub const RgbaU8: TextureCodec = RgbaU8TextureCodec.INSTANCE.textureCodec();
    pub const RgbU8: TextureCodec = RgbU8TextureCodec.INSTANCE.textureCodec();

    ctx: *const anyopaque,
    vtable: *const VTable,

    pub fn write(self: *const @This(), color: Color, bytes: []u8) void {
        self.vtable.write(self.ctx, color, bytes);
    }

    pub fn read(self: *const @This(), bytes: []const u8) Color {
        return self.vtable.read(self.ctx, bytes);
    }

    pub const VTable = struct {
        write: *const fn (ctx: *const anyopaque, color: Color, bytes: []u8) void,
        read: *const fn (ctx: *const anyopaque, bytes: []const u8) Color,
    };

};

pub const RgbaU8TextureCodec = struct {
    pub const INSTANCE: *const RgbaU8TextureCodec = &RgbaU8TextureCodec{};
    const COLOR_BYTES: u32 = 4;
    const TextureCodecVTable: *const TextureCodec.VTable = &TextureCodec.VTable{
        .read = TextureCodecFunctions.read,
        .write = TextureCodecFunctions.write,
    };

    pub fn write(color: Color, bytes: []u8) void {
        std.debug.assert(bytes.len == COLOR_BYTES);

        bytes[0] = @intFromFloat(color.r * @as(f32, @floatFromInt(std.math.maxInt(u8))));
        bytes[1] = @intFromFloat(color.g * @as(f32, @floatFromInt(std.math.maxInt(u8))));
        bytes[2] = @intFromFloat(color.b * @as(f32, @floatFromInt(std.math.maxInt(u8))));
        bytes[3] = @intFromFloat(color.a * @as(f32, @floatFromInt(std.math.maxInt(u8))));
    }

    pub fn read(bytes: []const u8) Color {
        std.debug.assert(bytes.len == COLOR_BYTES);

        return Color {
            .r = @as(f32, @floatFromInt(bytes[0])) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
            .g = @as(f32, @floatFromInt(bytes[1])) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
            .b = @as(f32, @floatFromInt(bytes[2])) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
            .a = @as(f32, @floatFromInt(bytes[3])) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
        };
    }

    pub fn textureCodec(self: *const @This()) TextureCodec {
        return TextureCodec{
            .ctx = @ptrCast(self),
            .vtable = TextureCodecVTable,
        };
    }

    const TextureCodecFunctions = struct {
        fn write(_: *const anyopaque, color: Color, bytes: []u8) void {
            RgbaU8TextureCodec.write(color, bytes);
        }

        fn read(_: *const anyopaque, bytes: []const u8) Color {
            return RgbaU8TextureCodec.read(bytes);
        }
    };
};

pub const RgbU8TextureCodec = struct {
    pub const INSTANCE: *const RgbU8TextureCodec = &RgbU8TextureCodec{};
    const COLOR_BYTES: u32 = 3;
    const TextureCodecVTable: *const TextureCodec.VTable = &TextureCodec.VTable{
        .read = TextureCodecFunctions.read,
        .write = TextureCodecFunctions.write,
    };

    pub fn write(color: Color, bytes: []u8) void {
        std.debug.assert(bytes.len == COLOR_BYTES);

        bytes[0] = @intFromFloat(color.r * @as(f32, @floatFromInt(std.math.maxInt(u8))));
        bytes[1] = @intFromFloat(color.g * @as(f32, @floatFromInt(std.math.maxInt(u8))));
        bytes[2] = @intFromFloat(color.b * @as(f32, @floatFromInt(std.math.maxInt(u8))));
    }

    pub fn read(bytes: []const u8) Color {
        std.debug.assert(bytes.len == COLOR_BYTES);

        return Color {
            .r = @as(f32, @floatFromInt(bytes[0])) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
            .g = @as(f32, @floatFromInt(bytes[1])) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
            .b = @as(f32, @floatFromInt(bytes[2])) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
            .a = 1.0,
        };
    }

    pub fn textureCodec(self: *const @This()) TextureCodec {
        return TextureCodec{
            .ctx = @ptrCast(self),
            .vtable = TextureCodecVTable,
        };
    }

    const TextureCodecFunctions = struct {
        fn write(_: *const anyopaque, color: Color, bytes: []u8) void {
            RgbU8TextureCodec.write(color, bytes);
        }

        fn read(_: *const anyopaque, bytes: []const u8) Color {
            return RgbU8TextureCodec.read(bytes);
        }
    };
};

pub const ColorBlend = struct {
    pub const Alpha: ColorBlend = AlphaColorBlend.INSTANCE.colorBlend();
    pub const Replace: ColorBlend = ReplaceColorBlend.INSTANCE.colorBlend();

    ctx: *const anyopaque,
    vtable: *const VTable,

    pub fn blend(self: ColorBlend, color1: Color, color2: Color) Color {
        return self.vtable.blend(self.ctx, color1, color2);
    }

    pub const VTable = struct {
        blend: *const fn (ctx: *const anyopaque, color1: Color, color2: Color) Color,
    };
};

pub const ReplaceColorBlend = struct {
    pub const INSTANCE: *const ReplaceColorBlend = &ReplaceColorBlend{};
    const ColorBlendVTable: *const ColorBlend.VTable = &ColorBlend.VTable{
        .blend = ColorBlendFunctions.blend,
    };

    pub fn blend(color1: Color, _: Color) Color {
        return color1;
    }

    pub fn colorBlend(self: *const ReplaceColorBlend) ColorBlend {
        return ColorBlend{
            .ctx = @ptrCast(self),
            .vtable = ColorBlendVTable,
        };
    }

    const ColorBlendFunctions = struct {
        fn blend(_: *const anyopaque, color1: Color, color2: Color) Color {
            return ReplaceColorBlend.blend(color1, color2);
        }
    };
};

pub const AlphaColorBlend = struct {
    pub const INSTANCE: *const AlphaColorBlend = &AlphaColorBlend{};
    const ColorBlendVTable: *const ColorBlend.VTable = &ColorBlend.VTable{
        .blend = ColorBlendFunctions.blend,
    };

    pub fn blend(color1: Color, color2: Color) Color {
        const alpha = (1.0 - color1.a) * color2.a + color1.a;
        const r = ((1.0 - color1.a) * color2.a * color2.r + color1.a * color1.r) / alpha;
        const g = ((1.0 - color1.a) * color2.a * color2.g + color1.a * color1.g) / alpha;
        const b = ((1.0 - color1.a) * color2.a * color2.b + color1.a * color1.b) / alpha;

        return Color{
            .r = r,
            .g = g,
            .b = b,
            .a = alpha,
        };
    }

    pub fn colorBlend(self: *const AlphaColorBlend) ColorBlend {
        return ColorBlend{
            .ctx = @ptrCast(self),
            .vtable = ColorBlendVTable,
        };
    }

    const ColorBlendFunctions = struct {
        fn blend(_: *const anyopaque, color1: Color, color2: Color) Color {
            return AlphaColorBlend.blend(color1, color2);
        }
    };
};

pub const TextureFormat = struct {
    pub const RgbU8: *const @This() = &@This() {
        .color_bytes = 3,
        .codec = TextureCodec.RgbU8,
        .color_codec = ColorCodec.Rgba,
    };
    pub const SrgbU8: *const @This() = &@This() {
        .color_bytes = 3,
        .codec = TextureCodec.RgbU8,
        .color_codec = ColorCodec.Srgba,
    };
    pub const RgbaU8: *const @This() = &@This() {
        .color_bytes = 4,
        .codec = TextureCodec.RgbaU8,
        .color_codec = ColorCodec.Rgba,
    };
    pub const SrgbaU8: *const @This() = &@This() {
        .color_bytes = 4,
        .codec = TextureCodec.RgbaU8,
        .color_codec = ColorCodec.Srgba,
    };

    color_bytes: u8,
    codec: TextureCodec,
    color_codec: ColorCodec,

    pub fn write(self: @This(), color: Color, bytes: []u8) void {
        const rgba_color = self.color_codec.toRgba(color);
        self.codec.write(rgba_color, bytes);
    }

    pub fn read(self: @This(), bytes: []const u8) Color {
        const color = self.codec.read(bytes);
        return self.color_codec.fromRgba(color);
    }
};

pub const Texture = struct {
    allocator: Allocator,
    dimensions: DimensionsU32,
    format: *const TextureFormat,
    bytes: []u8,

    pub fn init(allocator: Allocator, dimensions: DimensionsU32, format: *const TextureFormat) !@This() {
        return @This() {
            .allocator = allocator,
            .dimensions = dimensions,
            .format = format,
            .bytes = try allocator.alloc(u8, dimensions.size() * format.color_bytes),
        };
    }

    pub fn deinit(self: Texture) void {
        self.allocator.free(self.bytes);
    }

    pub fn toUnmanaged(self: Texture) TextureUnmanaged {
        return TextureUnmanaged{
            .dimensions = self.dimensions,
            .format = self.format,
            .bytes = self.bytes,
        };
    }

    pub fn clear(self: *@This(), color: Color) void {
        var unmanaged = self.toUnmanaged();
        unmanaged.clear(color);
    }

    pub fn getDimensions(self: @This()) DimensionsU32 {
        return self.dimensions;
    }

    pub fn getBytes(self: @This()) []u8 {
        return self.bytes;
    }

    pub fn getPixel(self: @This(), point: PointU32) ?Color {
        return self.toUnmanaged().getPixel(point);
    }

    pub fn getPixelUnsafe(self: @This(), point: PointU32) Color {
        return self.toUnmanaged().getPixelUnsafe(point);
    }

    pub fn setPixel(self: *@This(), point: PointU32, color: Color) bool {
        var unmanaged = self.toUnmanaged();
        return unmanaged.setPixel(point, color);
    }

    pub fn setPixelUnsafe(self: *@This(), point: PointU32, color: Color) bool {
        var unmanaged = self.toUnmanaged();
        return unmanaged.setPixelUnsafe(point, color);
    }
};

pub const TextureUnmanaged = struct {
    dimensions: DimensionsU32,
    format: *const TextureFormat,
    bytes: []u8,

    pub fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.bytes);
    }

    pub fn clear(self: *@This(), color: Color) void {
        for (0..self.dimensions.height) |y| {
            for (0..self.dimensions.width) |x| {
                const is_set = self.setPixel(PointU32{
                    .x = @intCast(x),
                    .y = @intCast(y),
                }, color);
                std.debug.assert(is_set);
            }
        }
    }

    pub fn getDimensions(self: @This()) DimensionsU32 {
        return self.dimensions;
    }

    pub fn getBytes(self: @This()) []u8 {
        return self.bytes;
    }

    pub fn getPixel(self: @This(), point: PointU32) ?Color {
        if (point.x < self.dimensions.width and point.y < self.dimensions.height) {
            return self.getPixelUnsafe(point);
        }

        return null;
    }

    pub fn getPixelUnsafe(self: @This(), point: PointU32) Color {
        const index = (point.x * self.format.color_bytes) + (self.dimensions.width * self.format.color_bytes * point.y);
        return self.format.read(self.bytes[index..index + self.format.color_bytes]);
    }

    pub fn setPixel(self: *@This(), point: PointU32, color: Color) bool {
        if (point.x < self.dimensions.width and point.y < self.dimensions.height) {
            self.setPixelUnsafe(point, color);
            return true;
        }

        return false;
    }

    pub fn setPixelUnsafe(self: *@This(), point: PointU32, color: Color) void {
        const index = (point.x * self.format.color_bytes) + (self.dimensions.width * self.format.color_bytes * point.y);
        self.format.write(color, self.bytes[index..index + self.format.color_bytes]);
    }
};
