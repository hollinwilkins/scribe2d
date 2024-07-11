const std = @import("std");
const xml = @import("./xml/mod.zig");
const core = @import("../core/root.zig");
const draw = @import("../draw/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const GenericReader = std.io.GenericReader;
const PointI32 = core.PointI32;
const RectI32 = core.RectI32;
const TransformF32 = core.TransformF32;
const Encoder = draw.Encoder;
const PathEncoderI16 = draw.PathEncoderI16;
const ColorU8 = draw.ColorU8;
const Style = draw.Style;

pub const Svg = struct {
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

        var viewbox_iter = std.mem.split(u8, doc.root.attr("viewBox").?, " ");
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

    pub fn encode(self: *@This(), encoder: *Encoder) !void {
        self.doc.acquire();
        defer self.doc.release();
        const root = self.doc.root;

        for (root.children()) |child| {
            try encodeNode(encoder, child);
        }
    }

    pub fn encodeNode(encoder: *Encoder, node: xml.NodeIndex) !void {
        switch (node) {
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
            try encodeNode(encoder, child.v());
        }
    }

    pub fn encodePathEl(encoder: *Encoder, path: xml.Element) !void {
        var style: ?Style = null;

        if (path.attr("fill")) |fill| {
            try encoder.encodeColor(parseColor(fill));

            style = if (style == null) Style{} else style;
            style.setFill(Style.Fill{
                .brush = .color,
            });
        }

        if (style) |s| {
            encoder.encodeStyle(s);
        }

        if (path.attr("path")) |path| {
            var path_encoder = encoder.pathEncoder(i16);
            var iterator = PathEncodeIterator{
                .path = path,
                .encoder = &path_encoder,
            };
            while (iterator.encodeNext()) {}
            try path_encoder.finish();
        }
    }

    fn parseTransform(value: []const u8) TransformF32.Affine {}

    fn parseColor(value: []const u8) ColorU8 {}

    pub const PathEncodeIterator = struct {
        encoder: *PathEncoderI16,
        path: []const u8,
        index: u32 = 0,

        pub fn encodeNext(self: *@This()) !bool {
            if (self.readByte()) |byte| {
                switch (std.ascii.toLower(byte)) {
                    'm' => {
                        const x = try self.readInt() orelse return self.err();
                        const y = try self.readInt() orelse return self.err();
                        try self.encoder.moveTo(x, y);
                    },
                    'h' => {
                        const y = try self.readInt() orelse return self.err();
                        const p0 = self.encoder.lastPoint() orelse return self.err();
                        try self.encoder.lineTo(p0.x, y);
                    },
                    'v' => {
                        const x = try self.readInt() orelse return self.err();
                        const p0 = self.encoder.lastPoint() orelse return self.err();
                        try self.encoder.lineTo(x, p0.y);
                    },
                    'l' => {
                        const x = try self.readInt() orelse return self.err();
                        const y = try self.readInt() orelse return self.err();
                        try self.encoder.lineTo(x, y);
                    },
                }
            }

            return true;
        }

        pub fn readByte(self: *@This()) ?u8 {
            if (self.peekByte()) |byte| {
                self.index += 1;
                return byte;
            }

            return null;
        }

        pub fn peekByte(self: *@This()) ?u8 {
            if (self.index >= self.path.len) {
                return null;
            }

            const byte = self.path[self.index];
            return byte;
        }

        pub fn readInt(self: *@This()) !?i16 {
            const start_index = self.index;
            var end_index = self.index;

            for (self.path[start_index]) |byte| {
                if (!isDigitOrMinus(byte)) {
                    break;
                }

                end_index += 1;
            }

            if (start_index == end_index) {
                return null;
            }

            return try std.fmt.parseInt(i16, self.path[start_index..end_index]);
        }

        pub fn readComma(self: *@This()) ?u8 {
            if (self.peekByte()) |byte| {
                if (byte == ',') {
                    self.index += 1;
                    return byte;
                }
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
            self.index = self.path.len;
            return false;
        }

        pub fn isWhitespace(byte: u8) bool {
            return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
        }

        pub fn isDigitOrMinus(byte: u8) bool {
            return (byte >= '0' and byte <= '9') or byte == '-';
        }
    };
};
