const std = @import("std");
const text = @import("../root.zig");
const util = @import("../util.zig");
const core = @import("../../core/root.zig");
const loca = @import("./loca.zig");
const TextOutliner = @import("../TextOutliner.zig");
const Error = text.Error;
const GlyphId = text.GlyphId;
const LazyIntArray = util.LazyIntArray;
const RectI16 = core.RectI16;
const PointI16 = core.PointI16;
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const DimensionsF32 = core.DimensionsF32;
const Transform = util.Transform;
const F2DOT14 = util.F2DOT14;
const Reader = util.Reader;

pub const MAX_COMPONENTS: u8 = 32;

pub const Table = struct {
    data: []const u8,
    loca: loca.Table,

    pub fn create(data: []const u8, loca_table: loca.Table) Error!Table {
        return Table{
            .data = data,
            .loca = loca_table,
        };
    }

    pub fn outline(self: Table, glyph_id: GlyphId, outliner: TextOutliner) Error!f64 {
        var builder = Builder.create(RectF32{
            .min = PointF32{
                .x = std.math.floatMax(f32),
                .y = std.math.floatMax(f32),
            },
            .max = PointF32{
                .x = std.math.floatMin(f32),
                .y = std.math.floatMin(f32),
            },
        }, Transform{}, outliner);
        const glyph_data = self.get(glyph_id) orelse return error.InvalidOutline;
        const aspect_ratio = try self.outlineImpl(glyph_data, 0, &builder);
        builder.finish();
        return aspect_ratio;
    }

    pub fn get(self: Table, glyph_id: GlyphId) ?[]const u8 {
        const range = self.loca.glyphRange(glyph_id) orelse return null;
        return self.data[range.start..range.end];
    }

    fn outlineImpl(self: Table, data: []const u8, depth: u8, builder: *Builder) Error!f64 {
        if (depth >= MAX_COMPONENTS) {
            return error.MaxDepthExceeded;
        }

        var reader = Reader.create(data);
        const numberOfContours = reader.readInt(i16) orelse return error.InvalidOutline;
        const bounds = util.readRect(i16, &reader) orelse return error.InvalidOutline;
        _ = bounds;

        if (numberOfContours > 0) {
            // Simple glyph

            const nContours: u16 = @intCast(numberOfContours);
            if (nContours == 0) {
                return error.InvalidOutline;
            }

            if (try parseSimpleOutline(reader.tail(), nContours)) |points_iterator| {
                var points_iterator_mut = points_iterator;
                var iter = &points_iterator_mut;
                while (iter.next()) |point| {
                    builder.pushPoint(
                        @as(f32, @floatFromInt(point.x)),
                        @as(f32, @floatFromInt(point.y)),
                        point.on_curve_point,
                        point.last_point,
                    );
                }
            }
        } else if (numberOfContours < 0) {
            // Composite glyph
            var iter = CompositeGlyphInfo.Iterator.create(reader.tail());

            while (iter.next()) |info| {
                if (self.loca.glyphRange(info.glyph_id)) |range| {
                    const glyph_data = self.data[range.start..range.end];
                    const transform = builder.transform.combine(info.transform);
                    var b = Builder.create(builder.bounds, transform, builder.outliner);
                    _ = try self.outlineImpl(glyph_data, depth + 1, &b);

                    // Take updated bounds
                    builder.bounds = b.bounds;
                }
            }
        } else {
            return 0.0;
        }

        // important for left side bearing offsetting
        // if this assertion ever breaks, we will need to return the original bounds.min.x
        // along with aspect ratio for positioning glyphs in a string properly
        // std.debug.assert(builder.bounds.min.x == @as(f32, @floatFromInt(bounds.min.x)));

        return builder.bounds.getAspectRatio();
    }

    fn parseSimpleOutline(glyph_data: []const u8, numberOfContours: u16) Error!?GlyphPoint.Iterator {
        var reader = Reader.create(glyph_data);
        const endpoints = GlyphPoint.EndpointsIterator.EndpointsList.read(&reader, numberOfContours) orelse return error.InvalidOutline;

        const lastPoint = endpoints.last() orelse return error.InvalidOutline;
        const pointsTotal = lastPoint + 1;

        if (pointsTotal == 1) {
            return null;
        }

        // Skip instructions byte code.
        const instructionsLength = reader.readInt(u16) orelse return error.InvalidOutline;
        reader.skipN(@intCast(instructionsLength));

        const flagsOffset = reader.cursor;
        const coordinateLengths = try resolveCoordinatesLength(&reader, pointsTotal);
        const xCoordinatesOffset = reader.cursor;
        const yCoordinatesOffset = xCoordinatesOffset + @as(usize, @intCast(coordinateLengths.x));
        const yCoordinatesEnd = yCoordinatesOffset + @as(usize, @intCast(coordinateLengths.y));

        return GlyphPoint.Iterator{
            .endpoints = GlyphPoint.EndpointsIterator.create(endpoints) orelse return null,
            .flags = GlyphPoint.FlagsIterator.create(glyph_data[flagsOffset..xCoordinatesOffset]),
            .xCoordinates = GlyphPoint.CoordinatesIterator.create(glyph_data[xCoordinatesOffset..yCoordinatesOffset]),
            .yCoordinates = GlyphPoint.CoordinatesIterator.create(glyph_data[yCoordinatesOffset..yCoordinatesEnd]),
            .pointsLeft = pointsTotal,
        };
    }

    fn resolveCoordinatesLength(reader: *Reader, pointsTotal: u16) Error!CoordinatesLength {
        var flagsLeft: u32 = @intCast(pointsTotal);
        var repeats: u32 = 0;
        var xCoordinatesLength: u32 = 0;
        var yCoordinatesLength: u32 = 0;

        while (flagsLeft > 0) {
            const flags = SimpleGlyphFlags.read(reader) orelse return error.InvalidOutline;

            // The number of times a glyph point repeats.
            if (flags.repeatFlag()) {
                const r = reader.readInt(u8) orelse return error.InvalidOutline;
                repeats = @intCast(r);
                repeats += 1;
            } else {
                repeats = 1;
            }

            if (repeats > flagsLeft) {
                return error.InvalidOutline;
            }

            // No need to check for `*_coords_len` overflow since u32 is more than enough.

            // Non-obfuscated code below.
            // Branchless version is surprisingly faster.

            if (flags.xShort()) {
                // Coordinate is 1 byte long.
                xCoordinatesLength += repeats;
            } else if (!flags.xIsSameOrPositiveShort()) {
                // Coordinate is 2 bytes long.
                xCoordinatesLength += repeats * 2;
            }

            if (flags.yShort()) {
                // Coordinate is 1 byte long.
                yCoordinatesLength += repeats;
            } else if (!flags.yIsSameOrPositiveShort()) {
                // Coordinate is 2 bytes long.
                yCoordinatesLength += repeats * 2;
            }

            flagsLeft -= repeats;
        }

        return CoordinatesLength{
            .x = xCoordinatesLength,
            .y = yCoordinatesLength,
        };
    }
};

