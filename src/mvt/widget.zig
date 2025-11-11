const std = @import("std");
const rl = @import("raylib");
const projection = @import("projection.zig");
const renderer = @import("renderer.zig");
const tile_cache = @import("tile_cache.zig");

/// Widget for rendering Mapbox Vector Tiles
pub const MVTWidget = struct {
    allocator: std.mem.Allocator,
    cache: tile_cache.TileCache,
    renderer: renderer.Renderer,
    viewport: projection.Viewport,
    cached_viewport: projection.Viewport,

    /// Initialize widget with viewport dimensions
    pub fn init(allocator: std.mem.Allocator, width: f32, height: f32) MVTWidget {
        const viewport = projection.Viewport{
            .width = width,
            .height = height,
            .offset_x = 0,
            .offset_y = 0,
            .scale = 1.0,
        };

        const proj = projection.Projection.init(viewport, 4096);
        const rend = renderer.Renderer.init(allocator, proj);

        return .{
            .allocator = allocator,
            .cache = tile_cache.TileCache.init(allocator),
            .renderer = rend,
            .viewport = viewport,
            .cached_viewport = viewport,
        };
    }

    pub fn deinit(self: *MVTWidget) void {
        self.renderer.deinit();
        self.cache.deinit();
    }

    /// Load and decode an MVT tile from file
    pub fn loadTileFromFile(self: *MVTWidget, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const data = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(data);

        _ = try file.readAll(data);

        try self.cache.loadTile(data);

        if (self.cache.getTile()) |tile| {
            const proj = projection.Projection.init(self.viewport, tile.extent);
            self.renderer.setProjection(proj);
        }
    }

    /// Load and decode an MVT tile from raw bytes
    pub fn loadTileFromData(self: *MVTWidget, data: []const u8) !void {
        try self.cache.loadTile(data);

        if (self.cache.getTile()) |tile| {
            const proj = projection.Projection.init(self.viewport, tile.extent);
            self.renderer.setProjection(proj);
        }
    }

    /// Update viewport size (call when window is resized)
    pub fn setViewportSize(self: *MVTWidget, width: f32, height: f32) void {
        self.viewport.width = width;
        self.viewport.height = height;

        if (self.cache.getTile()) |tile| {
            const proj = projection.Projection.init(self.viewport, tile.extent);
            self.renderer.setProjection(proj);
        }
        self.renderer.markNeedsRedraw();
    }

    /// Set zoom level (1.0 = default, 2.0 = 2x zoom)
    pub fn setZoom(self: *MVTWidget, scale: f32) void {
        if (self.viewport.scale != scale) {
            self.viewport.scale = scale;
            self.renderer.markNeedsRedraw();

            if (self.cache.getTile()) |tile| {
                const proj = projection.Projection.init(self.viewport, tile.extent);
                self.renderer.setProjection(proj);
            }
        }
    }

    /// Set pan offset in screen coordinates
    pub fn setPan(self: *MVTWidget, offset_x: f32, offset_y: f32) void {
        if (self.viewport.offset_x != offset_x or self.viewport.offset_y != offset_y) {
            self.viewport.offset_x = offset_x;
            self.viewport.offset_y = offset_y;
            self.renderer.markNeedsRedraw();

            if (self.cache.getTile()) |tile| {
                const proj = projection.Projection.init(self.viewport, tile.extent);
                self.renderer.setProjection(proj);
            }
        }
    }

    pub fn needsRedraw(self: *MVTWidget) bool {
        return self.renderer.needs_redraw;
    }

    fn isTileVisible(self: *MVTWidget, grid_x: i32, grid_y: i32) bool {
        const screen_size = @min(self.viewport.width, self.viewport.height);
        const scaled_size = screen_size * self.viewport.scale;

        const render_width = self.viewport.width * 2.0;
        const render_height = self.viewport.height * 2.0;

        const center_x = render_width / 2.0 + self.viewport.offset_x;
        const center_y = render_height / 2.0 + self.viewport.offset_y;

        const grid_offset_x = @as(f32, @floatFromInt(grid_x)) * scaled_size;
        const grid_offset_y = @as(f32, @floatFromInt(grid_y)) * scaled_size;

        const tile_left = center_x - scaled_size / 2.0 + grid_offset_x;
        const tile_right = center_x + scaled_size / 2.0 + grid_offset_x;
        const tile_top = center_y - scaled_size / 2.0 + grid_offset_y;
        const tile_bottom = center_y + scaled_size / 2.0 + grid_offset_y;

        const margin = scaled_size;
        return tile_right >= -margin and tile_left <= render_width + margin and
            tile_bottom >= -margin and tile_top <= render_height + margin;
    }

    /// Render tiles to texture (call when idle)
    pub fn renderToTexture(self: *MVTWidget) !void {
        const width = @as(i32, @intFromFloat(self.viewport.width * 2.0));
        const height = @as(i32, @intFromFloat(self.viewport.height * 2.0));

        try self.renderer.ensureRenderTexture(width, height);

        if (self.renderer.render_texture) |tex| {
            var render_viewport = self.viewport;
            render_viewport.width = self.viewport.width * 2.0;
            render_viewport.height = self.viewport.height * 2.0;

            if (self.cache.getTile()) |tile| {
                const proj = projection.Projection.init(render_viewport, tile.extent);
                self.renderer.setProjection(proj);
            }

            rl.beginTextureMode(tex);
            rl.clearBackground(rl.Color.init(240, 240, 235, 255));

            const grid_positions = [_]struct { x: i32, y: i32 }{
                .{ .x = -1, .y = -1 },
                .{ .x = 0, .y = -1 },
                .{ .x = -1, .y = 0 },
                .{ .x = 0, .y = 0 },
            };

            if (self.cache.getTile()) |cached_tile| {
                for (grid_positions) |pos| {
                    if (self.isTileVisible(pos.x, pos.y)) {
                        try self.renderer.drawTileAtPosition(cached_tile, pos.x, pos.y);
                    }
                }
            }

            rl.endTextureMode();
            self.renderer.needs_redraw = false;
            self.cached_viewport = render_viewport;

            self.renderer.resetScratchMemory();
        }
    }

    /// Draw cached texture to screen with current zoom/pan transforms
    pub fn draw(self: *MVTWidget, mouse_pos: rl.Vector2) !void {
        _ = mouse_pos;
        if (self.renderer.render_texture) |tex| {
            const scale_factor = self.viewport.scale / self.cached_viewport.scale;

            const src = rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(tex.texture.width),
                .height = -@as(f32, @floatFromInt(tex.texture.height)),
            };

            const scaled_width = self.cached_viewport.width * scale_factor;
            const scaled_height = self.cached_viewport.height * scale_factor;

            // Calculate where the world center appears in cached vs current viewport
            const cached_center_x = self.cached_viewport.width / 2.0 + self.cached_viewport.offset_x;
            const cached_center_y = self.cached_viewport.height / 2.0 + self.cached_viewport.offset_y;

            const current_center_x = self.viewport.width / 2.0 + self.viewport.offset_x;
            const current_center_y = self.viewport.height / 2.0 + self.viewport.offset_y;

            const dst = rl.Rectangle{
                .x = current_center_x - cached_center_x * scale_factor,
                .y = current_center_y - cached_center_y * scale_factor,
                .width = scaled_width,
                .height = scaled_height,
            };

            rl.drawTexturePro(tex.texture, src, dst, rl.Vector2.zero(), 0, rl.Color.white);
        }
    }

    /// Get metadata about the currently loaded tile
    pub fn getTileInfo(self: *MVTWidget) ?TileInfo {
        if (self.cache.getTile()) |tile| {
            return .{
                .extent = tile.extent,
                .num_layers = tile.layers.len,
            };
        }
        return null;
    }

    /// Get metadata about a specific layer by index
    pub fn getLayerInfo(self: *MVTWidget, layer_index: usize) ?LayerInfo {
        if (self.cache.getTile()) |tile| {
            if (layer_index < tile.layers.len) {
                const layer = &tile.layers[layer_index];
                return .{
                    .name = layer.name,
                    .version = layer.version,
                    .extent = layer.extent,
                    .num_features = layer.features.len,
                };
            }
        }
        return null;
    }
};

pub const TileInfo = struct {
    extent: u32,
    num_layers: usize,
};

pub const LayerInfo = struct {
    name: []const u8,
    version: u32,
    extent: u32,
    num_features: usize,
};
