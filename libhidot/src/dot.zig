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

/// To be populated with retrieved node-specific fields from a dif-node/tree
const NodeParams = struct {
    label: ?[]const u8 = null,
    bgcolor: ?[]const u8 = null,
    fgcolor: ?[]const u8 = null,
    shape: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

/// To be populated with retrieved edge-specific fields from a dif-node/tree
const EdgeParams = struct {
    label: ?[]const u8 = null,
    edge_style: ?dif.EdgeStyle = null,
    source_symbol: ?dif.EdgeEndStyle = null,
    source_label: ?[]const u8 = null,
    target_symbol: ?dif.EdgeEndStyle = null,
    target_label: ?[]const u8 = null,
};

/// To be populated with retrieved group-specific fields from a dif-node/tree
/// The top level diagram is also considered a group in this context.
const GroupParams = struct {
    label: ?[]const u8 = null,
    layout: ?[]const u8 = null,
    bgcolor: ?[]const u8 = null,
    note: ?[]const u8 = null,
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
            var i: usize = 0;
            if (lc.col > 0) while (i < lc.col - 1) : (i += 1) {
                err_writer.print(" ", .{}) catch {};
            };
            err_writer.print("^\n", .{}) catch {};
        }
    };
}

/// Extracts a set of predefined key/values, based on the particular ParamsType
fn getFieldsFromChildSet(comptime Writer: type, ctx: *DotContext(Writer), comptime ParamsType: type, first_sibling: *ial.Entry(DifNode), result: *ParamsType) !void {
    var node_ref = first_sibling;
    while (true) {
        const node = node_ref.get();
        // check node type: We're only looking for value-types
        if (node.node_type == .Value) {
            if (node.name) |param_name| {
                switch (ParamsType) {
                    NodeParams => {
                        if (std.mem.eql(u8, "label", param_name)) {
                            result.label = node.data.Value.value;
                        } else if (std.mem.eql(u8, "bgcolor", param_name)) {
                            result.bgcolor = node.data.Value.value;
                        } else if (std.mem.eql(u8, "fgcolor", param_name)) {
                            result.fgcolor = node.data.Value.value;
                        } else if (std.mem.eql(u8, "shape", param_name)) {
                            result.shape = node.data.Value.value;
                        } else if (std.mem.eql(u8, "note", param_name)) {
                            result.note = node.data.Value.value;
                        }
                    },
                    EdgeParams => {
                        if (std.mem.eql(u8, "label", param_name)) {
                            result.label = node.data.Value.value;
                        } else if (std.mem.eql(u8, "edge_style", param_name)) {
                            result.edge_style = dif.EdgeStyle.fromString(node.data.Value.value) catch |e| {
                                ctx.printError(node_ref, "Invalid value for field 'edge_style': {s}", .{node.data.Value.value});
                                return e;
                            };
                        } else if (std.mem.eql(u8, "source_symbol", param_name)) {
                            result.source_symbol = dif.EdgeEndStyle.fromString(node.data.Value.value) catch |e| {
                                ctx.printError(node_ref, "Invalid value for field 'source_symbol': {s}", .{node.data.Value.value});
                                return e;
                            };
                        } else if (std.mem.eql(u8, "target_symbol", param_name)) {
                            result.target_symbol = dif.EdgeEndStyle.fromString(node.data.Value.value) catch |e| {
                                ctx.printError(node_ref, "Invalid value for field 'target_symbol': {s}", .{node.data.Value.value});
                                return e;
                            };
                        } else if (std.mem.eql(u8, "source_label", param_name)) {
                            result.source_label = node.data.Value.value;
                        } else if (std.mem.eql(u8, "target_label", param_name)) {
                            result.target_label = node.data.Value.value;
                        }
                    },
                    GroupParams => {
                        if (std.mem.eql(u8, "label", param_name)) {
                            result.label = node.data.Value.value;
                        } else if (std.mem.eql(u8, "bgcolor", param_name)) {
                            result.bgcolor = node.data.Value.value;
                        } else if (std.mem.eql(u8, "layout", param_name)) {
                            result.layout = node.data.Value.value;
                        } else if (std.mem.eql(u8, "note", param_name)) {
                            result.note = node.data.Value.value;
                        }
                    },
                    else => {
                        debug("ERROR: Unsupported ParamsType {s}. Most likely a bug.\n", .{ParamsType});
                        unreachable;
                    },
                }
            }
        }

        if (node.next_sibling) |*next| {
            node_ref = next;
        } else {
            break;
        }
    }
}

