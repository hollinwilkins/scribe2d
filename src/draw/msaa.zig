const core = @import("../core/root.zig");
const PointF32 = core.PointF32;

pub fn createHalfPlanes(
    n_samples: comptime_int,
    t: type,
    points: *const [n_samples]PointF32,
    masks: *const [n_samples + 1]t,
) void {}

const UV_SAMPLE_COUNT_1: [1]PointF32 = [1]PointF32{
    PointF32.create(0.5, 0.5),
};

const UV_SAMPLE_COUNT_1_VERTICAL_LOOKUP: [2]u1 = [2]u1{
    0b0,
    0b1,
};

const UV_SAMPLE_COUNT_2: [2]PointF32 = [2]PointF32{
    PointF32.create(0.75, 0.75),
    PointF32.create(0.25, 0.25),
};

const UV_SAMPLE_COUNT_2_VERTICAL_LOOKUP: [3]u2 = [3]u2{
    0b00,
    0b01,
    0b11,
};

const UV_SAMPLE_COUNT_4: [4]PointF32 = [4]PointF32{
    PointF32.create(0.375, 0.125),
    PointF32.create(0.875, 0.375),
    PointF32.create(0.125, 0.625),
    PointF32.create(0.625, 0.875),
};

const UV_SAMPLE_COUNT_4_VERTICAL_LOOKUP: [5]u4 = [5]u4{
    0b0000,
    0b0001,
    0b0011,
    0b0111,
    0b1111,
};

const UV_SAMPLE_COUNT_8: [8]PointF32 = [8]PointF32{
    PointF32.create(0.5625, 0.3125),
    PointF32.create(0.4375, 0.6875),
    PointF32.create(0.8125, 0.5625),
    PointF32.create(0.3125, 0.1875),
    PointF32.create(0.1875, 0.8125),
    PointF32.create(0.0625, 0.4375),
    PointF32.create(0.6875, 0.9375),
    PointF32.create(0.9375, 0.0625),
};

const UV_SAMPLE_COUNT_8_VERTICAL_LOOKUP: [9]u8 = [9]u8{
    0b00000000,
    0b00000001,
    0b00000011,
    0b00000111,
    0b00001111,
    0b00011111,
    0b00111111,
    0b01111111,
    0b11111111,
};

const UV_SAMPLE_COUNT_16: [16]PointF32 = [16]PointF32{
    PointF32.create(0.5625, 0.5625),
    PointF32.create(0.4375, 0.3125),
    PointF32.create(0.3125, 0.625),
    PointF32.create(0.75, 0.4375),
    PointF32.create(0.1875, 0.375),
    PointF32.create(0.625, 0.8125),
    PointF32.create(0.8125, 0.6875),
    PointF32.create(0.6875, 0.1875),
    PointF32.create(0.375, 0.875),
    PointF32.create(0.5, 0.0625),
    PointF32.create(0.25, 0.125),
    PointF32.create(0.125, 0.75),
    PointF32.create(0.0, 0.5),
    PointF32.create(0.9375, 0.25),
    PointF32.create(0.875, 0.9375),
    PointF32.create(0.0625, 0.0),
};

const UV_SAMPLE_COUNT_16_VERTICAL_LOOKUP: [17]u16 = [17]u16{
    0b0000000000000000,
    0b0000000000000001,
    0b0000000000000011,
    0b0000000000000111,
    0b0000000000001111,
    0b0000000000011111,
    0b0000000000111111,
    0b0000000001111111,
    0b0000000011111111,
    0b0000000111111111,
    0b0000001111111111,
    0b0000011111111111,
    0b0000111111111111,
    0b0001111111111111,
    0b0011111111111111,
    0b0111111111111111,
    0b1111111111111111,
};
