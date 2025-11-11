const std = @import("std");
const geo = @import("geo.zig");

/// Abstract tile server interface
pub const TileServer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        fetchTile: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, z: u8, x: u32, y: u32) anyerror![]u8,
        deinit: *const fn (ptr: *anyopaque) void,
        getName: *const fn (ptr: *anyopaque) []const u8,
    };

    pub fn fetchTile(self: TileServer, allocator: std.mem.Allocator, z: u8, x: u32, y: u32) ![]u8 {
        return self.vtable.fetchTile(self.ptr, allocator, z, x, y);
    }

    pub fn deinit(self: TileServer) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn getName(self: TileServer) []const u8 {
        return self.vtable.getName(self.ptr);
    }
};

/// OpenAIP tile server implementation
pub const OpenAIPServer = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    http_client: std.http.Client,

    const base_url = "https://api.tiles.openaip.net/data/openaip";

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) !*OpenAIPServer {
        const server = try allocator.create(OpenAIPServer);
        server.* = .{
            .allocator = allocator,
            .api_key = try allocator.dupe(u8, api_key),
            .http_client = std.http.Client{ .allocator = allocator },
        };
        return server;
    }

    pub fn tileServer(self: *OpenAIPServer) TileServer {
        return .{
            .ptr = self,
            .vtable = &.{
                .fetchTile = fetchTileImpl,
                .deinit = deinitImpl,
                .getName = getNameImpl,
            },
        };
    }

    fn fetchTileImpl(ptr: *anyopaque, allocator: std.mem.Allocator, z: u8, x: u32, y: u32) ![]u8 {
        const self: *OpenAIPServer = @ptrCast(@alignCast(ptr));

        var url_buf: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(&url_buf, "{s}/{d}/{d}/{d}.pbf?apiKey={s}", .{ base_url, z, x, y, self.api_key });

        var response_writer: std.Io.Writer.Allocating = .init(allocator);
        defer response_writer.deinit();

        const result = try self.http_client.fetch(.{
            .location = .{ .url = url },
            .response_writer = &response_writer.writer,
        });

        if (result.status != .ok) {
            return error.HttpRequestFailed;
        }

        var response_data = response_writer.toArrayList();
        return response_data.toOwnedSlice(allocator);
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *OpenAIPServer = @ptrCast(@alignCast(ptr));
        self.http_client.deinit();
        self.allocator.free(self.api_key);
        self.allocator.destroy(self);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "OpenAIP";
    }
};

/// Mapbox tile server implementation
pub const MapboxServer = struct {
    allocator: std.mem.Allocator,
    access_token: []const u8,
    tileset_id: []const u8,
    http_client: std.http.Client,

    const base_url = "https://api.mapbox.com/v4";

    pub fn init(allocator: std.mem.Allocator, access_token: []const u8, tileset_id: []const u8) !*MapboxServer {
        const server = try allocator.create(MapboxServer);
        server.* = .{
            .allocator = allocator,
            .access_token = try allocator.dupe(u8, access_token),
            .tileset_id = try allocator.dupe(u8, tileset_id),
            .http_client = std.http.Client{ .allocator = allocator },
        };
        return server;
    }

    pub fn tileServer(self: *MapboxServer) TileServer {
        return .{
            .ptr = self,
            .vtable = &.{
                .fetchTile = fetchTileImpl,
                .deinit = deinitImpl,
                .getName = getNameImpl,
            },
        };
    }

    fn fetchTileImpl(ptr: *anyopaque, allocator: std.mem.Allocator, z: u8, x: u32, y: u32) ![]u8 {
        const self: *MapboxServer = @ptrCast(@alignCast(ptr));

        var url_buf: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(&url_buf, "{s}/{s}/{d}/{d}/{d}.mvt?access_token={s}", .{ base_url, self.tileset_id, z, x, y, self.access_token });

        var response_writer: std.Io.Writer.Allocating = .init(allocator);
        defer response_writer.deinit();

        const result = try self.http_client.fetch(.{
            .location = .{ .url = url },
            .response_writer = &response_writer.writer,
        });

        if (result.status != .ok) {
            return error.HttpRequestFailed;
        }

        var response_data = response_writer.toArrayList();
        return response_data.toOwnedSlice(allocator);
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *MapboxServer = @ptrCast(@alignCast(ptr));
        self.http_client.deinit();
        self.allocator.free(self.access_token);
        self.allocator.free(self.tileset_id);
        self.allocator.destroy(self);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "Mapbox";
    }
};
