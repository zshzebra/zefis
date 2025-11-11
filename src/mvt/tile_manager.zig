const std = @import("std");
const geo = @import("geo.zig");
const tile_server = @import("tile_server.zig");
const disk_cache = @import("disk_cache.zig");
const tile_cache = @import("tile_cache.zig");

/// Manages multiple tile sources and coordinates tile fetching
pub const TileManager = struct {
    allocator: std.mem.Allocator,
    sources: []TileSource,
    disk_cache: disk_cache.DiskCache,
    memory_cache: std.AutoHashMap(TileKey, *tile_cache.CachedTile),

    pub const TileSource = struct {
        name: []const u8,
        server: tile_server.TileServer,
        opacity: f32,
        enabled: bool,
    };

    pub const TileKey = struct {
        source_idx: usize,
        z: u8,
        x: u32,
        y: u32,

        pub fn hash(self: TileKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&self.source_idx));
            hasher.update(std.mem.asBytes(&self.z));
            hasher.update(std.mem.asBytes(&self.x));
            hasher.update(std.mem.asBytes(&self.y));
            return hasher.final();
        }

        pub fn eql(a: TileKey, b: TileKey) bool {
            return a.source_idx == b.source_idx and
                a.z == b.z and
                a.x == b.x and
                a.y == b.y;
        }
    };

    pub fn init(allocator: std.mem.Allocator, sources: []TileSource, cache: disk_cache.DiskCache) !TileManager {
        return .{
            .allocator = allocator,
            .sources = sources,
            .disk_cache = cache,
            .memory_cache = std.AutoHashMap(TileKey, *tile_cache.CachedTile).init(allocator),
        };
    }

    pub fn deinit(self: *TileManager) void {
        var iter = self.memory_cache.valueIterator();
        while (iter.next()) |cached_tile| {
            cached_tile.*.deinit();
            self.allocator.destroy(cached_tile.*);
        }
        self.memory_cache.deinit();
    }

    /// Fetch a tile from cache or server
    pub fn fetchTile(self: *TileManager, source_idx: usize, z: u8, x: u32, y: u32) !*tile_cache.CachedTile {
        const key = TileKey{
            .source_idx = source_idx,
            .z = z,
            .x = x,
            .y = y,
        };

        if (self.memory_cache.get(key)) |cached| {
            return cached;
        }

        if (source_idx >= self.sources.len) {
            return error.InvalidSourceIndex;
        }

        const source = &self.sources[source_idx];
        if (!source.enabled) {
            return error.SourceDisabled;
        }

        const source_name = source.server.getName();

        if (try self.disk_cache.get(source_name, z, x, y)) |data| {
            defer self.allocator.free(data);
            return try self.loadTileFromData(key, data);
        }

        const data = try source.server.fetchTile(self.allocator, z, x, y);
        defer self.allocator.free(data);

        try self.disk_cache.put(source_name, z, x, y, data);

        return try self.loadTileFromData(key, data);
    }

    fn loadTileFromData(self: *TileManager, key: TileKey, data: []const u8) !*tile_cache.CachedTile {
        const cached_tile = try self.allocator.create(tile_cache.CachedTile);
        errdefer self.allocator.destroy(cached_tile);

        var cache = tile_cache.TileCache.init(self.allocator);
        defer cache.deinit();

        try cache.loadTile(data);

        if (cache.getTile()) |tile| {
            cached_tile.* = tile.*;
            cache.cached_tile = null;
        } else {
            return error.NoTileLoaded;
        }

        try self.memory_cache.put(key, cached_tile);
        return cached_tile;
    }

    /// Get tiles for visible viewport
    pub fn getVisibleTiles(
        self: *TileManager,
        lat: f64,
        lon: f64,
        zoom: u8,
        viewport_width: f32,
        viewport_height: f32,
    ) ![]VisibleTile {
        const grid = geo.calculateVisibleTiles(lat, lon, zoom, viewport_width, viewport_height);

        var tiles = std.ArrayList(VisibleTile).empty;
        defer tiles.deinit(self.allocator);

        for (self.sources, 0..) |*source, source_idx| {
            if (!source.enabled) continue;

            var y: i32 = grid.min_y;
            while (y <= grid.max_y) : (y += 1) {
                var x: i32 = grid.min_x;
                while (x <= grid.max_x) : (x += 1) {
                    if (x < 0 or y < 0) continue;

                    const tile = self.fetchTile(source_idx, zoom, @intCast(x), @intCast(y)) catch |err| {
                        std.debug.print("Failed to fetch tile {s}/{d}/{d}/{d}: {}\n", .{ source.name, zoom, x, y, err });
                        continue;
                    };

                    const grid_x = x - @as(i32, @intCast(grid.center_tile_x));
                    const grid_y = y - @as(i32, @intCast(grid.center_tile_y));

                    try tiles.append(self.allocator, .{
                        .source_idx = source_idx,
                        .tile = tile,
                        .grid_x = grid_x,
                        .grid_y = grid_y,
                        .opacity = source.opacity,
                    });
                }
            }
        }

        return tiles.toOwnedSlice(self.allocator);
    }

    pub const VisibleTile = struct {
        source_idx: usize,
        tile: *tile_cache.CachedTile,
        grid_x: i32,
        grid_y: i32,
        opacity: f32,
    };
};
