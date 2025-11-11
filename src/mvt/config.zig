const std = @import("std");

pub const Config = struct {
    api_keys: ApiKeys,
    cache: CacheConfig,

    pub const ApiKeys = struct {
        openaip: ?[]const u8 = null,
        mapbox: ?[]const u8 = null,
    };

    pub const CacheConfig = struct {
        max_age_days: u32 = 30,
    };

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const contents = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(contents);

        return try parseJson(allocator, contents);
    }

    pub fn loadFromHomeDir(allocator: std.mem.Allocator) !Config {
        const home_dir = std.posix.getenv("HOME") orelse return error.HomeNotFound;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const config_path = try std.fmt.bufPrint(&path_buf, "{s}/.config/zefis/config.json", .{home_dir});

        return loadFromFile(allocator, config_path);
    }

    fn parseJson(allocator: std.mem.Allocator, json_str: []const u8) !Config {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        var config = Config{
            .api_keys = .{},
            .cache = .{},
        };

        if (root.get("api_keys")) |api_keys_val| {
            const api_keys = api_keys_val.object;

            if (api_keys.get("openaip")) |val| {
                if (val == .string) {
                    config.api_keys.openaip = try allocator.dupe(u8, val.string);
                }
            }

            if (api_keys.get("mapbox")) |val| {
                if (val == .string) {
                    config.api_keys.mapbox = try allocator.dupe(u8, val.string);
                }
            }
        }

        if (root.get("cache")) |cache_val| {
            const cache = cache_val.object;

            if (cache.get("max_age_days")) |val| {
                if (val == .integer) {
                    config.cache.max_age_days = @intCast(val.integer);
                }
            }
        }

        return config;
    }

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.api_keys.openaip) |key| {
            allocator.free(key);
        }
        if (self.api_keys.mapbox) |key| {
            allocator.free(key);
        }
    }
};
