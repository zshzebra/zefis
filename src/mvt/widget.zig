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
    }

    /// Set zoom level (1.0 = default, 2.0 = 2x zoom)
    pub fn setZoom(self: *MVTWidget, scale: f32) void {
        self.viewport.scale = scale;

        if (self.cache.getTile()) |tile| {
            const proj = projection.Projection.init(self.viewport, tile.extent);
            self.renderer.setProjection(proj);
        }
    }

    /// Set pan offset in screen coordinates
    pub fn setPan(self: *MVTWidget, offset_x: f32, offset_y: f32) void {
        self.viewport.offset_x = offset_x;
        self.viewport.offset_y = offset_y;

        if (self.cache.getTile()) |tile| {
            const proj = projection.Projection.init(self.viewport, tile.extent);
            self.renderer.setProjection(proj);
        }
    }

    /// Render the currently loaded tile
    pub fn draw(self: *MVTWidget) !void {
        if (self.cache.getTile()) |tile| {
            try self.renderer.drawTile(tile);
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