pub const CoordinatesLength = struct {
    x: u32,
    y: u32,
};

pub const Builder = struct {
    outliner: TextOutliner,
    bounds: RectF32,
    transform: Transform,
    is_default_transform: bool,
    first_on_curve: ?PointF32,
    first_off_curve: ?PointF32,
    last_off_curve: ?PointF32,

    pub fn create(bounds: RectF32, transform: Transform, outliner: TextOutliner) Builder {
        return Builder{
            .outliner = outliner,
            .bounds = bounds,
            .transform = transform,
            .is_default_transform = transform.isDefault(),
            .first_on_curve = null,
            .first_off_curve = null,
            .last_off_curve = null,
        };
    }

    pub fn moveTo(self: *Builder, x: f32, y: f32) void {
        var x_mut = x;
        var y_mut = y;
        if (!self.is_default_transform) {
            self.transform.applyTo(&x_mut, &y_mut);
        }

        self.bounds = self.bounds.extendBy(PointF32{
            .x = x_mut,
            .y = y_mut,
        });
        self.outliner.moveTo(x_mut, y_mut);
    }

    pub fn lineTo(self: *Builder, x: f32, y: f32) void {
        var x_mut = x;
        var y_mut = y;
        if (!self.is_default_transform) {
            self.transform.applyTo(&x_mut, &y_mut);
        }

        self.bounds = self.bounds.extendBy(PointF32{
            .x = x_mut,
            .y = y_mut,
        });
        self.outliner.lineTo(x_mut, y_mut);
    }

    pub fn quadTo(self: *Builder, x1: f32, y1: f32, x: f32, y: f32) void {
        var x1_mut = x1;
        var y1_mut = y1;
        var x_mut = x;
        var y_mut = y;
        if (!self.is_default_transform) {
            self.transform.applyTo(&x1_mut, &y1_mut);
            self.transform.applyTo(&x_mut, &y_mut);
        }

        self.bounds = self.bounds.extendBy(PointF32{
            .x = x1_mut,
            .y = y1_mut,
        }).extendBy(PointF32{
            .x = x_mut,
            .y = y_mut,
        });
        self.outliner.quadTo(x1_mut, y1_mut, x_mut, y_mut);
    }

    pub fn finish(self: *Builder) void {
        self.outliner.finish(self.bounds);
    }

    pub fn pushPoint(self: *Builder, x: f32, y: f32, on_curve_point: bool, last_point: bool) void {
        const p = PointF32{
            .x = x,
            .y = y,
        };

        if (self.first_on_curve == null) {
            if (on_curve_point) {
                self.first_on_curve = p;
                self.moveTo(p.x, p.y);
            } else {
                if (self.first_off_curve) |off_curve| {
                    const mid = off_curve.lerp(p, 0.5);
                    self.first_on_curve = mid;
                    self.last_off_curve = p;
                    self.moveTo(mid.x, mid.y);
                } else {
                    self.first_off_curve = p;
                }
            }
        } else {
            if (self.last_off_curve) |off_curve| {
                if (on_curve_point) {
                    self.last_off_curve = null;
                    self.quadTo(off_curve.x, off_curve.y, p.x, p.y);
                } else {
                    self.last_off_curve = p;
                    const mid = off_curve.lerp(p, 0.5);
                    self.quadTo(off_curve.x, off_curve.y, mid.x, mid.y);
                }
            } else {
                if (on_curve_point) {
                    self.lineTo(p.x, p.y);
                } else {
                    self.last_off_curve = p;
                }
            }
        }

        if (last_point) {
            self.finishContour();
        }
    }

    fn finishContour(self: *Builder) void {
        if (self.first_off_curve) |off_curve1| {
            if (self.last_off_curve) |off_curve2| {
                self.last_off_curve = null;
                const mid = off_curve2.lerp(off_curve1, 0.5);
                self.quadTo(off_curve2.x, off_curve2.y, mid.x, mid.y);
            }
        }

        if (self.first_on_curve) |p| {
            if (self.first_off_curve) |off_curve1| {
                self.quadTo(off_curve1.x, off_curve1.y, p.x, p.y);
            } else if (self.last_off_curve) |off_curve2| {
                self.quadTo(off_curve2.x, off_curve2.y, p.x, p.y);
            } else {
                self.lineTo(p.x, p.y);
            }

            self.first_on_curve = null;
            self.first_off_curve = null;
            self.last_off_curve = null;

            self.outliner.close();
        }
    }
};

