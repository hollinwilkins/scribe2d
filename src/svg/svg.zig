const std = @import("std");
const xml = @import("./xml/mod.zig");
const core = @import("../core/root.zig");
const draw = @import("../draw/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const GenericReader = std.io.GenericReader;
const PointF32 = core.PointF32;
const PointI32 = core.PointI32;
const RectI32 = core.RectI32;
const TransformF32 = core.TransformF32;
const Encoder = draw.Encoder;
const PathEncoderF32 = draw.PathEncoderF32;
const ColorU8 = draw.ColorU8;
const Style = draw.Style;

pub const Svg = struct {
    pub const EncodeError = error{
        OutOfMemory,
    };

    viewbox: RectI32,
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
        var dims: [4]i32 = undefined;
        var i: u32 = 0;
        while (viewbox_iter.next()) |dim| {
            dims[i] = try std.fmt.parseInt(i32, dim, 10);
            i += 1;
        }
        const viewbox = RectI32{
            .min = PointI32{
                .x = dims[0],
                .y = dims[1],
            },
            .max = PointI32{
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
            const x = parser.readFloat() orelse @panic("invalid translate");
            _ = parser.readExpected(',');
            const y = parser.readFloat() orelse @panic("invalid translate");
            transform.translate = PointF32{
                .x = x,
                .y = y,
            };
            _ = parser.readExpected(')');
        }

        return transform.toAffine();
    }

    fn parseColor(value: []const u8) ColorU8 {
        var parser = Parser.create(value);
        _ = parser.readExpected('#') orelse @panic("invalid color");
        const rs = parser.readN(2) orelse @panic("invalid color");
        const gs = parser.readN(2) orelse @panic("invalid color");
        const bs = parser.readN(2) orelse @panic("invalid color");

        const r = std.fmt.parseInt(u8, rs, 16) catch @panic("invalid color");
        const g = std.fmt.parseInt(u8, gs, 16) catch @panic("invalid color");
        const b = std.fmt.parseInt(u8, bs, 16) catch @panic("invalid color");

        return ColorU8{
            .r = r,
            .g = g,
            .b = b,
            .a = 255,
        };
    }

    pub const PathParser = struct {
        encoder: *PathEncoderF32,
        parser: Parser,
        state: State = State.START,
        index: u32 = 0,

        pub fn encodeNext(self: *@This()) !bool {
            switch (self.state.parser_state) {
                .start => {
                    self.state = self.parseNextState();
                    return try self.encodeNext();
                },
                .draw => {
                    switch (self.state.draw_state) {
                        .move_to => {
                            var point_parser = PointParser{
                                .parser = &self.parser,
                            };

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
                            var point_parser = PointParser{
                                .parser = &self.parser,
                            };

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
                    'm' => State.draw(.move_to, .relative),
                    'H' => State.draw(.horizontal_line_to, .absolute),
                    'h' => State.draw(.horizontal_line_to, .relative),
                    'V' => State.draw(.vertical_line_to, .absolute),
                    'v' => State.draw(.vertical_line_to, .relative),
                    'L' => State.draw(.line_to, .absolute),
                    'l' => State.draw(.line_to, .relative),
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
            cubic_to,
        };

        pub const PointParser = struct {
            parser: *Parser,

            pub fn next(self: *@This()) ?PointF32 {
                self.parser.skipWhitespace();

                const next_byte = self.parser.peekByte() orelse return null;

                if (Parser.isDigit(next_byte)) {
                    const x = self.parser.readFloat() orelse @panic("invalid point");
                    self.parser.skipWhitespace();
                    _ = self.parser.readExpected(',') orelse @panic("invalid point");
                    self.parser.skipWhitespace();
                    const y = self.parser.readFloat() orelse @panic("invalid point");
                    self.parser.skipWhitespace();

                    return PointF32.create(x, y);
                }

                return null;
            }
        };

        pub const FloatParser = struct {
            parser: *Parser,

            pub fn next(self: *@This()) ?f32 {
                self.parser.skipWhitespace();

                const next_byte = self.parser.peekByte() orelse return null;

                if (Parser.isDigit(next_byte)) {
                    const x = self.parser.readFloat() orelse @panic("invalid float");
                    self.parser.skipWhitespace();
                    return x;
                }

                return null;
            }
        };
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

        pub fn readFloat(self: *@This()) ?f32 {
            const start_index = self.index;
            var end_index = self.index;

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

            const int = std.fmt.parseFloat(
                f32,
                self.bytes[start_index..end_index],
            ) catch @panic("invalid integer");
            return int;
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
            var end_index: u32 = self.index;

            while (self.peekByte()) |byte| {
                if (!isWhitespace(byte)) {
                    break;
                }
                end_index += 1;
            }

            self.index = end_index;
        }

        fn err(self: *@This()) bool {
            self.index = @intCast(self.bytes.len);
            return false;
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
            return isDigit(byte) or byte == '-' or byte == '.';
        }

        pub fn isDigit(byte: u8) bool {
            return (byte >= '0' and byte <= '9') or byte == '-';
        }
    };
};
