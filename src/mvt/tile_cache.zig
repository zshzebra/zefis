const std = @import("std");
const vtzero = @import("vtzero");
const style = @import("style.zig");

pub const CachedTile = struct {
    data: []const u8,
    tile: vtzero.Tile,
    layers: []DecodedLayer,
    extent: u32,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *CachedTile) void {
        // Must destroy in reverse order: tile references data, arena owns data
        for (self.layers) |*layer| {
            layer.deinit();
        }
        self.tile.deinit();
        self.arena.deinit();
    }
};

pub const DecodedLayer = struct {
    name: []const u8,
    version: u32,
    extent: u32,
    features: []DecodedFeature,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DecodedLayer) void {
        for (self.features) |*feature| {
            feature.deinit();
        }
        self.allocator.free(self.features);
    }
};

pub const DecodedFeature = struct {
    id: ?u64,
    geometry_type: vtzero.GeomType,
    geometry: DecodedGeometry,
    properties: style.PropertyMap,

    pub fn deinit(self: *DecodedFeature) void {
        self.geometry.deinit();
        self.properties.deinit();
    }
};

pub const DecodedGeometry = union(vtzero.GeomType) {
    unknown: void,
    point: []Point,
    linestring: []LineString,
    polygon: []Polygon,

    pub const Point = struct {
        x: i32,
        y: i32,
    };

    pub const LineString = struct {
        points: []Point,
        allocator: std.mem.Allocator,

        pub fn deinit(self: LineString) void {
            self.allocator.free(self.points);
        }
    };

    pub const Polygon = struct {
        rings: []Ring,
        allocator: std.mem.Allocator,

        pub const Ring = struct {
            ring_type: RingType,
            points: []Point,
            allocator: std.mem.Allocator,

            pub fn deinit(self: Ring) void {
                self.allocator.free(self.points);
            }
        };

        pub const RingType = enum {
            outer,
            inner,
        };

        pub fn deinit(self: Polygon) void {
            for (self.rings) |ring| {
                ring.deinit();
            }
            self.allocator.free(self.rings);
        }
    };

    pub fn deinit(self: DecodedGeometry) void {
        switch (self) {
            .unknown => {},
            .point => |points| _ = points, // Points owned by arena allocator
            .linestring => |lines| {
                for (lines) |line| {
                    line.deinit();
                }
            },
            .polygon => |polygons| {
                for (polygons) |polygon| {
                    polygon.deinit();
                }
            },
        }
    }
};

