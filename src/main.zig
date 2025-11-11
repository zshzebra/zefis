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

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const current_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
        const current_height = @as(f32, @floatFromInt(rl.getScreenHeight()));
        widget.setViewportSize(current_width, current_height);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(240, 240, 235, 255));

        widget.draw() catch |err| {
            std.debug.print("Error drawing tile: {}\n", .{err});
        };

        rl.drawText("EFIS - Mapbox Vector Tile Demo", 10, 10, 20, rl.Color.dark_gray);
        if (widget.getTileInfo()) |info| {
            var buf: [256]u8 = undefined;
            const info_text = std.fmt.bufPrintZ(&buf, "Tile: extent={d}, layers={d}", .{ info.extent, info.num_layers }) catch "Info unavailable";
            rl.drawText(info_text, 10, 35, 16, rl.Color.dark_gray);
        }
    }
}
