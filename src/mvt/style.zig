const std = @import("std");
const rl = @import("raylib");
const vtzero = @import("vtzero");

pub const Style = struct {
    default_fill_color: rl.Color = rl.Color.gray,
    default_stroke_color: rl.Color = rl.Color.dark_gray,
    default_point_color: rl.Color = rl.Color.red,
    default_line_width: f32 = 2.0,
    default_point_radius: f32 = 4.0,
    opacity: f32 = 1.0,

    pub fn init() Style {
        return .{};
    }

    pub fn withOpacity(opacity: f32) Style {
        return .{ .opacity = opacity };
    }

    pub fn getFillColor(self: Style, layer_name: []const u8, properties: PropertyMap) rl.Color {
        // Check layer name first (Mapbox Streets uses layer names as primary classification)
        const color = if (std.mem.eql(u8, layer_name, "water"))
            rl.Color.init(170, 211, 223, 255) // Light blue
        else if (std.mem.eql(u8, layer_name, "building"))
            rl.Color.init(180, 160, 140, 255) // Tan
        else if (std.mem.eql(u8, layer_name, "landuse")) blk: {
            // Check class property for landuse
            if (properties.get("class")) |class| {
                if (std.mem.eql(u8, class, "park") or std.mem.eql(u8, class, "grass")) {
                    break :blk rl.Color.init(200, 230, 180, 255); // Light green
                } else if (std.mem.eql(u8, class, "wood") or std.mem.eql(u8, class, "forest")) {
                    break :blk rl.Color.init(170, 217, 150, 255); // Forest green
                } else if (std.mem.eql(u8, class, "agriculture")) {
                    break :blk rl.Color.init(240, 235, 200, 255); // Wheat
                } else if (std.mem.eql(u8, class, "residential")) {
                    break :blk rl.Color.init(225, 225, 220, 255); // Light gray
                }
            }
            break :blk rl.Color.init(220, 220, 210, 255); // Default landuse
        } else if (std.mem.eql(u8, layer_name, "landcover")) blk: {
            if (properties.get("class")) |class| {
                if (std.mem.eql(u8, class, "grass")) {
                    break :blk rl.Color.init(200, 230, 180, 255);
                } else if (std.mem.eql(u8, class, "wood")) {
                    break :blk rl.Color.init(170, 217, 150, 255);
                }
            }
            break :blk rl.Color.init(220, 230, 210, 255);
        } else if (properties.get("building")) |_|
            rl.Color.init(180, 160, 140, 255)
        else if (properties.get("water")) |_|
            rl.Color.init(170, 211, 223, 255)
        else if (properties.get("landuse")) |value| blk: {
            if (std.mem.eql(u8, value, "forest") or std.mem.eql(u8, value, "park")) {
                break :blk rl.Color.init(170, 217, 150, 255);
            }
            break :blk self.default_fill_color;
        } else if (properties.get("natural")) |value| blk: {
            if (std.mem.eql(u8, value, "wood") or std.mem.eql(u8, value, "forest")) {
                break :blk rl.Color.init(150, 200, 130, 255);
            }
            break :blk self.default_fill_color;
        } else
            self.default_fill_color;

        return self.applyOpacity(color);
    }

    pub fn getStrokeColor(self: Style, layer_name: []const u8, properties: PropertyMap) rl.Color {
        // Check layer name first
        const color = if (std.mem.eql(u8, layer_name, "road")) blk: {
            // Road colors based on class
            if (properties.get("class")) |class| {
                if (std.mem.eql(u8, class, "motorway")) {
                    break :blk rl.Color.init(255, 140, 0, 255); // Orange
                } else if (std.mem.eql(u8, class, "primary")) {
                    break :blk rl.Color.init(255, 200, 100, 255); // Yellow-orange
                } else if (std.mem.eql(u8, class, "secondary") or std.mem.eql(u8, class, "tertiary")) {
                    break :blk rl.Color.init(255, 230, 150, 255); // Light yellow
                } else if (std.mem.eql(u8, class, "street") or std.mem.eql(u8, class, "street_limited")) {
                    break :blk rl.Color.init(255, 255, 255, 255); // White
                }
            }
            break :blk rl.Color.init(200, 200, 200, 255); // Default road gray
        } else if (std.mem.eql(u8, layer_name, "waterway"))
            rl.Color.init(170, 211, 223, 255) // Water blue
        else if (std.mem.eql(u8, layer_name, "admin"))
            rl.Color.init(180, 160, 180, 255) // Purple-gray for boundaries
        else if (properties.get("highway")) |_|
            rl.Color.init(255, 200, 100, 255)
        else if (properties.get("railway")) |_|
            rl.Color.init(100, 100, 100, 255)
        else if (properties.get("waterway")) |_|
            rl.Color.init(100, 150, 200, 255)
        else
            self.default_stroke_color;

        return self.applyOpacity(color);
    }

    pub fn getLineWidth(self: Style, layer_name: []const u8, properties: PropertyMap) f32 {
        if (std.mem.eql(u8, layer_name, "road")) {
            if (properties.get("class")) |class| {
                if (std.mem.eql(u8, class, "motorway")) {
                    return 4.0;
                } else if (std.mem.eql(u8, class, "primary")) {
                    return 3.0;
                } else if (std.mem.eql(u8, class, "secondary") or std.mem.eql(u8, class, "tertiary")) {
                    return 2.5;
                } else if (std.mem.eql(u8, class, "street") or std.mem.eql(u8, class, "street_limited")) {
                    return 2.0;
                }
                return 1.5;
            }
        } else if (std.mem.eql(u8, layer_name, "waterway")) {
            return 2.0;
        } else if (std.mem.eql(u8, layer_name, "admin")) {
            return 1.0;
        }

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
        const color = if (properties.get("amenity")) |_|
            rl.Color.init(200, 100, 100, 255)
        else if (properties.get("shop")) |_|
            rl.Color.init(100, 200, 100, 255)
        else
            self.default_point_color;

        return self.applyOpacity(color);
    }

    fn applyOpacity(self: Style, color: rl.Color) rl.Color {
        if (self.opacity >= 1.0) return color;

        return rl.Color.init(
            color.r,
            color.g,
            color.b,
            @intFromFloat(@as(f32, @floatFromInt(color.a)) * self.opacity),
        );
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
