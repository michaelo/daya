/// Module for taking the DIF and convert it into proper DOT
const std = @import("std");
const main = @import("main.zig");
const bufwriter = @import("bufwriter.zig");
const utils = @import("utils.zig");
const printPrettify = utils.printPrettify;
const testing = std.testing;
const debug = std.debug.print;

const dif = @import("dif.zig");
const DifNode = dif.DifNode;
const DifNodeMap = std.StringHashMap(ial.Entry(DifNode));

const ial = @import("indexedarraylist.zig");

const RenderError = error{
    UnexpectedType,
    NoSuchNode,
    NoSuchEdge,
    NoSuchInstance,
    OutOfMemory,
};

/// Pre-populated sets of indexes to the different types of difnodes
pub const DifNodeMapSet = struct {
    node_map: *DifNodeMap,
    edge_map: *DifNodeMap,
    instance_map: *DifNodeMap,
    group_map: *DifNodeMap,
};

pub fn DotContext(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        pub fn init(writer: Writer) Self {
            return Self{
                .writer = writer,
            };
        }

        fn findUnit(node: *ial.Entry(dif.DifNode)) !*ial.Entry(dif.DifNode) {
            var current = node;
            while (current.get().node_type != .Unit) {
                if (current.get().parent) |*parent| {
                    current = parent;
                } else {
                    // Ending up here is a bug
                    return error.NoUnitFound;
                }
            }
            return current;
        }

        inline fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            try self.writer.print(fmt, args);
        }

        fn printError(self: *Self, node: *ial.Entry(dif.DifNode), comptime fmt: []const u8, args: anytype) void {
            _ = self;
            const err_writer = std.io.getStdErr().writer();
            const unit = findUnit(node) catch {
                err_writer.print("BUG: Could not find unit associated with node\n", .{}) catch {};
                // TODO: Don't have to unreach here - can continue to render anything but the filename and source chunk
                unreachable;
            };
            const src_buf = unit.get().data.Unit.src_buf;
            const lc = utils.idxToLineCol(src_buf, node.get().initial_token.?.start);
            err_writer.print("{s}:{d}:{d}: error: ", .{ unit.get().name.?, lc.line, lc.col }) catch {};
            err_writer.print(fmt, args) catch {};
            err_writer.print("\n", .{}) catch {};
            utils.dumpSrcChunkRef(@TypeOf(err_writer), err_writer, src_buf, node.get().initial_token.?.start);
            err_writer.print("\n", .{}) catch {};

            // Print ^ at start of symbol
            err_writer.writeByteNTimes(' ', lc.col-1) catch {};
            err_writer.print("^\n", .{}) catch {};
        }
    };
}


fn renderInstantiation(comptime Writer: type, ctx: *DotContext(Writer), instance_ref: *ial.Entry(DifNode)) anyerror!void {
    // Early opt out / safeguard. Most likely a bug
    const instance = instance_ref.get();
    if (instance.node_type != .Instantiation) {
        return RenderError.UnexpectedType;
    }

    //
    // Get all parameters of source, target and edge.
    //
    // This assumes the graph is well-formed at this point. TODO: Create duplicate graph from the Dif without optionals
    var params_instance = instance.data.Instantiation.params;
    var node = instance.data.Instantiation.node_type_ref.?.get();
    var params_node = node.data.Node.params;

    //
    // Generate the dot output
    //

    // Print node name and start attr-list
    try ctx.print("\"{s}\"[", .{instance.name});

    // Compose label
    {
        try ctx.print("label=\"", .{});

        // Instance-name/label
        if (params_instance.label) |label| {
            try ctx.print("{s}", .{label});
        } else if (instance.name) |name| {
            try printPrettify(Writer, ctx.writer, name, .{ .do_caps = true });
        }

        // Node-type-name/label
        if (params_node.label orelse node.name) |node_label| {
            try ctx.print("\n{s}", .{node_label});
        }

        try ctx.print("\",", .{});
    }

    // Shape
    if (params_instance.shape orelse params_node.shape) |shape| {
        try ctx.print("shape=\"{s}\",", .{shape});
    }

    // Foreground
    if (params_instance.fgcolor orelse params_node.fgcolor) |fgcolor| {
        try ctx.print("fontcolor=\"{0s}\",", .{fgcolor});
    }

    // Background
    if (params_instance.bgcolor orelse params_node.bgcolor) |bgcolor| {
        try ctx.print("style=filled,bgcolor=\"{0s}\",fillcolor=\"{0s}\",", .{bgcolor});
    }

    // end attr-list/node
    try ctx.print("];\n", .{});

    // Check for note:
    if (params_instance.note) |note| {
        var note_idx = instance_ref.idx;
        try ctx.print(
            \\note_{0x}[label="{1s}",style=filled,fillcolor="#ffffaa",shape=note];
            \\note_{0x} -> "{2s}"[arrowtail=none,arrowhead=none,style=dashed];
            \\
        , .{ note_idx, note, instance.name });
    }
}

