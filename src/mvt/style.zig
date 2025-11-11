const std = @import("std");
const rl = @import("raylib");
const vtzero = @import("vtzero");

pub const Style = struct {
    default_fill_color: rl.Color = rl.Color.gray,
    default_stroke_color: rl.Color = rl.Color.dark_gray,
    default_point_color: rl.Color = rl.Color.red,
    default_line_width: f32 = 2.0,
    default_point_radius: f32 = 4.0,

    pub fn init() Style {
        return .{};
    }

    pub fn getFillColor(self: Style, properties: PropertyMap) rl.Color {
        if (properties.get("building")) |_| {
            return rl.Color.init(180, 160, 140, 255);
        }
        if (properties.get("water")) |_| {
            return rl.Color.init(170, 211, 223, 255);
        }
        if (properties.get("landuse")) |value| {
            if (std.mem.eql(u8, value, "forest") or std.mem.eql(u8, value, "park")) {
                return rl.Color.init(170, 217, 150, 255);
            }
        }
        if (properties.get("natural")) |value| {
            if (std.mem.eql(u8, value, "wood") or std.mem.eql(u8, value, "forest")) {
                return rl.Color.init(150, 200, 130, 255);
            }
        }

        return self.default_fill_color;
    }

    pub fn getStrokeColor(self: Style, properties: PropertyMap) rl.Color {
        if (properties.get("highway")) |_| {
            return rl.Color.init(255, 200, 100, 255);
        }
        if (properties.get("railway")) |_| {
            return rl.Color.init(100, 100, 100, 255);
        }
        if (properties.get("waterway")) |_| {
            return rl.Color.init(100, 150, 200, 255);
        }

        return self.default_stroke_color;
    }

    pub fn getLineWidth(self: Style, properties: PropertyMap) f32 {
        if (properties.get("highway")) |highway_type| {
            if (std.mem.eql(u8, highway_type, "motorway")) {
                return 4.0;
            } else if (std.mem.eql(u8, highway_type, "primary")) {
                return 3.0;
            } else if (std.mem.eql(u8, highway_type, "secondary")) {
                return 2.5;
            }
            return 2.0;
        }

        return self.default_line_width;
    }

    pub fn getPointColor(self: Style, properties: PropertyMap) rl.Color {
        if (properties.get("amenity")) |_| {
            return rl.Color.init(200, 100, 100, 255);
        }
        if (properties.get("shop")) |_| {
            return rl.Color.init(100, 200, 100, 255);
        }

        return self.default_point_color;
    }

    pub fn getPointRadius(self: Style, properties: PropertyMap) f32 {
        if (properties.get("place")) |place_type| {
            if (std.mem.eql(u8, place_type, "city")) {
                return 8.0;
            } else if (std.mem.eql(u8, place_type, "town")) {
                return 6.0;
            }
            return 4.0;
        }

        return self.default_point_radius;
    }
};

pub const PropertyMap = struct {
    keys: [][]const u8,
    values: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PropertyMap {
        return .{
            .keys = &.{},
            .values = &.{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: PropertyMap) void {
        self.allocator.free(self.keys);
        self.allocator.free(self.values);
    }

    pub fn add(self: *PropertyMap, key: []const u8, value: []const u8) !void {
        const new_keys = try self.allocator.realloc(self.keys, self.keys.len + 1);
        const new_values = try self.allocator.realloc(self.values, self.values.len + 1);
        self.keys = new_keys;
        self.values = new_values;
        self.keys[self.keys.len - 1] = key;
        self.values[self.values.len - 1] = value;
    }

    pub fn get(self: PropertyMap, key: []const u8) ?[]const u8 {
        for (self.keys, 0..) |k, i| {
            if (std.mem.eql(u8, k, key)) {
                return self.values[i];
            }
        }
        return null;
    }

    pub fn count(self: PropertyMap) usize {
        return self.keys.len;
    }
};
