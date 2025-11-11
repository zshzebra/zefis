const std = @import("std");
const rl = @import("raylib");
const mvt = @import("mvt/widget.zig");

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

    widget.loadTileFromFile("resources/sample.mvt") catch |err| {
        std.debug.print("Error loading tile: {}\n", .{err});
        return;
    };

    if (widget.getTileInfo()) |info| {
        std.debug.print("Loaded tile with extent={d}, layers={d}\n", .{ info.extent, info.num_layers });

        var i: usize = 0;
        while (i < info.num_layers) : (i += 1) {
            if (widget.getLayerInfo(i)) |layer_info| {
                std.debug.print("  Layer {d}: '{s}' - {d} features\n", .{ i, layer_info.name, layer_info.num_features });
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
}
