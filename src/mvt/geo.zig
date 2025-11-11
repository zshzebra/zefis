const std = @import("std");

/// Geographic coordinate in WGS84 (latitude/longitude)
pub const LatLon = struct {
    lat: f64,
    lon: f64,
};

/// Slippy map tile coordinates (Web Mercator)
pub const TileCoord = struct {
    x: u32,
    y: u32,
    z: u8,
};

/// Pixel position within a tile
pub const TilePixel = struct {
    px: f64,
    py: f64,
};

/// Convert latitude/longitude to tile coordinates at given zoom level
pub fn latLonToTile(lat: f64, lon: f64, zoom: u8) TileCoord {
    const lat_rad = std.math.degreesToRadians(lat);
    const n = @as(f64, @floatFromInt(@as(u32, 1) << @intCast(zoom)));

    const x_tile = (lon + 180.0) / 360.0 * n;
    const y_tile = (1.0 - @log(std.math.tan(lat_rad) + (1.0 / std.math.cos(lat_rad))) / std.math.pi) / 2.0 * n;

    return .{
        .x = @intFromFloat(@floor(x_tile)),
        .y = @intFromFloat(@floor(y_tile)),
        .z = zoom,
    };
}

/// Convert tile coordinates to latitude/longitude (top-left corner of tile)
pub fn tileToLatLon(x: u32, y: u32, zoom: u8) LatLon {
    const n = @as(f64, @floatFromInt(@as(u32, 1) << @intCast(zoom)));

    const lon = @as(f64, @floatFromInt(x)) / n * 360.0 - 180.0;
    const lat_rad = std.math.atan(std.math.sinh(std.math.pi * (1.0 - 2.0 * @as(f64, @floatFromInt(y)) / n)));
    const lat = std.math.radiansToDegrees(lat_rad);

    return .{ .lat = lat, .lon = lon };
}

/// Convert latitude/longitude to pixel position within a specific tile
pub fn latLonToTilePixel(lat: f64, lon: f64, tile_x: u32, tile_y: u32, zoom: u8, extent: u32) TilePixel {
    const lat_rad = std.math.degreesToRadians(lat);
    const n = @as(f64, @floatFromInt(@as(u32, 1) << @intCast(zoom)));

    const x_tile = (lon + 180.0) / 360.0 * n;
    const y_tile = (1.0 - @log(std.math.tan(lat_rad) + (1.0 / std.math.cos(lat_rad))) / std.math.pi) / 2.0 * n;

    const x_offset = x_tile - @as(f64, @floatFromInt(tile_x));
    const y_offset = y_tile - @as(f64, @floatFromInt(tile_y));

    return .{
        .px = x_offset * @as(f64, @floatFromInt(extent)),
        .py = y_offset * @as(f64, @floatFromInt(extent)),
    };
}

/// Calculate visible tile grid for a given viewport centered on lat/lon
pub const TileGrid = struct {
    min_x: i32,
    max_x: i32,
    min_y: i32,
    max_y: i32,
    zoom: u8,
    center_tile_x: u32,
    center_tile_y: u32,
};

/// Calculate which tiles are visible given viewport dimensions and center point
pub fn calculateVisibleTiles(lat: f64, lon: f64, zoom: u8, viewport_width: f32, viewport_height: f32) TileGrid {
    const center = latLonToTile(lat, lon, zoom);

    // Estimate how many tiles are visible based on viewport size
    // At zoom level, each tile is 256px (standard), viewport size determines coverage
    const tile_size = 256.0;
    const tiles_wide = @ceil(viewport_width / tile_size) + 2; // +2 for buffer
    const tiles_high = @ceil(viewport_height / tile_size) + 2;

    const half_width = @as(i32, @intFromFloat(tiles_wide / 2.0));
    const half_height = @as(i32, @intFromFloat(tiles_high / 2.0));

    const center_x = @as(i32, @intCast(center.x));
    const center_y = @as(i32, @intCast(center.y));

    return .{
        .min_x = center_x - half_width,
        .max_x = center_x + half_width,
        .min_y = center_y - half_height,
        .max_y = center_y + half_height,
        .zoom = zoom,
        .center_tile_x = center.x,
        .center_tile_y = center.y,
    };
}

test "latLonToTile basic" {
    // Test with known coordinates (Newcastle, Australia)
    const coord = latLonToTile(-32.7850, 151.8827, 12);
    try std.testing.expect(coord.z == 12);
    try std.testing.expect(coord.x > 0);
    try std.testing.expect(coord.y > 0);
}

test "tileToLatLon roundtrip" {
    const original = LatLon{ .lat = -32.7850, .lon = 151.8827 };
    const tile = latLonToTile(original.lat, original.lon, 12);
    const recovered = tileToLatLon(tile.x, tile.y, 12);

    // Should be close to original (within tile bounds)
    try std.testing.expect(@abs(recovered.lat - original.lat) < 0.1);
    try std.testing.expect(@abs(recovered.lon - original.lon) < 0.1);
}