pub const CompositeGlyphFlags = struct {
    value: u16,

    pub fn arg_1_and_2_are_words(self: CompositeGlyphFlags) bool {
        return self.value & 0x0001 != 0;
    }

    pub fn args_are_xy_values(self: CompositeGlyphFlags) bool {
        return self.value & 0x0002 != 0;
    }

    pub fn we_have_a_scale(self: CompositeGlyphFlags) bool {
        return self.value & 0x0008 != 0;
    }

    pub fn more_components(self: CompositeGlyphFlags) bool {
        return self.value & 0x0020 != 0;
    }

    pub fn we_have_an_x_and_y_scale(self: CompositeGlyphFlags) bool {
        return self.value & 0x0040 != 0;
    }

    pub fn we_have_a_two_by_two(self: CompositeGlyphFlags) bool {
        return self.value & 0x0080 != 0;
    }

    pub fn read(reader: *Reader) ?CompositeGlyphFlags {
        const value = reader.readInt(u16) orelse return null;

        return CompositeGlyphFlags{
            .value = value,
        };
    }
};

pub const SimpleGlyphFlags = struct {
    value: u8,

    pub fn onCurvePoint(self: SimpleGlyphFlags) bool {
        return self.value & 0x01 != 0;
    }

    pub fn xShort(self: SimpleGlyphFlags) bool {
        return self.value & 0x02 != 0;
    }

    pub fn yShort(self: SimpleGlyphFlags) bool {
        return self.value & 0x04 != 0;
    }

    pub fn repeatFlag(self: SimpleGlyphFlags) bool {
        return self.value & 0x08 != 0;
    }

    pub fn xIsSameOrPositiveShort(self: SimpleGlyphFlags) bool {
        return self.value & 0x10 != 0;
    }

    pub fn yIsSameOrPositiveShort(self: SimpleGlyphFlags) bool {
        return self.value & 0x20 != 0;
    }

    pub fn read(reader: *Reader) ?SimpleGlyphFlags {
        const value = reader.read(u8) orelse return null;
        return SimpleGlyphFlags{
            .value = value,
        };
    }
};

