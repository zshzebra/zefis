const std = @import("std");
const rl = @import("raylib");
const projection = @import("projection.zig");
const style = @import("style.zig");
const tile_cache = @import("tile_cache.zig");

pub const Renderer = struct {
    projection: projection.Projection,
    style: style.Style,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, proj: projection.Projection) Renderer {
        return .{
            .projection = proj,
            .style = style.Style.init(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = self;
    }

    pub fn setProjection(self: *Renderer, proj: projection.Projection) void {
        self.projection = proj;
    }

    pub fn drawTile(self: *Renderer, cached_tile: *tile_cache.CachedTile) !void {
        for (cached_tile.layers) |*layer| {
            try self.drawLayer(layer);
        }
    }

    fn drawLayer(self: *Renderer, layer: *tile_cache.DecodedLayer) !void {
        for (layer.features) |*feature| {
            if (feature.geometry_type == .polygon) {
                try self.drawFeature(feature);
            }
        }

        for (layer.features) |*feature| {
            if (feature.geometry_type == .linestring) {
                try self.drawFeature(feature);
            }
        }

        for (layer.features) |*feature| {
            if (feature.geometry_type == .point) {
                try self.drawFeature(feature);
            }
        }
    }

    fn drawFeature(self: *Renderer, feature: *tile_cache.DecodedFeature) !void {
        switch (feature.geometry) {
            .unknown => {},
            .point => |points| try self.drawPoints(points, feature.properties),
            .linestring => |lines| try self.drawLineStrings(lines, feature.properties),
            .polygon => |polygons| try self.drawPolygons(polygons, feature.properties),
        }
    }

    fn drawPoints(self: *Renderer, points: []tile_cache.DecodedGeometry.Point, properties: style.PropertyMap) !void {
        const color = self.style.getPointColor(properties);
        const radius = self.style.getPointRadius(properties);

        for (points) |point| {
            const screen_pos = self.projection.tileToScreen(point.x, point.y);
            rl.drawCircleV(screen_pos, radius, color);
        }
    }

    fn drawLineStrings(self: *Renderer, lines: []tile_cache.DecodedGeometry.LineString, properties: style.PropertyMap) !void {
        const color = self.style.getStrokeColor(properties);
        const width = self.style.getLineWidth(properties);

        for (lines) |line| {
            if (line.points.len < 2) continue;

            for (0..line.points.len - 1) |i| {
                const p1 = self.projection.tileToScreen(line.points[i].x, line.points[i].y);
                const p2 = self.projection.tileToScreen(line.points[i + 1].x, line.points[i + 1].y);
                rl.drawLineEx(p1, p2, width, color);
            }
        }
    }

    fn drawPolygons(self: *Renderer, polygons: []tile_cache.DecodedGeometry.Polygon, properties: style.PropertyMap) !void {
        const fill_color = self.style.getFillColor(properties);
        const stroke_color = self.style.getStrokeColor(properties);

        for (polygons) |polygon| {
            for (polygon.rings) |ring| {
                if (ring.points.len < 3) continue;

                const screen_points = try self.allocator.alloc(rl.Vector2, ring.points.len);
                defer self.allocator.free(screen_points);

                for (ring.points, 0..) |point, i| {
                    screen_points[i] = self.projection.tileToScreen(point.x, point.y);
                }

                switch (ring.ring_type) {
                    .outer => {
                        if (screen_points.len >= 3) {
                            self.drawFilledPolygon(screen_points, fill_color);
                        }
                        self.drawPolygonOutline(screen_points, stroke_color, 1.0);
                    },
                    .inner => {
                        if (screen_points.len >= 3) {
                            self.drawFilledPolygon(screen_points, rl.Color.white);
                        }
                        self.drawPolygonOutline(screen_points, stroke_color, 1.0);
                    },
                }
            }
        }
    }

    fn drawFilledPolygon(self: *Renderer, points: []rl.Vector2, color: rl.Color) void {
        _ = self;
        if (points.len < 3) return;

        const center = points[0];
        for (1..points.len - 1) |i| {
            rl.drawTriangle(center, points[i], points[i + 1], color);
        }
    }

    fn drawPolygonOutline(self: *Renderer, points: []rl.Vector2, color: rl.Color, width: f32) void {
        _ = self;
        if (points.len < 2) return;

        for (0..points.len - 1) |i| {
            rl.drawLineEx(points[i], points[i + 1], width, color);
        }

        rl.drawLineEx(points[points.len - 1], points[0], width, color);
    }
};