fn renderRelationship(comptime Writer: type, ctx: *DotContext(Writer), instance_ref: *ial.Entry(DifNode)) anyerror!void {
    // Early opt out / safeguard. Most likely a bug
    const instance = instance_ref.get();
    if (instance.node_type != .Relationship) {
        return RenderError.UnexpectedType;
    }


    //
    // Get all parameters of source, target and edge.
    //
    // This assumes the graph is well-formed at this point. TODO: Create duplicate graph from the Dif without optionals
    var node_source = instance.data.Relationship.source_ref.?.get();
    var node_target = instance.data.Relationship.target_ref.?.get();
    var edge = instance.data.Relationship.edge_ref.?.get();

    var params_instance = instance.data.Relationship.params;
    var params_edge = edge.data.Edge.params;

    //
    // Generate the dot output
    //

    try ctx.print("\"{s}\" -> \"{s}\"[", .{ node_source.name, node_target.name });

    // Label
    if (params_instance.label orelse params_edge.label) |label| {
        try ctx.print("label=\"{s}\",", .{label});
    } else {
        if (edge.name) |label| {
            try ctx.print("label=\"", .{});
            try printPrettify(Writer, ctx.writer, label, .{});
            try ctx.print("\",", .{});
        }
    }

    // if source is group:
    if (node_source.node_type == .Group) {
        try ctx.print("ltail=cluster_{s},", .{node_source.name.?});
    }

    // if target is group:
    if (node_target.node_type == .Group) {
        try ctx.print("lhead=cluster_{s},", .{node_target.name.?});
    }

    // Style
    var edge_style = params_instance.edge_style orelse params_edge.edge_style orelse dif.EdgeStyle.solid;

    // Start edge
    try ctx.print("style=\"{s}\",", .{std.meta.tagName(edge_style)});

    try ctx.print("dir=both,", .{});

    if (params_instance.source_symbol orelse params_edge.source_symbol) |source_symbol| {
        var arrow = switch (source_symbol) {
            .arrow_open => "vee",
            .arrow_closed => "onormal",
            .arrow_filled => "normal",
            .none => "none",
        };

        try ctx.print("arrowtail={s},", .{arrow});
    } else {
        try ctx.print("arrowtail=none,", .{});
    }

    // End edge
    if (params_instance.target_symbol orelse params_edge.target_symbol) |target_symbol| {
        var arrow = switch (target_symbol) {
            .arrow_open => "vee",
            .arrow_closed => "onormal",
            .arrow_filled => "normal",
            .none => "none",
        };
        try ctx.print("arrowhead={s},", .{arrow});
    } else {
        try ctx.print("arrowhead=normal,", .{});
    }

    try ctx.print("];\n", .{});
}

