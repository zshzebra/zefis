const std = @import("std");
const rl = @import("raylib");
const mvt = @import("mvt/widget.zig");
const config = @import("mvt/config.zig");
const tile_server = @import("mvt/tile_server.zig");
const disk_cache = @import("mvt/disk_cache.zig");
const tile_manager = @import("mvt/tile_manager.zig");

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 450;

    rl.setConfigFlags(.{ .window_resizable = true, .vsync_hint = true, .msaa_4x_hint = true });
    rl.initWindow(screenWidth, screenHeight, "zefis - EFIS with Mapbox Vector Tiles");
    defer rl.closeWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var widget = mvt.MVTWidget.init(allocator, screenWidth, screenHeight);
    defer widget.deinit();

    var cfg = config.Config.loadFromHomeDir(allocator) catch |err| blk: {
        std.debug.print("Warning: Could not load config: {}\n", .{err});
        std.debug.print("Falling back to sample.mvt\n", .{});

        widget.loadTileFromFile("resources/sample.mvt") catch |load_err| {
            std.debug.print("Error loading sample tile: {}\n", .{load_err});
            return;
        };

        if (widget.getTileInfo()) |info| {
            std.debug.print("Loaded sample tile with extent={d}, layers={d}\n", .{ info.extent, info.num_layers });
        }

        break :blk null;
    };
    defer if (cfg) |*c| c.deinit(allocator);

    var tile_mgr: ?tile_manager.TileManager = null;
    var cache: ?disk_cache.DiskCache = null;
    var servers: ?[]tile_manager.TileManager.TileSource = null;

    if (cfg) |c| {
        cache = disk_cache.DiskCache.initInHomeDir(allocator) catch |err| blk: {
            std.debug.print("Warning: Could not initialize disk cache: {}\n", .{err});
            break :blk null;
        };

        if (cache) |*disk_cache_ptr| {
            var source_list = std.ArrayList(tile_manager.TileManager.TileSource).empty;
            defer source_list.deinit(allocator);

            if (c.api_keys.mapbox) |mapbox_key| {
                const mapbox_server = try tile_server.MapboxServer.init(allocator, mapbox_key, "mapbox.mapbox-streets-v8");
                const mapbox_tile_server = mapbox_server.tileServer();
                try source_list.append(allocator, .{
                    .name = "Mapbox Streets",
                    .server = mapbox_tile_server,
                    .opacity = 1.0,
                    .enabled = true,
                });
                std.debug.print("Enabled Mapbox Streets tile source\n", .{});
            }

            if (c.api_keys.openaip) |openaip_key| {
                const openaip_server = try tile_server.OpenAIPServer.init(allocator, openaip_key);
                const openaip_tile_server = openaip_server.tileServer();
                try source_list.append(allocator, .{
                    .name = "OpenAIP",
                    .server = openaip_tile_server,
                    .opacity = 0.8,
                    .enabled = true,
                });
                std.debug.print("Enabled OpenAIP tile source\n", .{});
            }

            if (source_list.items.len > 0) {
                servers = try allocator.dupe(tile_manager.TileManager.TileSource, source_list.items);
                tile_mgr = try tile_manager.TileManager.init(allocator, servers.?, disk_cache_ptr.*);

                widget.setTileManager(&tile_mgr.?);

                widget.setCenter(-32.7850, 151.8827, 12);
                std.debug.print("Set center to Newcastle, Australia (lat=-32.7850, lon=151.8827, zoom=12)\n", .{});
            }
        }
    }

    widget.renderToTexture() catch |err| {
        std.debug.print("Error rendering initial texture: {}\n", .{err});
        return;
    };

    var zoom: f32 = 1.0;
    var pan_x: f32 = 0.0;
    var pan_y: f32 = 0.0;
    var is_dragging = false;
    var last_mouse_x: f32 = 0.0;
    var last_mouse_y: f32 = 0.0;
    var last_interaction_time: f64 = 0.0;
    const idle_threshold: f64 = 0.1;

    rl.setTargetFPS(180);
    while (!rl.windowShouldClose()) {
        const current_time = rl.getTime();
        const current_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
        const current_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
        widget.setViewportSize(current_width, current_height);

        const mouse_wheel = rl.getMouseWheelMove();
        if (mouse_wheel != 0) {
            const mouse_pos = rl.getMousePosition();
            const old_zoom = zoom;
            zoom *= @exp(mouse_wheel * 0.1);
            zoom = @max(0.1, @min(zoom, 20.0));

            const zoom_ratio = zoom / old_zoom;
            const center_x = current_width / 2.0;
            const center_y = current_height / 2.0;

            const mouse_offset_x = mouse_pos.x - center_x;
            const mouse_offset_y = mouse_pos.y - center_y;

            pan_x = pan_x * zoom_ratio + mouse_offset_x * (1.0 - zoom_ratio);
            pan_y = pan_y * zoom_ratio + mouse_offset_y * (1.0 - zoom_ratio);

            widget.setZoom(zoom);
            widget.setPan(pan_x, pan_y);
            last_interaction_time = current_time;
        }

        if (rl.isMouseButtonPressed(.left)) {
            is_dragging = true;
            const mouse_pos = rl.getMousePosition();
            last_mouse_x = mouse_pos.x;
            last_mouse_y = mouse_pos.y;
        }

        if (rl.isMouseButtonReleased(.left)) {
            is_dragging = false;
        }

        if (is_dragging) {
            const mouse_pos = rl.getMousePosition();
            const delta_x = mouse_pos.x - last_mouse_x;
            const delta_y = mouse_pos.y - last_mouse_y;

            pan_x += delta_x;
            pan_y += delta_y;

            widget.setPan(pan_x, pan_y);

            last_mouse_x = mouse_pos.x;
            last_mouse_y = mouse_pos.y;
            last_interaction_time = current_time;
        }

        if ((current_time - last_interaction_time) >= idle_threshold) {
            if (widget.needsRedraw()) {
                widget.renderToTexture() catch |err| {
                    std.debug.print("Error rendering texture: {}\n", .{err});
                };
            }
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(240, 240, 235, 255));

        const mouse_pos = rl.getMousePosition();
        widget.draw(mouse_pos) catch |err| {
            std.debug.print("Error drawing tile: {}\n", .{err});
        };

        rl.drawText("EFIS MVT demo", 10, 10, 20, rl.Color.dark_gray);
        if (widget.getTileInfo()) |info| {
            var buf: [512]u8 = undefined;
            const info_text = std.fmt.bufPrintZ(&buf, "Tile: extent={d}, layers={d} | Zoom: {d:.2} | Pan: ({d:.0}, {d:.0})", .{ info.extent, info.num_layers, zoom, pan_x, pan_y }) catch "Info unavailable";
            rl.drawText(info_text, 10, 35, 16, rl.Color.dark_gray);
        }
        rl.drawText("Controls: Scroll to zoom, Click+Drag to pan", 10, 55, 14, rl.Color.gray);
    }

    if (tile_mgr) |*mgr| {
        mgr.deinit();
    }
    if (servers) |srv| {
        for (srv) |*source| {
            source.server.deinit();
        }
        allocator.free(srv);
    }
    if (cache) |*c| {
        c.deinit();
    }
}