pub const CompositeGlyphInfo = struct {
    glyph_id: GlyphId,
    transform: Transform,
    flags: CompositeGlyphFlags,

    pub const Iterator = struct {
        reader: Reader,

        pub fn create(data: []const u8) Iterator {
            return Iterator{
                .reader = Reader.create(data),
            };
        }

        pub fn next(self: *Iterator) ?CompositeGlyphInfo {
            return CompositeGlyphInfo.read(&self.reader);
        }
    };

    pub fn read(reader: *Reader) ?CompositeGlyphInfo {
        const flags = CompositeGlyphFlags.read(reader) orelse return null;
        const glyph_id = reader.readInt(GlyphId) orelse return null;
        var ts = Transform{};

        if (flags.args_are_xy_values()) {
            if (flags.arg_1_and_2_are_words()) {
                const e = reader.readInt(i16) orelse return null;
                const f = reader.readInt(i16) orelse return null;
                ts.e = @floatFromInt(e);
                ts.f = @floatFromInt(f);
            } else {
                const e = reader.readInt(u8) orelse return null;
                const f = reader.readInt(u8) orelse return null;
                ts.e = @floatFromInt(e);
                ts.f = @floatFromInt(f);
            }
        }

        if (flags.we_have_a_two_by_two()) {
            const a = F2DOT14.read(reader) orelse return null;
            const b = F2DOT14.read(reader) orelse return null;
            const c = F2DOT14.read(reader) orelse return null;
            const d = F2DOT14.read(reader) orelse return null;
            ts.a = a.toF32();
            ts.b = b.toF32();
            ts.c = c.toF32();
            ts.d = d.toF32();
        } else if (flags.we_have_an_x_and_y_scale()) {
            const a = F2DOT14.read(reader) orelse return null;
            const d = F2DOT14.read(reader) orelse return null;
            ts.a = a.toF32();
            ts.d = d.toF32();
        } else if (flags.we_have_a_scale()) {
            const a = F2DOT14.read(reader) orelse return null;
            ts.a = a.toF32();
            ts.d = ts.a;
        }

        if (!flags.more_components()) {
            reader.skipToEnd();
        }

        return CompositeGlyphInfo{
            .glyph_id = glyph_id,
            .transform = ts,
            .flags = flags,
        };
    }
};