pub const TileCache = struct {
    allocator: std.mem.Allocator,
    cached_tile: ?CachedTile = null,

    pub fn init(allocator: std.mem.Allocator) TileCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TileCache) void {
        if (self.cached_tile) |*tile| {
            tile.deinit();
        }
    }

    pub fn loadTile(self: *TileCache, data: []const u8) !void {
        if (self.cached_tile) |*old_tile| {
            old_tile.deinit();
            self.cached_tile = null;
        }

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();

        // Copy data into arena so tile_data outlives tile handle
        const tile_data = try arena.allocator().dupe(u8, data);

        var tile = try vtzero.Tile.init(tile_data);
        errdefer tile.deinit();

        var layers = std.ArrayList(DecodedLayer).empty;
        errdefer {
            for (layers.items) |*layer| {
                layer.deinit();
            }
            layers.deinit(arena.allocator());
        }

        var extent: u32 = 4096;

        try tile.resetLayer();

        while (try tile.nextLayer()) |layer| {
            defer layer.deinit();

            const layer_name = try layer.name();
            const layer_version = try layer.version();
            const layer_extent = try layer.extent();

            if (layers.items.len == 0) {
                extent = layer_extent;
            }

            var features = std.ArrayList(DecodedFeature).empty;
            errdefer {
                for (features.items) |*feat| {
                    feat.deinit();
                }
                features.deinit(arena.allocator());
            }

            while (try layer.nextFeature()) |feature| {
                defer feature.deinit();

                const feature_id = try feature.id();
                const geom_type = try feature.geometryType();

                var props = style.PropertyMap.init(arena.allocator());
                errdefer props.deinit();

                while (try feature.nextProperty()) |prop| {
                    defer prop.deinit();

                    const key = try prop.key();
                    const value = try prop.value();

                    const value_str = switch (value) {
                        .string => |s| s,
                        .int => |i| try std.fmt.allocPrint(arena.allocator(), "{d}", .{i}),
                        .uint => |u| try std.fmt.allocPrint(arena.allocator(), "{d}", .{u}),
                        .sint => |si| try std.fmt.allocPrint(arena.allocator(), "{d}", .{si}),
                        .float => |f| try std.fmt.allocPrint(arena.allocator(), "{d}", .{f}),
                        .double => |d| try std.fmt.allocPrint(arena.allocator(), "{d}", .{d}),
                        .bool => |b| if (b) "true" else "false",
                    };

                    try props.add(key, value_str);
                }

                var geom = try feature.decodeGeometry(arena.allocator());
                defer geom.deinit(arena.allocator());

                const decoded_geom = try convertGeometry(geom, arena.allocator());

                try features.append(arena.allocator(), .{
                    .id = feature_id,
                    .geometry_type = geom_type,
                    .geometry = decoded_geom,
                    .properties = props,
                });
            }

            try layers.append(arena.allocator(), .{
                .name = layer_name,
                .version = layer_version,
                .extent = layer_extent,
                .features = try features.toOwnedSlice(arena.allocator()),
                .allocator = arena.allocator(),
            });
        }

        self.cached_tile = .{
            .data = tile_data,
            .tile = tile,
            .layers = try layers.toOwnedSlice(arena.allocator()),
            .extent = extent,
            .arena = arena,
        };
    }

    pub fn getTile(self: *TileCache) ?*CachedTile {
        if (self.cached_tile) |*tile| {
            return tile;
        }
        return null;
    }
};

fn convertGeometry(geom: vtzero.Geometry, allocator: std.mem.Allocator) !DecodedGeometry {
    switch (geom) {
        .unknown => return .{ .unknown = {} },
        .point => |points| {
            const decoded_points = try allocator.alloc(DecodedGeometry.Point, points.items.len);
            for (points.items, 0..) |p, i| {
                decoded_points[i] = .{ .x = p.x, .y = p.y };
            }
            return .{ .point = decoded_points };
        },
        .linestring => |lines| {
            const decoded_lines = try allocator.alloc(DecodedGeometry.LineString, lines.items.len);
            for (lines.items, 0..) |line, i| {
                const points = try allocator.alloc(DecodedGeometry.Point, line.items.len);
                for (line.items, 0..) |p, j| {
                    points[j] = .{ .x = p.x, .y = p.y };
                }
                decoded_lines[i] = .{
                    .points = points,
                    .allocator = allocator,
                };
            }
            return .{ .linestring = decoded_lines };
        },
        .polygon => |rings| {
            const decoded_polygons = try allocator.alloc(DecodedGeometry.Polygon, 1);
            const polygon_rings = try allocator.alloc(DecodedGeometry.Polygon.Ring, rings.items.len);

            for (rings.items, 0..) |ring, i| {
                const points = try allocator.alloc(DecodedGeometry.Point, ring.points.items.len);
                for (ring.points.items, 0..) |p, j| {
                    points[j] = .{ .x = p.x, .y = p.y };
                }

                const ring_type: DecodedGeometry.Polygon.RingType = switch (ring.ring_type) {
                    .outer => .outer,
                    .inner => .inner,
                    .invalid => .outer, // Treat invalid rings as outer
                };

                polygon_rings[i] = .{
                    .ring_type = ring_type,
                    .points = points,
                    .allocator = allocator,
                };
            }

            decoded_polygons[0] = .{
                .rings = polygon_rings,
                .allocator = allocator,
            };

            return .{ .polygon = decoded_polygons };
        },
    }
}
