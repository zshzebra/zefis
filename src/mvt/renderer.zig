const std = @import("std");
const rl = @import("raylib");
const projection = @import("projection.zig");
const style = @import("style.zig");
const tile_cache = @import("tile_cache.zig");
const earcut = @import("earcut.zig");

pub const Renderer = struct {
    projection: projection.Projection,
    style: style.Style,
    allocator: std.mem.Allocator,
    render_texture: ?rl.RenderTexture2D,
    needs_redraw: bool,
    scratch_arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, proj: projection.Projection) Renderer {
        return .{
            .projection = proj,
            .style = style.Style.init(),
            .allocator = allocator,
            .render_texture = null,
            .needs_redraw = true,
            .scratch_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Renderer) void {
        if (self.render_texture) |tex| {
            rl.unloadRenderTexture(tex);
        }
        self.scratch_arena.deinit();
    }

    pub fn setProjection(self: *Renderer, proj: projection.Projection) void {
        self.projection = proj;
    }

    pub fn markNeedsRedraw(self: *Renderer) void {
        self.needs_redraw = true;
    }

    pub fn resetScratchMemory(self: *Renderer) void {
        _ = self.scratch_arena.reset(.retain_capacity);
    }

    pub fn ensureRenderTexture(self: *Renderer, width: i32, height: i32) !void {
        if (self.render_texture) |tex| {
            if (tex.texture.width != width or tex.texture.height != height) {
                rl.unloadRenderTexture(tex);
                self.render_texture = null;
            }
        }

        if (self.render_texture == null) {
            self.render_texture = try rl.loadRenderTexture(width, height);
            self.needs_redraw = true;
        }
    }

    pub fn drawTile(self: *Renderer, cached_tile: *tile_cache.CachedTile) !void {
        try self.drawTileAtPosition(cached_tile, 0, 0);
    }

    pub fn drawTileAtPosition(self: *Renderer, cached_tile: *tile_cache.CachedTile, grid_x: i32, grid_y: i32) !void {
        for (cached_tile.layers) |*layer| {
            try self.drawLayer(layer, grid_x, grid_y);
        }
    }

    fn drawLayer(self: *Renderer, layer: *tile_cache.DecodedLayer, grid_x: i32, grid_y: i32) !void {
        for (layer.features) |*feature| {
            if (feature.geometry_type == .polygon) {
                try self.drawFeature(layer.name, feature, grid_x, grid_y);
            }
        }

        for (layer.features) |*feature| {
            if (feature.geometry_type == .linestring) {
                try self.drawFeature(layer.name, feature, grid_x, grid_y);
            }
        }

        for (layer.features) |*feature| {
            if (feature.geometry_type == .point) {
                try self.drawFeature(layer.name, feature, grid_x, grid_y);
            }
        }
    }

    fn drawFeature(self: *Renderer, layer_name: []const u8, feature: *tile_cache.DecodedFeature, grid_x: i32, grid_y: i32) !void {
        switch (feature.geometry) {
            .unknown => {},
            .point => |points| try self.drawPoints(points, feature.properties, grid_x, grid_y),
            .linestring => |lines| try self.drawLineStrings(layer_name, lines, feature.properties, grid_x, grid_y),
            .polygon => |polygons| try self.drawPolygons(layer_name, polygons, feature.properties, grid_x, grid_y),
        }
    }

    fn drawPoints(self: *Renderer, points: []tile_cache.DecodedGeometry.Point, properties: style.PropertyMap, grid_x: i32, grid_y: i32) !void {
        const color = self.style.getPointColor(properties);
        const radius = self.style.getPointRadius(properties);

        for (points) |point| {
            const screen_pos = self.projection.tileToScreen(point.x, point.y, grid_x, grid_y);
            rl.drawCircleV(screen_pos, radius, color);
        }
    }

    fn drawLineStrings(self: *Renderer, layer_name: []const u8, lines: []tile_cache.DecodedGeometry.LineString, properties: style.PropertyMap, grid_x: i32, grid_y: i32) !void {
        const color = self.style.getStrokeColor(layer_name, properties);
        const width = self.style.getLineWidth(layer_name, properties);

        for (lines) |line| {
            if (line.points.len < 2) continue;

            for (0..line.points.len - 1) |i| {
                const p1 = self.projection.tileToScreen(line.points[i].x, line.points[i].y, grid_x, grid_y);
                const p2 = self.projection.tileToScreen(line.points[i + 1].x, line.points[i + 1].y, grid_x, grid_y);
                rl.drawLineEx(p1, p2, width, color);
            }
        }
    }

    fn drawPolygons(self: *Renderer, layer_name: []const u8, polygons: []tile_cache.DecodedGeometry.Polygon, properties: style.PropertyMap, grid_x: i32, grid_y: i32) !void {
        const fill_color = self.style.getFillColor(layer_name, properties);
        const stroke_color = self.style.getStrokeColor(layer_name, properties);

        const draw_outline = std.mem.eql(u8, layer_name, "building") or
                           std.mem.eql(u8, layer_name, "admin");

        for (polygons) |polygon| {
            for (polygon.rings) |ring| {
                if (ring.points.len < 3) continue;

                const screen_points = try self.scratch_arena.allocator().alloc(rl.Vector2, ring.points.len);

                for (ring.points, 0..) |point, i| {
                    screen_points[i] = self.projection.tileToScreen(point.x, point.y, grid_x, grid_y);
                }

                switch (ring.ring_type) {
                    .outer => {
                        if (screen_points.len >= 3) {
                            self.drawFilledPolygon(screen_points, fill_color);
                        }
                        if (draw_outline) {
                            self.drawPolygonOutline(screen_points, stroke_color, 1.0);
                        }
                    },
                    .inner => {
                        if (screen_points.len >= 3) {
                            self.drawFilledPolygon(screen_points, rl.Color.white);
                        }
                        if (draw_outline) {
                            self.drawPolygonOutline(screen_points, stroke_color, 1.0);
                        }
                    },
                }
            }
        }
    }

    fn drawFilledPolygon(self: *Renderer, points: []rl.Vector2, color: rl.Color) void {
        if (points.len < 3) return;

        const vertices = self.scratch_arena.allocator().alloc(f32, points.len * 2) catch {
            self.drawFilledPolygonFan(points, color);
            return;
        };

        for (points, 0..) |point, i| {
            vertices[i * 2] = point.x;
            vertices[i * 2 + 1] = point.y;
        }

        const indices = earcut.earcut(self.scratch_arena.allocator(), vertices, null, 2) catch {
            self.drawFilledPolygonFan(points, color);
            return;
        };

        var i: usize = 0;
        while (i < indices.len) : (i += 3) {
            if (i + 2 >= indices.len) break;
            const idx0 = indices[i];
            const idx1 = indices[i + 1];
            const idx2 = indices[i + 2];
            if (idx0 < points.len and idx1 < points.len and idx2 < points.len) {
                rl.drawTriangle(points[idx0], points[idx1], points[idx2], color);
            }
        }
    }

    fn drawFilledPolygonFan(self: *Renderer, points: []rl.Vector2, color: rl.Color) void {
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