pub const GlyphPoint = struct {
    x: i16,
    y: i16,
    on_curve_point: bool,
    last_point: bool,

    pub const Iterator = struct {
        endpoints: EndpointsIterator = EndpointsIterator{},
        flags: FlagsIterator,
        xCoordinates: CoordinatesIterator,
        yCoordinates: CoordinatesIterator,
        pointsLeft: u16,

        pub fn currentContour(self: *const Iterator) u16 {
            return self.endpoints.index - 1;
        }

        pub fn next(self: *Iterator) ?GlyphPoint {
            if (self.pointsLeft == 0) {
                return null;
            }
            self.pointsLeft = self.pointsLeft - 1;

            const flags = self.flags.next() orelse return null;
            const lastPoint = self.endpoints.next();

            return GlyphPoint{
                .x = self.xCoordinates.next(flags.xShort(), flags.xIsSameOrPositiveShort()),
                .y = self.yCoordinates.next(flags.yShort(), flags.yIsSameOrPositiveShort()),
                .on_curve_point = flags.onCurvePoint(),
                .last_point = lastPoint,
            };
        }
    };

    pub const EndpointsIterator = struct {
        const EndpointsList = LazyIntArray(u16);

        endpoints: EndpointsList = EndpointsList{},
        index: u16 = 0,
        left: u16 = 0,

        pub fn create(endpoints: EndpointsList) ?EndpointsIterator {
            const left = endpoints.get(0) orelse return null;

            return EndpointsIterator{
                .endpoints = endpoints,
                .index = 1,
                .left = left,
            };
        }

        pub fn next(self: *EndpointsIterator) bool {
            if (self.left == 0) {
                if (self.endpoints.get(self.index)) |endpoint| {
                    const previous = self.endpoints.get(self.index - 1) orelse 0;
                    self.left = endpoint -| previous;
                    self.left -|= 1;
                }

                self.index += 1;

                return true;
            } else {
                self.left -= 1;
                return false;
            }
        }
    };

    pub const FlagsIterator = struct {
        reader: Reader,
        repeats: u8,
        flags: SimpleGlyphFlags,

        pub fn create(data: []const u8) FlagsIterator {
            return FlagsIterator{
                .reader = Reader.create(data),
                .repeats = 0,
                .flags = SimpleGlyphFlags{
                    .value = 0,
                },
            };
        }

        pub fn next(self: *FlagsIterator) ?SimpleGlyphFlags {
            if (self.repeats == 0) {
                self.flags = SimpleGlyphFlags.read(&self.reader) orelse SimpleGlyphFlags{ .value = 0 };
                if (self.flags.repeatFlag()) {
                    self.repeats = self.reader.readInt(u8) orelse 0;
                }
            } else {
                self.repeats -= 1;
            }

            return self.flags;
        }
    };

    pub const CoordinatesIterator = struct {
        reader: Reader,
        previous: i16,

        pub fn create(data: []const u8) CoordinatesIterator {
            return CoordinatesIterator{
                .reader = Reader.create(data),
                .previous = 0,
            };
        }

        pub fn next(self: *CoordinatesIterator, isShort: bool, isSameOrShort: bool) i16 {
            var n: i16 = 0;

            if (isShort) {
                n = @intCast(self.reader.readInt(u8) orelse 0);
                if (!isSameOrShort) {
                    n = -n;
                }
            } else if (!isSameOrShort) {
                n = self.reader.readInt(i16) orelse 0;
            }

            self.previous = self.previous + n;
            return self.previous;
        }
    };
};
