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
            defer path_encoder.finish();
            var iterator = PathParser{
                .parser = Parser.create(path),
                .encoder = &path_encoder,
            };
            while (try iterator.encodeNext()) {}
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
            var float_parser = FloatParser{
                .parser = &parser,
            };
            _ = parser.readExpected('(');
            const a = float_parser.next() orelse @panic("invalid matrix");
            const b = float_parser.next() orelse @panic("invalid matrix");
            const c = float_parser.next() orelse @panic("invalid matrix");
            const d = float_parser.next() orelse @panic("invalid matrix");
            const e = float_parser.next() orelse @panic("invalid matrix");
            const f = float_parser.next() orelse @panic("invalid matrix");
            _ = parser.readExpected(')');

            return TransformF32.Affine{
                .coefficients = [6]f32{
                    a, c, e,
                    b, d, f,
                },
            };
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

    pub const PathParser = struct {
        encoder: *PathEncoderF32,
        parser: Parser,
        state: State = State.START,
        index: u32 = 0,
        c2: ?PointF32 = null,

        pub fn encodeNext(self: *@This()) !bool {
            std.debug.assert(true);

            switch (self.state.parser_state) {
                .start => {
                    self.state = self.parseNextState();
                    return try self.encodeNext();
                },
                .draw => {
                    switch (self.state.draw_state) {
                        .move_to => {
                            self.c2 = null;
                            var point_parser = PointParser.create(&self.parser);

                            while (point_parser.next()) |point| {
                                switch (self.state.draw_position) {
                                    .absolute => {
                                        try self.encoder.moveToPoint(point);
                                    },
                                    .relative => {
                                        const current = self.encoder.currentPoint();
                                        try self.encoder.moveToPoint(current.add(point));
                                    },
                                }
                            }
                        },
                        .horizontal_line_to => {
                            self.c2 = null;
                            var float_parser = FloatParser{
                                .parser = &self.parser,
                            };

                            while (float_parser.next()) |y| {
                                const current = self.encoder.currentPoint();
                                switch (self.state.draw_position) {
                                    .absolute => {
                                        try self.encoder.lineTo(current.x, y);
                                    },
                                    .relative => {
                                        try self.encoder.lineTo(current.x, current.y + y);
                                    },
                                }
                            }
                        },
                        .vertical_line_to => {
                            self.c2 = null;
                            var float_parser = FloatParser{
                                .parser = &self.parser,
                            };

                            while (float_parser.next()) |x| {
                                const current = self.encoder.currentPoint();
                                switch (self.state.draw_position) {
                                    .absolute => {
                                        try self.encoder.lineTo(x, current.y);
                                    },
                                    .relative => {
                                        try self.encoder.lineTo(current.x + x, current.y);
                                    },
                                }
                            }
                        },
                        .line_to => {
                            self.c2 = null;
                            var point_parser = PointParser.create(&self.parser);

                            while (point_parser.next()) |point| {
                                switch (self.state.draw_position) {
                                    .absolute => {
                                        try self.encoder.lineToPoint(point);
                                    },
                                    .relative => {
                                        const current = self.encoder.currentPoint();
                                        try self.encoder.lineToPoint(current.add(point));
                                    },
                                }
                            }
                        },
                        .quad_to => {
                            var point_parser = PointParser.create(&self.parser);

                            while (point_parser.next()) |p1| {
                                const p2 = point_parser.next() orelse @panic("invalid cubic");

                                switch (self.state.draw_position) {
                                    .absolute => {
                                        try self.encoder.quadToPoint(p1, p2);
                                        self.c2 = p2;
                                    },
                                    .relative => {
                                        const current = self.encoder.currentPoint();
                                        try self.encoder.quadToPoint(p1.add(current), p2.add(current));
                                        self.c2 = p2;
                                    },
                                }
                            }
                        },
                        .cubic_to => {
                            var point_parser = PointParser.create(&self.parser);

                            while (point_parser.next()) |p1| {
                                const p2 = point_parser.next() orelse @panic("invalid cubic");
                                const p3 = point_parser.next() orelse @panic("invalid cubic");

                                switch (self.state.draw_position) {
                                    .absolute => {
                                        try self.encoder.cubicToPoint(p1, p2, p3);
                                        self.c2 = p2;
                                    },
                                    .relative => {
                                        const current = self.encoder.currentPoint();
                                        try self.encoder.cubicToPoint(p1.add(current), p2.add(current), p3.add(current));
                                        self.c2 = p2;
                                    },
                                }
                            }
                        },
                        .smooth_cubic_to => {
                            var point_parser = PointParser.create(&self.parser);

                            while (point_parser.next()) |p2| {
                                const p3 = point_parser.next() orelse @panic("invalid cubic");
                                var p1: PointF32 = undefined;

                                if (self.c2) |c2| {
                                    p1 = c2.reflectOn(self.encoder.currentPoint());
                                } else {
                                    p1 = self.encoder.currentPoint();
                                }

                                switch (self.state.draw_position) {
                                    .absolute => {
                                        try self.encoder.cubicToPoint(p1, p2, p3);
                                        self.c2 = p2;
                                    },
                                    .relative => {
                                        const current = self.encoder.currentPoint();
                                        try self.encoder.cubicToPoint(p1, p2.add(current), p3.add(current));
                                        self.c2 = p2;
                                    },
                                }
                            }
                        },
                        .close => {
                            self.encoder.finish();
                        },
                        else => @panic("unsupported draw state"),
                    }
                },
                .done => {
                    return false;
                },
            }

            self.state = self.parseNextState();
            return self.state.parser_state == .draw;
        }

        fn parseNextState(self: *@This()) State {
            self.parser.skipWhitespace();
            if (self.parser.readByte()) |byte| {
                return switch (byte) {
                    'M' => State.draw(.move_to, .absolute),
                    'm' => State.draw(.move_to, .absolute),
                    'H' => State.draw(.horizontal_line_to, .absolute),
                    'h' => State.draw(.horizontal_line_to, .relative),
                    'V' => State.draw(.vertical_line_to, .absolute),
                    'v' => State.draw(.vertical_line_to, .relative),
                    'L' => State.draw(.line_to, .absolute),
                    'l' => State.draw(.line_to, .relative),
                    'Q' => State.draw(.quad_to, .absolute),
                    'q' => State.draw(.quad_to, .relative),
                    'C' => State.draw(.cubic_to, .absolute),
                    'c' => State.draw(.cubic_to, .relative),
                    'S' => State.draw(.smooth_cubic_to, .absolute),
                    's' => State.draw(.smooth_cubic_to, .relative),
                    'z' => State.draw(.close, .absolute),
                    else => @panic("unsupported path movement"),
                };
            }

            return State.DONE;
        }

        pub const State = struct {
            pub const START: State = State{
                .parser_state = .start,
            };
            pub const DONE: State = State{
                .parser_state = .done,
            };

            parser_state: ParserState = .start,
            draw_state: DrawState = .move_to,
            draw_position: DrawPosition = .absolute,

            pub fn draw(draw_state: DrawState, draw_position: DrawPosition) State {
                return State{
                    .parser_state = .draw,
                    .draw_state = draw_state,
                    .draw_position = draw_position,
                };
            }
        };

        pub const ParserState = enum {
            start,
            draw,
            done,
        };

        pub const DrawPosition = enum {
            absolute,
            relative,
        };

        pub const DrawState = enum {
            move_to,
            line_to,
            horizontal_line_to,
            vertical_line_to,
            arc_to,
            quad_to,
            smooth_quad_to,
            cubic_to,
            smooth_cubic_to,
            close,
        };
    };

    pub const PointParser = struct {
        float_parser: FloatParser,

        pub fn create(parser: *Parser) @This() {
            return @This(){
                .float_parser = FloatParser{
                    .parser = parser,
                },
            };
        }

        pub fn next(self: *@This()) ?PointF32 {
            const x = self.float_parser.next() orelse return null;
            const y = self.float_parser.next() orelse return null;

            return PointF32{
                .x = x,
                .y = y,
            };
        }
    };

    pub const FloatParser = struct {
        parser: *Parser,

        pub fn next(self: *@This()) ?f32 {
            self.parser.skipWhitespace();

            var next_byte = self.parser.peekByte() orelse return null;
            if (next_byte == ',') {
                _ = self.parser.readByte();
                self.parser.skipWhitespace();
                next_byte = self.parser.peekByte() orelse return null;
            }

            if (Parser.isDigit(next_byte) or next_byte == '-') {
                self.parser.skipWhitespace();
                const x = self.parser.readF32() orelse @panic("invalid float");
                self.parser.skipWhitespace();
                return x;
            }

            return null;
        }
    };

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

            if (start_index == end_index) {
                return null;
            }
            self.index = end_index;

            const float_bytes = self.bytes[start_index..end_index];
            std.debug.print("FLoat Bytes: {s}\n", .{float_bytes});
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
