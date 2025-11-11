const std = @import("std");

/// Earcut polygon triangulation algorithm
/// Based on https://github.com/mapbox/earcut
/// Triangulates a polygon with holes into triangles
pub fn earcut(allocator: std.mem.Allocator, vertices: []const f32, hole_indices: ?[]const usize, dim: usize) ![]u32 {
    const has_holes = if (hole_indices) |holes| holes.len > 0 else false;
    const outer_len = if (has_holes) hole_indices.?[0] * dim else vertices.len;

    const outer_node = try linkedList(allocator, vertices, 0, outer_len, dim, true);
    var triangles = std.ArrayList(u32){};

    if (outer_node == null) return try triangles.toOwnedSlice(allocator);

    try earcutLinked(allocator, outer_node, &triangles, 0);

    return try triangles.toOwnedSlice(allocator);
}

const Node = struct {
    i: usize,
    x: f32,
    y: f32,
    prev: ?*Node,
    next: ?*Node,
    z: i32,
    prevZ: ?*Node,
    nextZ: ?*Node,
    steiner: bool,
};

fn linkedList(allocator: std.mem.Allocator, data: []const f32, start: usize, end: usize, dim: usize, clockwise: bool) !?*Node {
    if (start >= end) return null;

    var last: ?*Node = null;

    if (clockwise == (signedArea(data, start, end, dim) > 0)) {
        var i = start;
        while (i < end) : (i += dim) {
            last = try insertNode(allocator, i / dim, data[i], data[i + 1], last);
        }
    } else {
        var i = end;
        while (i > start) {
            i -= dim;
            last = try insertNode(allocator, i / dim, data[i], data[i + 1], last);
        }
    }

    if (last) |l| {
        if (l.next) |n| {
            if (equals(l, n)) {
                removeNode(l);
                last = n.next;
            }
        }
    }

    return last;
}

fn signedArea(data: []const f32, start: usize, end: usize, dim: usize) f32 {
    var sum: f32 = 0;
    var i = start;
    var j = end - dim;

    while (i < end) : ({i += dim; j = i - dim;}) {
        sum += (data[j] - data[i]) * (data[i + 1] + data[j + 1]);
    }

    return sum;
}

fn insertNode(allocator: std.mem.Allocator, i: usize, x: f32, y: f32, last: ?*Node) !*Node {
    const p = try allocator.create(Node);
    p.* = .{
        .i = i,
        .x = x,
        .y = y,
        .prev = null,
        .next = null,
        .z = 0,
        .prevZ = null,
        .nextZ = null,
        .steiner = false,
    };

    if (last == null) {
        p.prev = p;
        p.next = p;
    } else {
        p.next = last.?.next;
        p.prev = last;
        last.?.next.?.prev = p;
        last.?.next = p;
    }

    return p;
}

fn removeNode(p: *Node) void {
    p.next.?.prev = p.prev;
    p.prev.?.next = p.next;

    if (p.prevZ) |pz| pz.nextZ = p.nextZ;
    if (p.nextZ) |nz| nz.prevZ = p.prevZ;
}

fn equals(p1: *Node, p2: *Node) bool {
    return p1.x == p2.x and p1.y == p2.y;
}

fn earcutLinked(
    allocator: std.mem.Allocator,
    ear_opt: ?*Node,
    triangles: *std.ArrayList(u32),
    pass: u8,
) !void {
    var ear = ear_opt orelse return;
    var iterations: usize = 0;
    const max_iter: usize = 1000;

    while (ear.prev != ear.next) {
        iterations += 1;
        if (iterations > max_iter) break;

        const prev = ear.prev.?;
        const next = ear.next.?;

        if (isEar(ear)) {
            try triangles.append(allocator, @intCast(prev.i));
            try triangles.append(allocator, @intCast(ear.i));
            try triangles.append(allocator, @intCast(next.i));

            removeNode(ear);
            ear = next.next.?;

            continue;
        }

        ear = next;

        if (ear == ear.next.?) {
            if (pass == 0) {
                try earcutLinked(allocator, filterPoints(ear, null), triangles, 1);
            }
            break;
        }
    }
}

fn isEar(ear: *Node) bool {
    const a = ear.prev.?;
    const b = ear;
    const c = ear.next.?;

    if (area(a, b, c) >= 0) return false;

    var p = ear.next.?.next;

    while (p != ear.prev) : (p = p.?.next) {
        if (pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, p.?.x, p.?.y) and
            area(p.?.prev.?, p.?, p.?.next.?) >= 0) {
            return false;
        }
    }

    return true;
}

fn area(p: *Node, q: *Node, r: *Node) f32 {
    return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
}

fn pointInTriangle(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32, px: f32, py: f32) bool {
    return (cx - px) * (ay - py) >= (ax - px) * (cy - py) and
           (ax - px) * (by - py) >= (bx - px) * (ay - py) and
           (bx - px) * (cy - py) >= (cx - px) * (by - py);
}

fn filterPoints(start_opt: ?*Node, end_opt: ?*Node) ?*Node {
    var start = start_opt orelse return null;
    const end = end_opt orelse start;

    var p = start;
    var again = true;

    while (again or p != end) {
        again = false;

        if (!p.steiner and (equals(p, p.next.?) or area(p.prev.?, p, p.next.?) == 0)) {
            removeNode(p);
            p = end;
            start = end;
            if (p == p.next.?) return null;
            again = true;
        } else {
            p = p.next.?;
        }
    }

    return start;
}
