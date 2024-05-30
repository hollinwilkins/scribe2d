const root = @import("../root.zig");
const GlyphId = root.GlyphId;
const OutlineBuilder = root.OutlineBuilder;
const RectI16 = root.RectI16;
const RectF32 = root.RectF32;
const PointF32 = root.PointF32;
const Error = root.Error;
const Reader = root.Reader;
const table = root.table;

pub const Table = struct {
    loca: table.loca.Table,

    pub fn create(data: []const u8) Error!Table {
        const loca_table = try table.loca.Table.create(data);

        return Table{
            .loca = loca_table,
        };
    }

    pub fn outline(self: Table, glyph_id: GlyphId, builder: OutlineBuilder) ?RectI16 {}

    //     /// Outlines a glyph.
    //     #[inline]
    //     pub fn outline(&self, glyph_id: GlyphId, builder: &mut dyn OutlineBuilder) -> Option<Rect> {
    //         let mut b = Builder::new(Transform::default(), RectF::new(), builder);
    //         let glyph_data = self.get(glyph_id)?;
    //         outline_impl(self.loca_table, self.data, glyph_data, 0, &mut b)?
    //     }

    //     #[inline]
    //     pub(crate) fn get(&self, glyph_id: GlyphId) -> Option<&'a [u8]> {
    //         let range = self.loca_table.glyph_range(glyph_id)?;
    //         self.data.get(range)
    //     }
};

