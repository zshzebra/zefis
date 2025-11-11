const std = @import("std");
const rl = @import("raylib");

pub const Viewport = struct {
    width: f32,
    height: f32,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    scale: f32 = 1.0,
};

/// Coordinate transformation from MVT tile space to screen pixels
pub const Projection = struct {
    viewport: Viewport,
    extent: u32,

    pub fn init(viewport: Viewport, extent: u32) Projection {
        return .{
            .viewport = viewport,
            .extent = extent,
        };
    }

    /// Convert tile coordinates to screen position
    pub fn tileToScreen(self: Projection, tile_x: i32, tile_y: i32) rl.Vector2 {
        const norm_x = @as(f32, @floatFromInt(tile_x)) / @as(f32, @floatFromInt(self.extent));
        const norm_y = @as(f32, @floatFromInt(tile_y)) / @as(f32, @floatFromInt(self.extent));

        const screen_size = @min(self.viewport.width, self.viewport.height);
        const scaled_size = screen_size * self.viewport.scale;

        const center_x = self.viewport.width / 2.0 + self.viewport.offset_x;
        const center_y = self.viewport.height / 2.0 + self.viewport.offset_y;

        const screen_x = center_x + (norm_x - 0.5) * scaled_size;
        const screen_y = center_y + (norm_y - 0.5) * scaled_size;

        return .{ .x = screen_x, .y = screen_y };
    }

    pub fn tilePointsToScreen(
        self: Projection,
        allocator: std.mem.Allocator,
        points: []const struct { x: i32, y: i32 },
    ) ![]rl.Vector2 {
        const screen_points = try allocator.alloc(rl.Vector2, points.len);
        for (points, 0..) |point, i| {
            screen_points[i] = self.tileToScreen(point.x, point.y);
        }
        return screen_points;
    }

    pub fn setViewportSize(self: *Projection, width: f32, height: f32) void {
        self.viewport.width = width;
        self.viewport.height = height;
    }

    pub fn setScale(self: *Projection, scale: f32) void {
        self.viewport.scale = scale;
    }

    pub fn setOffset(self: *Projection, offset_x: f32, offset_y: f32) void {
        self.viewport.offset_x = offset_x;
        self.viewport.offset_y = offset_y;
    }
};
