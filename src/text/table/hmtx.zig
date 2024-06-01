const std = @import("std");
const text = @import("../root.zig");
const util = @import("../util.zig");
const Error = text.Error;
const GlyphId = text.GlyphId;
const Reader = util.Reader;
const LazyArray = util.LazyArray;
const LazyIntArray = util.LazyIntArray;

pub const Metrics = struct {
    advance: u16,
    bearing: i16,

    pub fn read(reader: *Reader) ?Metrics {
        const advance = reader.readInt(u16) orelse return null;
        const bearing = reader.readInt(i16) orelse return null;

        return Metrics{
            .advance = advance,
            .bearing = bearing,
        };
    }
};

pub const Table = struct {
    const MetricsList = LazyArray(Metrics);
    const BearingsList = LazyIntArray(i16);

    metrics: MetricsList,
    bearings: BearingsList,
    number_of_metrics: u16,

    pub fn create(number_of_metrics: u16, number_of_glyphs: u16, data: []const u8) Error!Table {
        if (number_of_metrics == 0 or number_of_glyphs == 0) {
            return error.InvalidTable;
        }

        var reader = Reader.create(data);
        const metrics = MetricsList.read(&reader, number_of_metrics) orelse return error.InvalidTable;

        // 'If the number_of_metrics is less than the total number of glyphs,
        // then that array is followed by an array for the left side bearing values
        // of the remaining glyphs.'
        var bearings: BearingsList = undefined;
        if (number_of_metrics < number_of_glyphs) {
            bearings = BearingsList{};
        } else {
            const count = number_of_glyphs - number_of_metrics;
            // Some malformed fonts can skip "left side bearing values"
            // even when they are expected.
            // Therefore if we weren't able to parser them, simply fallback to an empty array.
            // No need to mark the whole table as malformed.

            bearings = BearingsList.read(&reader, count) orelse BearingsList{};
        }

        return Table{
            .metrics = metrics,
            .bearings = bearings,
            .number_of_metrics = number_of_metrics,
        };
    }

    pub fn getAdvance(self: Table, glyph_id: GlyphId) ?u16 {
        if (glyph_id >= self.number_of_metrics) {
            return null;
        }

        if (self.metrics.get(glyph_id)) |metrics| {
            return metrics.advance;
        } else {
            // 'As an optimization, the number of records can be less than the number of glyphs,
            // in which case the advance value of the last record applies
            // to all remaining glyph IDs.'

            if (self.metrics.last()) |metrics| {
                return metrics.advance;
            }
        }

        return null;
    }

    pub fn getBearing(self: Table, glyph_id: GlyphId) ?i16 {
        if (self.metrics.get(glyph_id)) |metrics| {
            return metrics.bearing;
        }

        if (glyph_id >= self.metrics.len) {
            // 'If the number_of_metrics is less than the total number of glyphs,
            // then that array is followed by an array for the side bearing values
            // of the remaining glyphs.'
            if (self.bearings.get(glyph_id - self.metrics.len)) |bearing| {
                return bearing;
            }
        }
    }
};
