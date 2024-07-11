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
const PathEncoderI16 = draw.PathEncoderI16;
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
            try encoder.encodeColor(parseColor(fill));

            style = if (style == null) Style{} else style;
            style.?.setFill(Style.Fill{
                .brush = .color,
            });
        }

        if (style) |s| {
            try encoder.encodeStyle(s);
        }

        if (path_el.attr("d")) |path| {
            var path_encoder = encoder.pathEncoder(i16);
            defer path_encoder.finish();
            var iterator = PathEncodeIterator{
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
            const x = parser.readInt() orelse @panic("invalid translate");
            _ = parser.readExpected(',');
            const y = parser.readInt() orelse @panic("invalid translate");
            transform.translate = PointF32{
                .x = @floatFromInt(x),
                .y = @floatFromInt(y),
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
        };
    }

    pub const PathEncodeIterator = struct {
        encoder: *PathEncoderI16,
        parser: Parser,
        index: u32 = 0,

        pub fn encodeNext(self: *@This()) !bool {
            const start_index = self.parser.index;
            if (self.parser.readByte()) |byte| {
                switch (std.ascii.toLower(byte)) {
                    'm' => {
                        const x = self.parser.readInt() orelse return self.parser.err();
                        _ = self.parser.readExpected(',') orelse return self.parser.err();
                        const y = self.parser.readInt() orelse return self.parser.err();
                        try self.encoder.moveTo(x, y);
                    },
                    'h' => {
                        const y = self.parser.readInt() orelse return self.parser.err();
                        const p0 = self.encoder.lastPoint() orelse return self.parser.err();
                        try self.encoder.lineTo(p0.x, y);
                    },
                    'v' => {
                        const x = self.parser.readInt() orelse return self.parser.err();
                        const p0 = self.encoder.lastPoint() orelse return self.parser.err();
                        try self.encoder.lineTo(x, p0.y);
                    },
                    'l' => {
                        const x = self.parser.readInt() orelse return self.parser.err();
                        _ = self.parser.readExpected(',') orelse return self.parser.err();
                        const y = self.parser.readInt() orelse return self.parser.err();
                        try self.encoder.lineTo(x, y);
                    },
                    else => {
                        std.debug.print("HEEEY({s}): Head({s})\n", .{ &[_]u8{byte}, self.parser.bytes[start_index..self.parser.index] });
                        @panic("invalid path");
                    },
                }
            } else {
                return false;
            }

            return true;
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

        pub fn readInt(self: *@This()) ?i16 {
            const start_index = self.index;
            var end_index = self.index;

            for (self.bytes[start_index..]) |byte| {
                if (!isDigitOrMinus(byte)) {
                    break;
                }

                end_index += 1;
            }

            if (start_index == end_index) {
                return null;
            }
            self.index = end_index;

            const int = std.fmt.parseInt(
                i16,
                self.bytes[start_index..end_index],
                10,
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
            var end_index: u32 = 0;

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

        pub fn isDigitOrMinus(byte: u8) bool {
            return isDigit(byte) or byte == '-';
        }

        pub fn isDigit(byte: u8) bool {
            return (byte >= '0' and byte <= '9') or byte == '-';
        }
    };
};