pub const Builder = struct {
    builder: OutlineBuilder,
    bbox: RectF32,
    first_on_curve: ?PointF32,
    first_off_curve: ?PointF32,
    last_off_curve: ?PointF32,

    pub fn create(bbox: RectF32, builder: OutlineBuilder) Builder {
        return Builder{
            .builder = builder,
            .bbox = bbox,
            .first_on_curve = null,
            .first_off_curve = null,
            .last_off_curve = null,
        };
    }

    pub fn moveTo(self: *Builder, x: f32, y: f32) void {
        self.bbox.extendBy(x, y);
        self.builder.moveTo(x, y);
    }

    pub fn lineTo(self: *Builder, x: f32, y: f32) void {
        self.bbox.extendBy(x, y);
        self.builder.lineTo(x, y);
    }

    pub fn quadTo(self: *Builder, x1: f32, y1: f32, x: f32, y: f32) void {
        self.bbox.extendBy(x1, y1);
        self.bbox.extendBy(x, y);
        self.builder.quadTo(x1, y1, x, y);
    }

    pub fn pushPoint(self: *Builder, x: f32, y: f32, on_curve_point: bool, last_point: bool) void {
        const p = PointF32{
            .x = x,
            .y = y,
        };

        if (self.first_on_curve == null) {
            if (on_curve_point) {
                self.first_on_curve = p;
                self.moveTo(x, y);
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

            self.builder.close();
        }
    }
};

// #[derive(Clone, Copy, Debug)]
// pub(crate) struct CompositeGlyphInfo {
//     pub glyph_id: GlyphId,
//     pub transform: Transform,
//     #[allow(dead_code)]
//     pub flags: CompositeGlyphFlags,
// }

// #[derive(Clone)]
// pub(crate) struct CompositeGlyphIter<'a> {
//     stream: Stream<'a>,
// }

// impl<'a> CompositeGlyphIter<'a> {
//     #[inline]
//     pub fn new(data: &'a [u8]) -> Self {
//         CompositeGlyphIter {
//             stream: Stream::new(data),
//         }
//     }
// }

// impl<'a> Iterator for CompositeGlyphIter<'a> {
//     type Item = CompositeGlyphInfo;

//     #[inline]
//     fn next(&mut self) -> Option<Self::Item> {
//         let flags = CompositeGlyphFlags(self.stream.read::<u16>()?);
//         let glyph_id = self.stream.read::<GlyphId>()?;

//         let mut ts = Transform::default();

//         if flags.args_are_xy_values() {
//             if flags.arg_1_and_2_are_words() {
//                 ts.e = f32::from(self.stream.read::<i16>()?);
//                 ts.f = f32::from(self.stream.read::<i16>()?);
//             } else {
//                 ts.e = f32::from(self.stream.read::<i8>()?);
//                 ts.f = f32::from(self.stream.read::<i8>()?);
//             }
//         }

//         if flags.we_have_a_two_by_two() {
//             ts.a = self.stream.read::<F2DOT14>()?.to_f32();
//             ts.b = self.stream.read::<F2DOT14>()?.to_f32();
//             ts.c = self.stream.read::<F2DOT14>()?.to_f32();
//             ts.d = self.stream.read::<F2DOT14>()?.to_f32();
//         } else if flags.we_have_an_x_and_y_scale() {
//             ts.a = self.stream.read::<F2DOT14>()?.to_f32();
//             ts.d = self.stream.read::<F2DOT14>()?.to_f32();
//         } else if flags.we_have_a_scale() {
//             ts.a = self.stream.read::<F2DOT14>()?.to_f32();
//             ts.d = ts.a;
//         }

//         if !flags.more_components() {
//             // Finish the iterator even if stream still has some data.
//             self.stream.jump_to_end();
//         }

//         Some(CompositeGlyphInfo {
//             glyph_id,
//             transform: ts,
//             flags,
//         })
//     }
// }

// // Due to some optimization magic, using f32 instead of i16
// // makes the code ~10% slower. At least on my machine.
// // I guess it's due to the fact that with i16 the struct
// // fits into the machine word.
// #[derive(Clone, Copy, Debug)]
// pub(crate) struct GlyphPoint {
//     pub x: i16,
//     pub y: i16,
//     /// Indicates that a point is a point on curve
//     /// and not a control point.
//     pub on_curve_point: bool,
//     pub last_point: bool,
// }

// #[derive(Clone, Default)]
// pub(crate) struct GlyphPointsIter<'a> {
//     endpoints: EndpointsIter<'a>,
//     flags: FlagsIter<'a>,
//     x_coords: CoordsIter<'a>,
//     y_coords: CoordsIter<'a>,
//     pub points_left: u16, // Number of points left in the glyph.
// }

// #[cfg(feature = "variable-fonts")]
// impl GlyphPointsIter<'_> {
//     #[inline]
//     pub fn current_contour(&self) -> u16 {
//         self.endpoints.index - 1
//     }
// }

// impl<'a> Iterator for GlyphPointsIter<'a> {
//     type Item = GlyphPoint;

//     #[inline]
//     fn next(&mut self) -> Option<Self::Item> {
//         self.points_left = self.points_left.checked_sub(1)?;

//         // TODO: skip empty contours

//         let last_point = self.endpoints.next();
//         let flags = self.flags.next()?;
//         Some(GlyphPoint {
//             x: self
//                 .x_coords
//                 .next(flags.x_short(), flags.x_is_same_or_positive_short()),
//             y: self
//                 .y_coords
//                 .next(flags.y_short(), flags.y_is_same_or_positive_short()),
//             on_curve_point: flags.on_curve_point(),
//             last_point,
//         })
//     }
// }

// /// A simple flattening iterator for glyph's endpoints.
// ///
// /// Translates endpoints like: 2 4 7
// /// into flags: 0 0 1 0 1 0 0 1
// #[derive(Clone, Copy, Default)]
// struct EndpointsIter<'a> {
//     endpoints: LazyArray16<'a, u16>, // Each endpoint indicates a contour end.
//     index: u16,
//     left: u16,
// }

// impl<'a> EndpointsIter<'a> {
//     #[inline]
//     fn new(endpoints: LazyArray16<'a, u16>) -> Option<Self> {
//         Some(EndpointsIter {
//             endpoints,
//             index: 1,
//             left: endpoints.get(0)?,
//         })
//     }

//     #[inline]
//     fn next(&mut self) -> bool {
//         if self.left == 0 {
//             if let Some(end) = self.endpoints.get(self.index) {
//                 let prev = self.endpoints.get(self.index - 1).unwrap_or(0);
//                 // Malformed font can have endpoints not in increasing order,
//                 // so we have to use checked_sub.
//                 self.left = end.saturating_sub(prev);
//                 self.left = self.left.saturating_sub(1);
//             }

//             // Always advance the index, so we can check the current contour number.
//             if let Some(n) = self.index.checked_add(1) {
//                 self.index = n;
//             }

//             true
//         } else {
//             self.left -= 1;
//             false
//         }
//     }
// }

// #[derive(Clone, Default)]
// struct FlagsIter<'a> {
//     stream: Stream<'a>,
//     // Number of times the `flags` should be used
//     // before reading the next one from `stream`.
//     repeats: u8,
//     flags: SimpleGlyphFlags,
// }

// impl<'a> FlagsIter<'a> {
//     #[inline]
//     fn new(data: &'a [u8]) -> Self {
//         FlagsIter {
//             stream: Stream::new(data),
//             repeats: 0,
//             flags: SimpleGlyphFlags(0),
//         }
//     }
// }

// impl<'a> Iterator for FlagsIter<'a> {
//     type Item = SimpleGlyphFlags;

//     #[inline]
//     fn next(&mut self) -> Option<Self::Item> {
//         if self.repeats == 0 {
//             self.flags = SimpleGlyphFlags(self.stream.read::<u8>().unwrap_or(0));
//             if self.flags.repeat_flag() {
//                 self.repeats = self.stream.read::<u8>().unwrap_or(0);
//             }
//         } else {
//             self.repeats -= 1;
//         }

//         Some(self.flags)
//     }
// }

// #[derive(Clone, Default)]
// struct CoordsIter<'a> {
//     stream: Stream<'a>,
//     prev: i16, // Points are stored as deltas, so we have to keep the previous one.
// }

// impl<'a> CoordsIter<'a> {
//     #[inline]
//     fn new(data: &'a [u8]) -> Self {
//         CoordsIter {
//             stream: Stream::new(data),
//             prev: 0,
//         }
//     }

//     #[inline]
//     fn next(&mut self, is_short: bool, is_same_or_short: bool) -> i16 {
//         // See https://docs.microsoft.com/en-us/typography/opentype/spec/glyf#simple-glyph-description
//         // for details about Simple Glyph Flags processing.

//         // We've already checked the coords data, so it's safe to fallback to 0.

//         let mut n = 0;
//         if is_short {
//             n = i16::from(self.stream.read::<u8>().unwrap_or(0));
//             if !is_same_or_short {
//                 n = -n;
//             }
//         } else if !is_same_or_short {
//             n = self.stream.read::<i16>().unwrap_or(0);
//         }

//         self.prev = self.prev.wrapping_add(n);
//         self.prev
//     }
// }

// #[derive(Clone, Copy, Debug)]
// struct Point {
//     x: f32,
//     y: f32,
// }

// impl Point {
//     #[inline]
//     fn lerp(self, other: Point, t: f32) -> Point {
//         Point {
//             x: self.x + t * (other.x - self.x),
//             y: self.y + t * (other.y - self.y),
//         }
//     }
// }

// // https://docs.microsoft.com/en-us/typography/opentype/spec/glyf#simple-glyph-description
// #[derive(Clone, Copy, Default)]
// struct SimpleGlyphFlags(u8);

// #[rustfmt::skip]
// impl SimpleGlyphFlags {
//     #[inline] fn on_curve_point(self) -> bool { self.0 & 0x01 != 0 }
//     #[inline] fn x_short(self) -> bool { self.0 & 0x02 != 0 }
//     #[inline] fn y_short(self) -> bool { self.0 & 0x04 != 0 }
//     #[inline] fn repeat_flag(self) -> bool { self.0 & 0x08 != 0 }
//     #[inline] fn x_is_same_or_positive_short(self) -> bool { self.0 & 0x10 != 0 }
//     #[inline] fn y_is_same_or_positive_short(self) -> bool { self.0 & 0x20 != 0 }
// }

// // https://docs.microsoft.com/en-us/typography/opentype/spec/glyf#composite-glyph-description
// #[derive(Clone, Copy, Debug)]
// pub(crate) struct CompositeGlyphFlags(u16);

// #[rustfmt::skip]
// impl CompositeGlyphFlags {
//     #[inline] pub fn arg_1_and_2_are_words(self) -> bool { self.0 & 0x0001 != 0 }
//     #[inline] pub fn args_are_xy_values(self) -> bool { self.0 & 0x0002 != 0 }
//     #[inline] pub fn we_have_a_scale(self) -> bool { self.0 & 0x0008 != 0 }
//     #[inline] pub fn more_components(self) -> bool { self.0 & 0x0020 != 0 }
//     #[inline] pub fn we_have_an_x_and_y_scale(self) -> bool { self.0 & 0x0040 != 0 }
//     #[inline] pub fn we_have_a_two_by_two(self) -> bool { self.0 & 0x0080 != 0 }
// }

// // It's not defined in the spec, so we are using our own value.
// pub(crate) const MAX_COMPONENTS: u8 = 32;

// #[allow(clippy::comparison_chain)]
// #[inline]
// fn outline_impl(
//     loca_table: loca::Table,
//     glyf_table: &[u8],
//     data: &[u8],
//     depth: u8,
//     builder: &mut Builder,
// ) -> Option<Option<Rect>> {
//     if depth >= MAX_COMPONENTS {
//         return None;
//     }

//     let mut s = Stream::new(data);
//     let number_of_contours = s.read::<i16>()?;
//     s.advance(8); // Skip bbox. We use calculated one.

//     if number_of_contours > 0 {
//         // Simple glyph.

//         // u16 casting is safe, since we already checked that the value is positive.
//         let number_of_contours = NonZeroU16::new(number_of_contours as u16)?;
//         for point in parse_simple_outline(s.tail()?, number_of_contours)? {
//             builder.push_point(
//                 f32::from(point.x),
//                 f32::from(point.y),
//                 point.on_curve_point,
//                 point.last_point,
//             );
//         }
//     } else if number_of_contours < 0 {
//         // Composite glyph.
//         for comp in CompositeGlyphIter::new(s.tail()?) {
//             if let Some(range) = loca_table.glyph_range(comp.glyph_id) {
//                 if let Some(glyph_data) = glyf_table.get(range) {
//                     let transform = Transform::combine(builder.transform, comp.transform);
//                     let mut b = Builder::new(transform, builder.bbox, builder.builder);
//                     outline_impl(loca_table, glyf_table, glyph_data, depth + 1, &mut b)?;

//                     // Take updated bbox.
//                     builder.bbox = b.bbox;
//                 }
//             }
//         }
//     }

//     if builder.bbox.is_default() {
//         return Some(None);
//     }

//     Some(builder.bbox.to_rect())
// }

// #[inline]
// pub(crate) fn parse_simple_outline(
//     glyph_data: &[u8],
//     number_of_contours: NonZeroU16,
// ) -> Option<GlyphPointsIter> {
//     let mut s = Stream::new(glyph_data);
//     let endpoints = s.read_array16::<u16>(number_of_contours.get())?;

//     let points_total = endpoints.last()?.checked_add(1)?;

//     // Contours with a single point should be ignored.
//     // But this is not an error, so we should return an "empty" iterator.
//     if points_total == 1 {
//         return Some(GlyphPointsIter::default());
//     }

//     // Skip instructions byte code.
//     let instructions_len = s.read::<u16>()?;
//     s.advance(usize::from(instructions_len));

//     let flags_offset = s.offset();
//     let (x_coords_len, y_coords_len) = resolve_coords_len(&mut s, points_total)?;
//     let x_coords_offset = s.offset();
//     let y_coords_offset = x_coords_offset + usize::num_from(x_coords_len);
//     let y_coords_end = y_coords_offset + usize::num_from(y_coords_len);

//     Some(GlyphPointsIter {
//         endpoints: EndpointsIter::new(endpoints)?,
//         flags: FlagsIter::new(glyph_data.get(flags_offset..x_coords_offset)?),
//         x_coords: CoordsIter::new(glyph_data.get(x_coords_offset..y_coords_offset)?),
//         y_coords: CoordsIter::new(glyph_data.get(y_coords_offset..y_coords_end)?),
//         points_left: points_total,
//     })
// }

// /// Resolves coordinate arrays length.
// ///
// /// The length depends on *Simple Glyph Flags*, so we have to process them all to find it.
// fn resolve_coords_len(s: &mut Stream, points_total: u16) -> Option<(u32, u32)> {
//     let mut flags_left = u32::from(points_total);
//     let mut repeats;
//     let mut x_coords_len = 0;
//     let mut y_coords_len = 0;
//     while flags_left > 0 {
//         let flags = SimpleGlyphFlags(s.read::<u8>()?);

//         // The number of times a glyph point repeats.
//         repeats = if flags.repeat_flag() {
//             let repeats = s.read::<u8>()?;
//             u32::from(repeats) + 1
//         } else {
//             1
//         };

//         if repeats > flags_left {
//             return None;
//         }

//         // No need to check for `*_coords_len` overflow since u32 is more than enough.

//         // Non-obfuscated code below.
//         // Branchless version is surprisingly faster.
//         //
//         // if flags.x_short() {
//         //     // Coordinate is 1 byte long.
//         //     x_coords_len += repeats;
//         // } else if !flags.x_is_same_or_positive_short() {
//         //     // Coordinate is 2 bytes long.
//         //     x_coords_len += repeats * 2;
//         // }
//         // if flags.y_short() {
//         //     // Coordinate is 1 byte long.
//         //     y_coords_len += repeats;
//         // } else if !flags.y_is_same_or_positive_short() {
//         //     // Coordinate is 2 bytes long.
//         //     y_coords_len += repeats * 2;
//         // }

//         x_coords_len += (flags.0 & 0x02 != 0) as u32 * repeats;
//         x_coords_len += (flags.0 & (0x02 | 0x10) == 0) as u32 * (repeats * 2);

//         y_coords_len += (flags.0 & 0x04 != 0) as u32 * repeats;
//         y_coords_len += (flags.0 & (0x04 | 0x20) == 0) as u32 * (repeats * 2);

//         flags_left -= repeats;
//     }

//     Some((x_coords_len, y_coords_len))
// }

// /// A [Glyph Data Table](
// /// https://docs.microsoft.com/en-us/typography/opentype/spec/glyf).
// #[derive(Clone, Copy)]
// pub struct Table<'a> {
//     pub(crate) data: &'a [u8],
//     loca_table: loca::Table<'a>,
// }

// impl core::fmt::Debug for Table<'_> {
//     fn fmt(&self, f: &mut core::fmt::Formatter) -> core::fmt::Result {
//         write!(f, "Table {{ ... }}")
//     }
// }

// impl<'a> Table<'a> {
//     /// Parses a table from raw data.
//     #[inline]
//     pub fn parse(loca_table: loca::Table<'a>, data: &'a [u8]) -> Option<Self> {
//         Some(Table { loca_table, data })
//     }

//     /// Outlines a glyph.
//     #[inline]
//     pub fn outline(&self, glyph_id: GlyphId, builder: &mut dyn OutlineBuilder) -> Option<Rect> {
//         let mut b = Builder::new(Transform::default(), RectF::new(), builder);
//         let glyph_data = self.get(glyph_id)?;
//         outline_impl(self.loca_table, self.data, glyph_data, 0, &mut b)?
//     }

//     #[inline]
//     pub(crate) fn get(&self, glyph_id: GlyphId) -> Option<&'a [u8]> {
//         let range = self.loca_table.glyph_range(glyph_id)?;
//         self.data.get(range)
//     }
// }