/// Recursive
/// TODO: Specify which node-types to render? To e.g. render only nodes, groups, notes (and note-edges) - or only edges
fn renderGeneration(comptime Writer: type, ctx: *DotContext(Writer), instance: *ial.Entry(DifNode)) anyerror!void {
    var node = instance;

    // Iterate over siblings
    while (true) {
        switch (node.get().node_type) {
            .Unit => {
                if (node.get().first_child) |*child| {
                    try renderGeneration(Writer, ctx, child);
                }
            },
            .Instantiation => {
                try renderInstantiation(Writer, ctx, node);
            },
            .Relationship => {
                try renderRelationship(Writer, ctx, node);
            },
            .Group => {
                // Recurse on groups
                if (node.get().first_child) |*child| {
                    try ctx.print("subgraph cluster_{s} {{\n", .{node.get().name});

                    // Invisible point inside group, used to create edges to/from groups
                    try ctx.print("{s} [shape=point,style=invis,height=0,width=0];", .{node.get().name});
                    try renderGeneration(Writer, ctx, child);
                    try ctx.print("}}\n", .{});

                    // Checking group-fields in case of label, which shall be created outside of group
                    var params_group = child.get().data.Group.params;

                    // Check for note:
                    if (params_group.note) |note| {
                        var note_idx = instance.idx;
                        try ctx.print(
                            \\note_{0x}[label="{1s}",style=filled,fillcolor="#ffffaa",shape=note];
                            \\note_{0x} -> {2s}[lhead=cluster_{2s},arrowtail=none,arrowhead=none,style=dashed];
                            \\
                        , .{ note_idx, note, node.get().name });
                    }
                }
            },
            else => {},
        }

        if (node.get().next_sibling) |*next| {
            node = next;
        } else {
            break;
        }
    }

    // Group-level attributes
    if(instance.get().parent) |*parent| {
        const maybe_params_group: ?dif.GroupParams = switch(parent.get().data) {
            .Group => |el| el.params,
            .Unit => |el| el.params,
            else => null
        };

        if(maybe_params_group) |params_group| {
            if (params_group.label) |label| {
                try ctx.print("label=\"{s}\";labelloc=\"t\";\n", .{label});
            }

            if (params_group.layout) |layout| {
                try ctx.print("layout=\"{s}\";\n", .{layout});
            }
        }
    }
}

pub fn difToDot(comptime Writer: type, ctx: *DotContext(Writer), root_node: *ial.Entry(DifNode)) !void {
    try ctx.print("strict digraph {{\ncompound=true;\n", .{});
    try renderGeneration(Writer, ctx, root_node);
    try ctx.print("}}\n", .{});
}

test "writeNodeFields" {
    // Go through each fields and verify that it gets converted as expected
    var buf: [1024]u8 = undefined;
    var buf_context = bufwriter.ArrayBuf{ .buf = buf[0..] };

    var writer = buf_context.writer();

    const source =
        \\node MyNode {
        \\    label="My label";
        \\    fgcolor="#000000";
        \\    bgcolor="#FF0000";
        \\}
        \\Node: MyNode;
        \\
    ;

    try main.hidotToDot(std.testing.allocator, bufwriter.ArrayBufWriter, writer, source, "test");
    // Check that certain strings actually gets converted. It might not be 100% correct, but is intended to catch that
    // basic flow of logic is happening
    try testing.expect(std.mem.indexOf(u8, buf_context.slice(), "\"Node\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf_context.slice(), "My label") != null);
    try testing.expect(std.mem.indexOf(u8, buf_context.slice(), "bgcolor=\"#FF0000\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf_context.slice(), "color=\"#000000\"") != null);
}

test "writeRelationshipFields" {
    // Go through each fields and verify that it gets converted as expected
    var buf: [1024]u8 = undefined;
    var context = bufwriter.ArrayBuf{ .buf = buf[0..] };

    var writer = context.writer();

    const source =
        \\node MyNode {}
        \\edge Uses {
        \\    label="Edge label";
        \\    source_symbol=arrow_filled;
        \\    target_symbol=arrow_open;
        \\}
        \\NodeA: MyNode;
        \\NodeB: MyNode;
        \\NodeA Uses NodeB;
        \\
    ;

    try main.hidotToDot(std.testing.allocator, bufwriter.ArrayBufWriter, writer, source, "test");
    // Check that certain strings actually gets converted. It might not be 100% correct, but is intended to catch that
    // basic flow of logic is happening
    try testing.expect(std.mem.indexOf(u8, context.slice(), "Edge label") != null);
    try testing.expect(std.mem.indexOf(u8, context.slice(), "arrowhead=vee") != null);
    try testing.expect(std.mem.indexOf(u8, context.slice(), "arrowtail=normal") != null);
}
