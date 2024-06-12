const std = @import("std");
const core = @import("../core/root.zig");
const DimensionsU32 = core.DimensionsU32;
const PointU32 = core.PointU32;

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

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
    pub const VTable = struct {
        toRgba: *const fn (ctx: *const anyopaque, color: Color) Color,
        fromRgba: *const fn (ctx: *const anyopaque, color: Color) Color,
    };

    ctx: *const anyopaque,
    vtable: *const VTable,

    pub fn toRgba(self: *const @This(), color: Color) Color {
        return self.vtable.toRgba(self.ctx, color);
    }

    pub fn fromRgba(self: *const @This(), color: Color) Color {
        return self.vtable.fromRgba(self.ctx, color);
    }
};

pub const RgbaColorCodec = struct {
    pub const ColorCodecVTable: *const ColorCodec.VTable = &ColorCodecFunctions{};

    pub fn toRgba(color: Color) Color {
        return color;
    }

    pub fn fromRgba(color: Color) Color {
        return color;
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
    pub const DEFAULT_GAMMA: f32 = 2.4;
    pub const DEFAULT: SrgbaColorCodec = SrgbaColorCodec.create(DEFAULT_GAMMA);
    pub const ColorCodecVTable: *const ColorCodec.VTable = &ColorCodecFunctions{};

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

    pub fn toLinear(self: *const @This(), component: f32) u8 {
        return std.math.pow(component, self.gamma);
    }

    pub fn fromLinear(self: *const @This(), component: f32) u8 {
        return std.math.pow(component, self.inverse_gamma);
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
    pub const VTable = struct {
        write: *const fn (ctx: *const anyopaque, color: Color, bytes: []u8) void,
        read: *const fn (ctx: *const anyopaque, bytes: []const u8) Color,
    };

    ctx: *const anyopaque,
    vtable: *const VTable,

    pub fn write(self: *const @This(), color: Color, bytes: []u8) void {
        self.vtable.write(self.ctx, color, bytes);
    }

    pub fn read(self: *const @This(), bytes: []const u8) Color {
        return self.vtable.read(self.ctx, bytes);
    }
};

pub const RgbaU8TextureCodec = struct {
    const COLOR_BYTES: u32 = 4;
    const TextureCodecVTable: *const TextureCodec.VTable = &TextureCodecFunctions{};

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

pub const TextureFormat = struct {
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
    dimensions: DimensionsU32,
    bytes: []u8,
    format: *const TextureFormat,

    pub fn getDimensions(self: @This()) DimensionsU32 {
        return self.dimensions;
    }

    pub fn getBytes(self: @This()) []u8 {
        return self.bytes;
    }

    pub fn getPixel(self: @This(), point: PointU32) ?Color {
        if (point.x < self.dimensions.width and point.y < self.dimensions.height) {
            const index = (point.x * self.format.color_bytes) + (self.dimensions.width * self.format.color_bytes * point.y);
            return self.format.read(self.bytes[index..index + self.format.color_bytes]);
        }

        return null;
    }

    pub fn setPixel(self: *@This(), point: PointU32, color: Color) bool {
        if (point.x < self.dimensions.width and point.y < self.dimensions.height) {
            const index = (point.x * self.format.color_bytes) + (self.dimensions.width * self.format.color_bytes * point.y);
            self.format.write(color, self.bytes[index..index + self.format.color_bytes]);
            return true;
        }

        return false;
    }
};
