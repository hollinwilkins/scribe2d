const std = @import("std");
const xml = @import("./xml/mod.zig");
const core = @import("../core/root.zig");
const draw = @import("../draw/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const GenericReader = std.io.GenericReader;
const PointF32 = core.PointF32;
const RectF32 = core.RectF32;
const TransformF32 = core.TransformF32;
const Encoder = draw.Encoder;
const PathEncoderF32 = draw.PathEncoderF32;
const ColorU8 = draw.ColorU8;
const Style = draw.Style;

pub const Svg = struct {
    pub const EncodeError = error{
        OutOfMemory,
    };

    viewbox: RectF32,
    doc: xml.Document,

    pub fn parseFileAlloc(allocator: Allocator, path: []const u8) !Svg {
        const absolute_path = try std.fs.realpathAlloc(allocator, path);
        defer allocator.free(absolute_path);

        var file = try std.fs.openFileAbsolute(absolute_path, std.fs.File.OpenFlags{});
        defer file.close();

        var doc = try xml.parse(allocator, path, file.reader());
        errdefer doc.deinit();

        doc.acquire();
        defer doc.release();

        std.debug.print("Parsed document: {s}...\n", .{doc.root.tag_name.slice()});

        var viewbox_iter = std.mem.splitSequence(u8, doc.root.attr("viewBox").?, " ");
        var dims: [4]f32 = undefined;
        var i: u32 = 0;
        while (viewbox_iter.next()) |dim| {
            dims[i] = try std.fmt.parseFloat(f32, dim);
            i += 1;
        }
        const viewbox = RectF32{
            .min = PointF32{
                .x = dims[0],
                .y = dims[1],
            },
            .max = PointF32{
                .x = dims[2],
                .y = dims[3],
            },
        };
        std.debug.print("Parsed viewport: {}...\n", .{viewbox});

        return Svg{
            .viewbox = viewbox,
            .doc = doc,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.doc.deinit();
    }

    pub fn encode(self: *@This(), encoder: *Encoder) EncodeError!void {
        self.doc.acquire();
        defer self.doc.release();
        const root = self.doc.root;

        for (root.children()) |child| {
            try encodeNode(encoder, child);
        }
    }

    pub fn encodeNode(encoder: *Encoder, node: xml.NodeIndex) EncodeError!void {
        switch (node.v()) {
            .element => |el| {
                try encodeElement(encoder, el);
            },
            else => {
                // skip
            },
        }
    }

    pub fn encodeElement(encoder: *Encoder, el: xml.Element) !void {
        if (std.mem.eql(u8, el.tag_name.slice(), "g")) {
            try encodeGroupEl(encoder, el);
        } else if (std.mem.eql(u8, el.tag_name.slice(), "path")) {
            try encodePathEl(encoder, el);
        }
    }

    pub fn encodeGroupEl(encoder: *Encoder, group: xml.Element) !void {
        if (group.attr("transform")) |transform_str| {
            try encoder.encodeTransform(parseTransform(transform_str));
        }

        var style: ?Style = null;

        fill: {
            if (group.attr("fill")) |fill| {
                if (std.mem.eql(u8, fill, "none")) {
                    break :fill;
                }

                const color = parseColor(fill);
                try encoder.encodeColor(color);

                style = if (style == null) Style{} else style;
                style.?.setFill(Style.Fill{
                    .brush = .color,
                });
            }
        }

        stroke: {
            if (group.attr("stroke")) |stroke| {
                if (std.mem.eql(u8, stroke, "none")) {
                    break :stroke;
                }

                const color = parseColor(stroke);
                try encoder.encodeColor(color);

                style = if (style == null) Style{} else style;
                style.?.setStroke(Style.Stroke{
                    .brush = .color,
                    .join = .bevel,
                    .start_cap = .butt,
                    .end_cap = .butt,
                });
            }
        }

        if (group.attr("stroke-width")) |stroke_width_str| {
            const stroke_width = std.fmt.parseFloat(f32, stroke_width_str) catch @panic("invalid stroke-width");
            if (style) |*s| {
                s.stroke.width = stroke_width;
            }
        }

        if (style) |s| {
            try encoder.encodeStyle(s);
        }

        for (group.children()) |child| {
            try encodeNode(encoder, child);
        }
    }

    pub fn encodePathEl(encoder: *Encoder, path_el: xml.Element) !void {
        var style: ?Style = null;

        if (path_el.attr("fill")) |fill| {
            const color = parseColor(fill);
            try encoder.encodeColor(color);

            style = if (style == null) Style{} else style;
            style.?.setFill(Style.Fill{
                .brush = .color,
            });
        }

        stroke: {
            if (path_el.attr("stroke")) |stroke| {
                if (std.mem.eql(u8, stroke, "none")) {
                    break :stroke;
                }
                const color = parseColor(stroke);
                try encoder.encodeColor(color);

                style = if (style == null) Style{} else style;
                style.?.setStroke(Style.Stroke{
                    .brush = .color,
                    .join = .bevel,
                    .start_cap = .butt,
                    .end_cap = .butt,
                });
            }
        }

        if (path_el.attr("stroke-width")) |stroke_width_str| {
            const stroke_width = std.fmt.parseFloat(f32, stroke_width_str) catch @panic("invalid stroke-width");
            if (style) |*s| {
                s.stroke.width = stroke_width;
            }
        }

        if (style) |s| {
            try encoder.encodeStyle(s);
        }

        if (path_el.attr("d")) |path| {
            var path_encoder = encoder.pathEncoder(f32);

            var path_parser = PathParser.create(path, &path_encoder);
            try path_parser.encode();

            try path_encoder.finish();
        }
    }

    fn parseTransform(value: []const u8) TransformF32.Affine {
        var parser = Parser.create(value);
        const id = parser.readIdentifier() orelse @panic("invalid transform");

        var transform: TransformF32 = TransformF32{};
        if (std.mem.eql(u8, id, "translate")) {
            _ = parser.readExpected('(');
            const x = parser.readF32() orelse @panic("invalid translate");
            parser.skipWhitespace();
            _ = parser.readExpected(',');
            parser.skipWhitespace();
            const y = parser.readF32() orelse @panic("invalid translate");
            transform.translate = PointF32{
                .x = x,
                .y = y,
            };
            _ = parser.readExpected(')');
            return transform.toAffine();
        } else if (std.mem.eql(u8, id, "matrix")) {
            _ = parser.readExpected('(');
            const a = parser.readF32() orelse @panic("invalid matrix");
            const b = parser.readF32() orelse @panic("invalid matrix");
            const c = parser.readF32() orelse @panic("invalid matrix");
            const d = parser.readF32() orelse @panic("invalid matrix");
            const e = parser.readF32() orelse @panic("invalid matrix");
            const f = parser.readF32() orelse @panic("invalid matrix");
            _ = parser.readExpected(')');

            const affine = TransformF32.Affine{
                .coefficients = [6]f32{
                    a, c, e,
                    b, d, f,
                },
            };

            std.debug.print("TRANSFORM SCALE: {}\n", .{affine.getScale()});
            return affine;
        }

        return transform.toAffine();
    }

    fn parseColor(value: []const u8) ColorU8 {
        var parser = Parser.create(value);

        const next_byte = parser.peekByte() orelse @panic("invalid color");

        switch (next_byte) {
            '#' => {
                _ = parser.readByte();

                if (parser.readHex()) |hex| {
                    var r: u8 = undefined;
                    var g: u8 = undefined;
                    var b: u8 = undefined;

                    if (hex.len == 3) {
                        r = std.fmt.parseInt(u8, &[2]u8{ hex[0], hex[0] }, 16) catch @panic("invalid color");
                        g = std.fmt.parseInt(u8, &[2]u8{ hex[1], hex[1] }, 16) catch @panic("invalid color");
                        b = std.fmt.parseInt(u8, &[2]u8{ hex[2], hex[2] }, 16) catch @panic("invalid color");
                    } else if (hex.len == 6) {
                        r = std.fmt.parseInt(u8, hex[0..2], 16) catch @panic("invalid color");
                        g = std.fmt.parseInt(u8, hex[2..4], 16) catch @panic("invalid color");
                        b = std.fmt.parseInt(u8, hex[4..6], 16) catch @panic("invalid color");
                    } else {
                        @panic("invalid color");
                    }

                    return ColorU8{
                        .r = r,
                        .g = g,
                        .b = b,
                        .a = 255,
                    };
                } else {
                    @panic("invalid color");
                }
            },
            'r' => {
                const id = parser.readIdentifier().?;

                if (std.mem.eql(u8, id, "rgb")) {
                    _ = parser.readExpected('(') orelse @panic("invalid color");
                    parser.skipWhitespace();
                    const r: u8 = @intCast(parser.readI32() orelse @panic("invalid color"));
                    parser.skipWhitespace();
                    _ = parser.readExpected(',') orelse @panic("invalid color");
                    parser.skipWhitespace();
                    const g: u8 = @intCast(parser.readI32() orelse @panic("invalid color"));
                    parser.skipWhitespace();
                    _ = parser.readExpected(',') orelse @panic("invalid color");
                    parser.skipWhitespace();
                    const b: u8 = @intCast(parser.readI32() orelse @panic("invalid color"));
                    parser.skipWhitespace();
                    _ = parser.readExpected(')') orelse @panic("invalid color");

                    return ColorU8{
                        .r = r,
                        .g = g,
                        .b = b,
                        .a = 255,
                    };
                }
            },
            else => @panic("invalid color"),
        }

        @panic("invalid color");
    }

    pub const Parser = struct {
        bytes: []const u8,
        index: u32 = 0,

        pub fn create(bytes: []const u8) @This() {
            return @This(){
                .bytes = bytes,
            };
        }

        pub fn readByte(self: *@This()) ?u8 {
            if (self.peekByte()) |byte| {
                self.index += 1;
                return byte;
            }

            return null;
        }

        pub fn readN(self: *@This(), n: u32) ?[]const u8 {
            if (self.index + n > self.bytes.len) {
                return null;
            }

            const bytes = self.bytes[self.index .. self.index + n];
            self.index += n;
            return bytes;
        }

        pub fn peekByte(self: *@This()) ?u8 {
            if (self.index >= self.bytes.len) {
                return null;
            }

            const byte = self.bytes[self.index];
            return byte;
        }

        pub fn readHexN(self: *@This(), n: u32) ?u32 {
            const bytes = self.readN(n) orelse return null;

            const value = std.fmt.parseInt(
                u32,
                bytes,
                16,
            ) catch @panic("invalid i32");

            return value;
        }

        pub fn readI32(self: *@This()) ?i32 {
            const start_index = self.index;
            var end_index = self.index;

            for (self.bytes[start_index..]) |byte| {
                if (!isDigit(byte)) {
                    break;
                }

                end_index += 1;
            }

            if (start_index == end_index) {
                return null;
            }
            self.index = end_index;

            const value = std.fmt.parseInt(
                i32,
                self.bytes[start_index..end_index],
                10,
            ) catch @panic("invalid i32");
            return value;
        }

        pub fn readF32(self: *@This()) ?f32 {
            self.skipWhitespace();
            self.skipComma();
            const real_start_index = self.index;
            var start_index = self.index;
            var end_index = self.index;

            const next_byte = self.peekByte() orelse return null;
            if (next_byte == '-') {
                _ = self.readByte();
                start_index += 1;
                end_index += 1;
            }

            for (self.bytes[start_index..]) |byte| {
                if (!isFloatByte(byte)) {
                    break;
                }

                end_index += 1;
            }

            if (real_start_index == end_index) {
                return null;
            }
            self.index = end_index;

            const float_bytes = self.bytes[real_start_index..end_index];
            const value = std.fmt.parseFloat(
                f32,
                float_bytes,
            ) catch @panic("invalid f32");
            return value;
        }

        pub fn readExpected(self: *@This(), expected: u8) ?u8 {
            if (self.peekByte()) |byte| {
                if (byte == expected) {
                    self.index += 1;
                    return byte;
                }
            }

            return null;
        }

        pub fn readHex(self: *@This()) ?[]const u8 {
            const start_index = self.index;
            var end_index = start_index;

            for (self.bytes[start_index..]) |byte| {
                if (!isHex(byte)) {
                    break;
                }

                end_index += 1;
            }

            if (start_index == end_index) {
                return null;
            }

            self.index = end_index;
            return self.bytes[start_index..end_index];
        }

        pub fn readIdentifier(self: *@This()) ?[]const u8 {
            const start_index = self.index;
            var end_index = start_index;

            _ = self.readAlpha() orelse return null;
            for (self.bytes[start_index..]) |byte| {
                if (!isAlphaNumeric(byte)) {
                    break;
                }

                end_index += 1;
            }

            if (start_index == end_index) {
                return null;
            }

            self.index = end_index;
            return self.bytes[start_index..end_index];
        }

        pub fn readAlpha(self: *@This()) ?u8 {
            const byte = self.peekByte() orelse return null;
            if (isAlpha(byte)) {
                return byte;
            }

            return null;
        }

        pub fn skipWhitespace(self: *@This()) void {
            while (self.peekByte()) |byte| {
                if (!isWhitespace(byte)) {
                    break;
                }
                self.index += 1;
            }
        }

        pub fn skipComma(self: *@This()) void {
            const next_byte = self.peekByte() orelse return;
            if (next_byte == ',') {
                _ = self.readByte();
            }
        }

        fn err(self: *@This()) bool {
            self.index = @intCast(self.bytes.len);
            return false;
        }

        pub fn isHex(byte: u8) bool {
            return (byte >= '0' and byte <= '8') or (byte >= 'a' and byte <= 'f') or (byte >= 'A' or byte <= 'F');
        }

        pub fn isAlphaNumeric(byte: u8) bool {
            return isAlpha(byte) or isDigit(byte);
        }

        pub fn isAlpha(byte: u8) bool {
            return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z');
        }

        pub fn isWhitespace(byte: u8) bool {
            return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
        }

        pub fn isFloatByte(byte: u8) bool {
            return isDigit(byte) or byte == '.';
        }

        pub fn isDigit(byte: u8) bool {
            return (byte >= '0' and byte <= '9');
        }
    };
};

pub const PathParser = struct {
    tokenizer: PathTokenizer,
    path_encoder: *PathEncoderF32,
    draw_mode: ?PathTokenizer.DrawMode = null,
    last_control_point: ?PointF32 = null,

    pub fn create(path: []const u8, path_encoder: *PathEncoderF32) @This() {
        return @This(){
            .tokenizer = PathTokenizer.create(path),
            .path_encoder = path_encoder,
        };
    }

    pub fn encode(self: *@This()) !void {
        while (self.tokenizer.next()) |token| {
            switch (token) {
                .draw_mode => |draw_mode| {
                    self.setDrawMode(draw_mode);
                },
                .points => |points| {
                    var points2 = points;
                    try self.drawPoints(&points2);
                },
            }
        }
    }

    pub fn setDrawMode(self: *@This(), new_draw_mode: PathTokenizer.DrawMode) void {
        self.draw_mode = new_draw_mode;

        if (!new_draw_mode.isCubic()) {
            self.last_control_point = null;
        }
    }

    pub fn drawPoints(self: *@This(), points: *PathTokenizer.PointIterator) !void {
        const draw_mode = self.draw_mode orelse @panic("not drawing");

        switch (draw_mode.draw) {
            .move_to => {
                std.debug.assert(true);
                while (self.nextPoint(points, draw_mode.position)) |point| {
                    try self.path_encoder.moveToPoint(point);
                }
                self.last_control_point = null;
            },
            .horizontal_line_to => {
                while (self.nextHorizontalPoint(points, draw_mode.position)) |point| {
                    try self.path_encoder.lineToPoint(point);
                }
                self.last_control_point = null;
            },
            .vertical_line_to => {
                while (self.nextVerticalPoint(points, draw_mode.position)) |point| {
                    try self.path_encoder.lineToPoint(point);
                }
                self.last_control_point = null;
            },
            .line_to => {
                while (self.nextPoint(points, draw_mode.position)) |point| {
                    try self.path_encoder.lineToPoint(point);
                }
                self.last_control_point = null;
            },
            .quad_to => {
                while (self.nextPoint(points, draw_mode.position)) |p1| {
                    const p2 = self.nextPoint(points, draw_mode.position) orelse @panic("invalid quad_to");
                    try self.path_encoder.quadToPoint(p1, p2);
                }
                self.last_control_point = null;
            },
            .cubic_to => {
                while (self.nextPoint(points, draw_mode.position)) |p1| {
                    const p2 = self.nextPoint(points, draw_mode.position) orelse @panic("invalid cubic_to");
                    const p3 = self.nextPoint(points, draw_mode.position) orelse @panic("invalid cubic_to");

                    self.last_control_point = p2;
                    try self.path_encoder.cubicToPoint(p1, p2, p3);
                }
            },
            .smooth_cubic_to => {
                while (true) {
                    var p1 = self.getPreviousPoint();
                    if (self.last_control_point) |ctl| {
                        p1 = p1.mulScalar(2.0).sub(ctl);
                    }

                    const p2 = self.nextPoint(points, draw_mode.position) orelse break;
                    const p3 = self.nextPoint(points, draw_mode.position) orelse @panic("invalid smooth_cubic_to");

                    self.last_control_point = p2;
                    try self.path_encoder.cubicToPoint(p1, p2, p3);
                }
            },
            .close => {
                try self.path_encoder.close();
            },
        }
    }

    pub fn nextPoint(
        self: *@This(),
        points: *PathTokenizer.PointIterator,
        position: PathTokenizer.Position,
    ) ?PointF32 {
        const previous_point = self.getPreviousPoint();
        var next_point = points.next() orelse return null;

        if (position == .relative) {
            next_point = previous_point.add(next_point);
        }

        return next_point;
    }

    pub fn nextHorizontalPoint(
        self: *@This(),
        points: *PathTokenizer.PointIterator,
        position: PathTokenizer.Position,
    ) ?PointF32 {
        const next_float = points.nextFloat() orelse return null;
        const previous_point = self.getPreviousPoint();
        var point = PointF32.create(next_float, previous_point.y);

        if (position == .relative) {
            point.x += previous_point.x;
        }

        return point;
    }

    pub fn nextVerticalPoint(
        self: *@This(),
        points: *PathTokenizer.PointIterator,
        position: PathTokenizer.Position,
    ) ?PointF32 {
        const next_float = points.nextFloat() orelse return null;
        const previous_point = self.getPreviousPoint();
        var point = PointF32.create(previous_point.x, next_float);

        if (position == .relative) {
            point.y += previous_point.y;
        }

        return point;
    }

    pub fn getPreviousPoint(self: @This()) PointF32 {
        const previous_point = self.path_encoder.currentPoint();
        return previous_point;
    }
};

pub const PathTokenizer = struct {
    bytes: []const u8,
    index: u32 = 0,

    pub fn create(bytes: []const u8) @This() {
        return @This(){
            .bytes = bytes,
        };
    }

    pub fn next(self: *@This()) ?Token {
        self.skip();
        const next_byte = self.peekByte() orelse return null;

        switch (next_byte) {
            'M' => {
                self.advance();
                return Token.drawMode(.move_to, .absolute);
            },
            'm' => {
                self.advance();
                return Token.drawMode(.move_to, .relative);
            },
            'H' => {
                self.advance();
                return Token.drawMode(.horizontal_line_to, .absolute);
            },
            'h' => {
                self.advance();
                return Token.drawMode(.horizontal_line_to, .relative);
            },
            'V' => {
                self.advance();
                return Token.drawMode(.vertical_line_to, .absolute);
            },
            'v' => {
                self.advance();
                return Token.drawMode(.vertical_line_to, .relative);
            },
            'L' => {
                self.advance();
                return Token.drawMode(.line_to, .absolute);
            },
            'l' => {
                self.advance();
                return Token.drawMode(.line_to, .relative);
            },
            'Q' => {
                self.advance();
                return Token.drawMode(.quad_to, .absolute);
            },
            'q' => {
                self.advance();
                return Token.drawMode(.quad_to, .relative);
            },
            'C' => {
                self.advance();
                return Token.drawMode(.cubic_to, .absolute);
            },
            'c' => {
                self.advance();
                return Token.drawMode(.cubic_to, .relative);
            },
            'S' => {
                self.advance();
                return Token.drawMode(.smooth_cubic_to, .absolute);
            },
            's' => {
                self.advance();
                return Token.drawMode(.smooth_cubic_to, .relative);
            },
            'Z' => {
                self.advance();
                return Token.drawMode(.close, .absolute);
            },
            'z' => {
                self.advance();
                return Token.drawMode(.close, .absolute);
            },
            else => {
                // continue for further processing
            },
        }

        if (isStartPoint(next_byte)) {
            return Token{
                .points = PointIterator.create(self),
            };
        }

        @panic("invalid path");
    }

    pub fn peekByte(self: @This()) ?u8 {
        if (self.index >= self.bytes.len) {
            return null;
        }

        return self.bytes[self.index];
    }

    pub fn skip(self: *@This()) void {
        while (self.peekByte()) |byte| {
            if (!isSkip(byte)) {
                break;
            }

            self.advance();
        }
    }

    pub fn advance(self: *@This()) void {
        self.index += 1;
    }

    pub fn readF32(self: *@This()) !f32 {
        const start_index = self.index;
        var end_index = self.index + 1;

        self.advance();
        while (self.peekByte()) |byte| {
            if (!isFloatByte(byte)) {
                break;
            }

            self.advance();
            end_index += 1;
        }

        const float_bytes = self.bytes[start_index..end_index];
        return try std.fmt.parseFloat(f32, float_bytes);
    }

    pub fn isStartPoint(byte: u8) bool {
        return isDigit(byte) or byte == '-';
    }

    pub fn isFloatByte(byte: u8) bool {
        return isDigit(byte) or byte == '.';
    }

    pub fn isDigit(byte: u8) bool {
        return byte >= '0' and byte <= '9';
    }

    pub fn isSkip(byte: u8) bool {
        return isWhitespace(byte) or byte == ',';
    }

    pub fn isWhitespace(byte: u8) bool {
        return byte == ' ' or byte == '\n' or byte == '\r' or byte == '\t';
    }

    pub const PointIterator = struct {
        tokenizer: *PathTokenizer,

        pub fn create(tokenizer: *PathTokenizer) PointIterator {
            return @This(){
                .tokenizer = tokenizer,
            };
        }

        pub fn next(self: *@This()) ?PointF32 {
            self.tokenizer.skip();
            const next_byte = self.tokenizer.peekByte() orelse return null;

            if (!isStartPoint(next_byte)) {
                return null;
            }

            const x = self.tokenizer.readF32() catch @panic("invalid point");
            self.tokenizer.skip();
            const y = self.tokenizer.readF32() catch @panic("invalid point");

            return PointF32.create(x, y);
        }

        pub fn nextFloat(self: *@This()) ?f32 {
            self.tokenizer.skip();
            const next_byte = self.tokenizer.peekByte() orelse return null;

            if (!isStartPoint(next_byte)) {
                return null;
            }

            const x = self.tokenizer.readF32() catch @panic("invalid point");
            return x;
        }
    };

    pub const Token = union(enum) {
        draw_mode: DrawMode,
        points: PointIterator,

        pub fn drawMode(d: Draw, p: Position) @This() {
            return @This(){
                .draw_mode = DrawMode.create(d, p),
            };
        }
    };

    pub const DrawMode = struct {
        draw: Draw,
        position: Position,

        pub fn create(d: Draw, p: Position) @This() {
            return @This(){
                .draw = d,
                .position = p,
            };
        }

        pub fn isCubic(self: @This()) bool {
            return self.draw == .cubic_to or self.draw == .smooth_cubic_to;
        }
    };

    pub const Draw = enum {
        move_to,
        line_to,
        horizontal_line_to,
        vertical_line_to,
        quad_to,
        cubic_to,
        smooth_cubic_to,
        close,
    };

    pub const Position = enum {
        absolute,
        relative,
    };
};