fn renderInstantiation(comptime Writer: type, ctx: *DotContext(Writer), instance: *ial.Entry(DifNode), map_set: DifNodeMapSet) anyerror!void {
    // Early opt out / safeguard. Most likely a bug
    if (instance.get().node_type != .Instantiation) {
        return RenderError.UnexpectedType;
    }

    //
    // Get all parameters of source, target and edge.
    //

    // This also verifies that the source/target nodes actually exists - this should probably be solved at sema (TODO)
    var params_instance: NodeParams = .{};
    var params_node: NodeParams = .{};

    var node_type_name = instance.get().data.Instantiation.target;

    var node = map_set.node_map.get(node_type_name) orelse {
        ctx.printError(instance, "No node '{s}' found\n", .{node_type_name});
        return RenderError.NoSuchNode;
    };

    // TODO: Dilemma; all other fields but label are overrides - if we could solve that, then we could just let
    //       both getNodeFieldsFromChildSet-calls take the same set according to presedence (node, then instantiation)
    if (instance.get().first_child) |*child| {
        try getFieldsFromChildSet(Writer, ctx, @TypeOf(params_instance), child, &params_instance);
    }

    if (node.get().first_child) |*child| {
        try getFieldsFromChildSet(Writer, ctx, @TypeOf(params_node), child, &params_node);
    }

    //
    // Generate the dot output
    //

    // Print node name and start attr-list
    try ctx.print("\"{s}\"[", .{instance.get().name});

    // Compose label
    {
        try ctx.print("label=\"", .{});

        // Instance-name/label
        if (params_instance.label) |label| {
            try ctx.print("{s}", .{label});
        } else if (instance.get().name) |name| {
            try printPrettify(Writer, ctx.writer, name, .{ .do_caps = true });
        }

        // Node-type-name/label
        if (params_node.label orelse node.get().name) |node_label| {
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
        var note_idx = instance.idx;
        try ctx.print(
            \\note_{0x}[label="{1s}",style=filled,fillcolor="#ffffaa",shape=note];
            \\note_{0x} -> "{2s}"[arrowtail=none,arrowhead=none,style=dashed];
            \\
        , .{ note_idx, note, instance.get().name });
    }
}

fn renderRelationship(comptime Writer: type, ctx: *DotContext(Writer), instance: *ial.Entry(DifNode), map_set: DifNodeMapSet) anyerror!void {
    // Early opt out / safeguard. Most likely a bug
    if (instance.get().node_type != .Relationship) {
        return RenderError.UnexpectedType;
    }

    //
    // Get all parameters of source, target and edge.
    //
    // This also verifies that the source/target nodes actually exists - this should probably be solved at sema (TODO)
    var node_name_source = instance.get().name.?;
    var edge_name = instance.get().data.Relationship.edge;
    var node_name_target = instance.get().data.Relationship.target;

    var node_source = map_set.instance_map.get(node_name_source) orelse map_set.group_map.get(node_name_source) orelse {
        ctx.printError(instance, "No instance or group '{s}' found\n", .{node_name_source});
        return error.NoSuchInstance;
    };

    var node_target = map_set.instance_map.get(node_name_target) orelse map_set.group_map.get(node_name_target) orelse {
        ctx.printError(instance, "No instance or group '{s}' found\n", .{node_name_target});
        return error.NoSuchInstance;
    };

    var edge = map_set.edge_map.get(edge_name) orelse {
        ctx.printError(instance, "No edge '{s}' found\n", .{edge_name});
        return error.NoSuchEdge;
    };

    var params_instance: EdgeParams = .{};
    var params_edge: EdgeParams = .{};

    if (instance.get().first_child) |*child| {
        try getFieldsFromChildSet(Writer, ctx, @TypeOf(params_instance), child, &params_instance);
    }

    if (edge.get().first_child) |*child| {
        try getFieldsFromChildSet(Writer, ctx, @TypeOf(params_edge), child, &params_edge);
    }

    //
    // Generate the dot output
    //

    try ctx.print("\"{s}\" -> \"{s}\"[", .{ node_source.get().name, node_target.get().name });

    // Label
    if (params_instance.label orelse params_edge.label) |label| {
        try ctx.print("label=\"{s}\",", .{label});
    } else {
        if (edge.get().name) |label| {
            try ctx.print("label=\"", .{});
            try printPrettify(Writer, ctx.writer, label, .{});
            try ctx.print("\",", .{});
        }
    }

    // if source is group:
    if (node_source.get().node_type == .Group) {
        try ctx.print("ltail=cluster_{s},", .{node_name_source});
    }

    // if target is group:
    if (node_target.get().node_type == .Group) {
        try ctx.print("lhead=cluster_{s},", .{node_name_target});
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
fn renderGeneration(comptime Writer: type, ctx: *DotContext(Writer), instance: *ial.Entry(DifNode), map_set: DifNodeMapSet) anyerror!void {
    var node = instance;

    // Iterate over siblings
    while (true) {
        switch (node.get().node_type) {
            .Unit => {
                if (node.get().first_child) |*child| {
                    try renderGeneration(Writer, ctx, child, map_set);
                }
            },
            .Instantiation => {
                try renderInstantiation(Writer, ctx, node, map_set);
            },
            .Relationship => {
                try renderRelationship(Writer, ctx, node, map_set);
            },
            .Group => {
                // Recurse on groups
                if (node.get().first_child) |*child| {
                    try ctx.print("subgraph cluster_{s} {{\n", .{node.get().name});

                    // Invisible point inside group, used to create edges to/from groups
                    try ctx.print("{s} [shape=point,style=invis,height=0,width=0];", .{node.get().name});
                    try renderGeneration(Writer, ctx, child, map_set);
                    try ctx.print("}}\n", .{});

                    // Checking group-fields in case of label, which shall be created outside of group
                    var params_group: GroupParams = .{};
                    try getFieldsFromChildSet(Writer, ctx, @TypeOf(params_group), child, &params_group);

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
    var params_group: GroupParams = .{};
    try getFieldsFromChildSet(Writer, ctx, @TypeOf(params_group), instance, &params_group);

    if (params_group.label) |label| {
        try ctx.print("label=\"{s}\";labelloc=\"t\";\n", .{label});
    }

    if (params_group.layout) |layout| {
        try ctx.print("layout=\"{s}\";\n", .{layout});
    }
}

pub fn difToDot(comptime Writer: type, ctx: *DotContext(Writer), root_node: *ial.Entry(DifNode), map_set: DifNodeMapSet) !void {
    try ctx.print("strict digraph {{\ncompound=true;\n", .{});
    try renderGeneration(Writer, ctx, root_node, map_set);
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
