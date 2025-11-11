const std = @import("std");
const sqlite = @import("sqlite");

/// SQLite-backed disk cache for MVT tiles
pub const DiskCache = struct {
    db: sqlite.Db,
    allocator: std.mem.Allocator,

    const schema =
        \\CREATE TABLE IF NOT EXISTS tiles (
        \\  source TEXT NOT NULL,
        \\  z INTEGER NOT NULL,
        \\  x INTEGER NOT NULL,
        \\  y INTEGER NOT NULL,
        \\  data BLOB NOT NULL,
        \\  timestamp INTEGER NOT NULL,
        \\  PRIMARY KEY (source, z, x, y)
        \\)
    ;

    pub fn init(allocator: std.mem.Allocator, db_path: [:0]const u8) !DiskCache {
        var db = try sqlite.Db.init(.{
            .mode = sqlite.Db.Mode{ .File = db_path },
            .open_flags = .{
                .write = true,
                .create = true,
            },
            .threading_mode = .MultiThread,
        });

        try db.exec(schema, .{}, .{});

        return .{
            .db = db,
            .allocator = allocator,
        };
    }

    pub fn initInHomeDir(allocator: std.mem.Allocator) !DiskCache {
        const home_dir = std.posix.getenv("HOME") orelse return error.HomeNotFound;

        var cache_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cache_dir = try std.fmt.bufPrint(&cache_dir_buf, "{s}/.cache/zefis", .{home_dir});

        std.fs.cwd().makePath(cache_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        var db_path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
        const db_path = try std.fmt.bufPrintZ(&db_path_buf, "{s}/tiles.db", .{cache_dir});

        return init(allocator, db_path);
    }

    pub fn deinit(self: *DiskCache) void {
        self.db.deinit();
    }

    /// Get a cached tile, returns null if not found
    pub fn get(self: *DiskCache, source: []const u8, z: u8, x: u32, y: u32) !?[]const u8 {
        const query =
            \\SELECT data FROM tiles
            \\WHERE source = ? AND z = ? AND x = ? AND y = ?
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.deinit();

        const row = try stmt.oneAlloc([]const u8, self.allocator, .{}, .{
            .source = source,
            .z = z,
            .x = x,
            .y = y,
        });

        return row;
    }

    /// Store a tile in the cache
    pub fn put(self: *DiskCache, source: []const u8, z: u8, x: u32, y: u32, data: []const u8) !void {
        const query =
            \\INSERT OR REPLACE INTO tiles (source, z, x, y, data, timestamp)
            \\VALUES (?, ?, ?, ?, ?, ?)
        ;

        const timestamp = std.time.timestamp();

        var stmt = try self.db.prepare(query);
        defer stmt.deinit();

        try stmt.exec(.{}, .{
            .source = source,
            .z = z,
            .x = x,
            .y = y,
            .data = sqlite.Blob{ .data = data },
            .timestamp = timestamp,
        });
    }

    /// Remove tiles older than max_age_seconds
    pub fn prune(self: *DiskCache, max_age_seconds: i64) !void {
        const cutoff = std.time.timestamp() - max_age_seconds;

        const query =
            \\DELETE FROM tiles WHERE timestamp < ?
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.deinit();

        try stmt.exec(.{}, .{ .timestamp = cutoff });
    }

    /// Get cache statistics
    pub fn stats(self: *DiskCache) !CacheStats {
        const count_query = "SELECT COUNT(*) FROM tiles";
        const size_query = "SELECT SUM(LENGTH(data)) FROM tiles";

        const count = (try self.db.one(usize, count_query, .{}, .{})) orelse 0;
        const total_bytes = (try self.db.one(usize, size_query, .{}, .{})) orelse 0;

        return .{
            .tile_count = count,
            .total_bytes = total_bytes,
        };
    }

    pub const CacheStats = struct {
        tile_count: usize,
        total_bytes: usize,
    };
};
