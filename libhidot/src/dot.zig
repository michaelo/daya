/// Module for taking the DIF and convert it into proper DOT
const std = @import("std");
const main = @import("main.zig");
const bufwriter = @import("bufwriter.zig");
const utils = @import("utils.zig");
const testing = std.testing;
const debug = std.debug.print;

const dif = @import("dif.zig");
const DifNode = dif.DifNode;

test "writeNodeFields" {
    // Go through each fields and verify that it gets converted as expected
    var buf: [1024]u8 = undefined;
    var buf_context = bufwriter.ArrayBuf {
        .buf = buf[0..]
    };

    var writer = buf_context.writer();

    var source =
        \\node MyNode {
        \\    label="My label";
        \\    fgcolor="#000000";
        \\    bgcolor="#FF0000";
        \\}
        \\Node: MyNode;
        \\
        ;

    try main.hidotToDot(bufwriter.ArrayBufWriter, writer, source);
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
    var context = bufwriter.ArrayBuf {
        .buf = buf[0..]
    };

    var writer = context.writer();

    var source =
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

    try main.hidotToDot(bufwriter.ArrayBufWriter, writer, source);
    // Check that certain strings actually gets converted. It might not be 100% correct, but is intended to catch that
    // basic flow of logic is happening
    try testing.expect(std.mem.indexOf(u8, context.slice(), "Edge label") != null);
    try testing.expect(std.mem.indexOf(u8, context.slice(), "arrowhead=vee") != null);
    try testing.expect(std.mem.indexOf(u8, context.slice(), "arrowtail=normal") != null);
}

const DifNodeMap = std.StringHashMap(*DifNode);

const RenderError = error{
    UnexpectedType,
    NoSuchNode,
    NoSuchEdge,
    NoSuchInstance,
    OutOfMemory,
};

const NodeParams = struct {
    label: ?[]const u8 = null,
    bgcolor: ?[]const u8 = null,
    fgcolor: ?[]const u8 = null,
    shape: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

const EdgeParams = struct {
    label: ?[]const u8 = null,
    edge_style: ?dif.EdgeStyle = null,
    source_symbol: ?dif.EdgeEndStyle = null,
    source_label: ?[]const u8 = null,
    target_symbol: ?dif.EdgeEndStyle = null,
    target_label: ?[]const u8 = null,
};

const GroupParams = struct {
    label: ?[]const u8 = null,
    layout: ?[]const u8 = null,
    bgcolor: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

// Take a string and with simple heuristics try to make it more readable (replaces _ with space upon print)
// TODO: Support unicode properly
fn printPrettify(comptime Writer: type, writer: Writer, label: []const u8, comptime opts: struct {
    do_caps: bool = false,
}) !void {
    const State = enum {
        space,
        plain,
    };
    var state: State = .space;
    for (label) |c| {
        var fc = blk: {
            switch (state) {
                // First char of string or after space
                .space => switch (c) {
                    '_', ' ' => break :blk ' ',
                    else => {
                        state = .plain;
                        break :blk if(opts.do_caps) std.ascii.toUpper(c) else c;
                    },
                },
                .plain => switch (c) {
                    '_', ' ' => {
                        state = .space;
                        break :blk ' ';
                    },
                    else => break :blk c,
                },
            }
        };
        try writer.print("{c}", .{fc});
    }
}

test "printPrettify" {
    // Setup custom writer with buffer we can inspect
    var buf: [128]u8 = undefined;
    var bufctx = bufwriter.ArrayBuf {
        .buf = buf[0..]
    };

    var writer = bufctx.writer();

    try printPrettify(@TypeOf(writer), writer, "label", .{});
    try testing.expectEqualStrings("label", bufctx.slice());
    bufctx.reset();

    try printPrettify(@TypeOf(writer), writer, "label", .{.do_caps=true});
    try testing.expectEqualStrings("Label", bufctx.slice());
    bufctx.reset();

    try printPrettify(@TypeOf(writer), writer, "label_part", .{});
    try testing.expectEqualStrings("label part", bufctx.slice());
    bufctx.reset();

    try printPrettify(@TypeOf(writer), writer, "Hey Der", .{});
    try testing.expectEqualStrings("Hey Der", bufctx.slice());
    bufctx.reset();

    try printPrettify(@TypeOf(writer), writer, "æøå_æøå", .{}); // TODO: unicode not handled
    try testing.expectEqualStrings("æøå æøå", bufctx.slice());
    bufctx.reset();

    // Not working
    // try printPrettify(@TypeOf(writer), writer, "æøå_æøå", .{.do_caps=true}); // TODO: unicode not handled
    // try testing.expectEqualStrings("Æøå Æøå", bufctx.slice());
    // bufctx.reset();
}


pub fn DotContext(comptime Writer: type) type {
    return struct {
        const Self = @This();

        src_buf: []const u8,
        writer: Writer,

        pub fn init(writer: Writer, src_buf: []const u8) Self {
            return Self{
                .writer = writer,
                .src_buf = src_buf,
            };
        }

        fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            try self.writer.print(fmt, args);
        }

        fn printError(self: *Self, node: *dif.DifNode, comptime fmt: []const u8, args: anytype) void {
            const errPrint = std.io.getStdErr().writer().print;
            var lc = utils.idxToLineCol(self.src_buf, node.initial_token.?.start);
            errPrint("ERROR ({d}:{d}): ", .{lc.line, lc.col}) catch {};
            errPrint(fmt, args) catch {};
            errPrint("\n", .{}) catch {};
            utils.dumpSrcChunkRef(self.src_buf, node.initial_token.?.start);
            errPrint("\n", .{}) catch {};

            // Print ^ at start of symbol
            var i: usize = 0;
            if(lc.col > 0) while(i<lc.col-1): (i+=1) {
                errPrint(" ", .{}) catch {};
            };
            errPrint("^\n", .{}) catch {};
        }
    };
}

test "continue here" {
    testing.expect(false);
}

/// Pre-populated sets of indexes to the different difnodes
pub const DifNodeMapSet = struct{
    node_map: *DifNodeMap,
    edge_map: *DifNodeMap,
    instance_map: *DifNodeMap,
    group_map: *DifNodeMap,
};

/// Extracts a set of predefined key/values, based on the particular ParamsType
/// TODO: How to best output or return error when e.g. parsing enum from string? Pass in a DotContext with reference to source buffer, then print from inside?
fn getFieldsFromChildSet(comptime Writer: type, ctx: *DotContext(Writer), comptime ParamsType: type, first_sibling: *DifNode, result: *ParamsType) !void {
    var node = first_sibling;
    while (true) {
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
                                ctx.printError(node, "Invalid value for field 'edge_style': {s}\n", .{node.data.Value.value});
                                return e;
                            };
                        } else if (std.mem.eql(u8, "source_symbol", param_name)) {
                            result.source_symbol = dif.EdgeEndStyle.fromString(node.data.Value.value) catch |e| {
                                ctx.printError(node, "Invalid value for field 'source_symbol': {s}\n", .{node.data.Value.value});
                                return e;
                            };
                        } else if (std.mem.eql(u8, "target_symbol", param_name)) {
                            result.target_symbol = dif.EdgeEndStyle.fromString(node.data.Value.value) catch |e| {
                                ctx.printError(node, "Invalid value for field 'target_symbol': {s}\n", .{node.data.Value.value});
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
                        debug("ERROR: Unsupported ParamsType {s}\n", .{ParamsType});
                        unreachable;
                    },
                }
            }
        }

        if (node.next_sibling) |next| {
            node = next;
        } else {
            break;
        }
    }
}

fn renderInstantiation(comptime Writer: type, ctx: *DotContext(Writer), instance: *DifNode, nodeMap: *DifNodeMap) anyerror!void {
    if (instance.node_type != .Instantiation) {
        return RenderError.UnexpectedType;
    }

    var instanceParams: NodeParams = .{};
    var nodeParams: NodeParams = .{};

    var nodeName = instance.data.Instantiation.target;

    var node = nodeMap.get(nodeName) orelse {
        ctx.printError(instance, "No node {s} found\n", .{nodeName});
        return RenderError.NoSuchNode;
    };

    // TODO: Dilemma; all other fields but label are overrides - if we could solve that, then we could just let
    //       both getNodeFieldsFromChildSet-calls take the same set according to presedence (node, then instantiation)
    if (instance.first_child) |child| {
        try getFieldsFromChildSet(Writer, ctx, @TypeOf(instanceParams), child, &instanceParams);
    }

    if (node.first_child) |child| {
        try getFieldsFromChildSet(Writer, ctx, @TypeOf(nodeParams), child, &nodeParams);
    }

    // Print node name and start attr-list
    try ctx.print("    \"{s}\"[", .{instance.name});

    // Compose label
    {
        try ctx.print("label=\"", .{});

        // Instance-name/label
        if (instanceParams.label) |label| {
            try ctx.print("{s}", .{label});
        } else if (instance.name) |name| {
            try printPrettify(Writer, ctx.writer, name, .{.do_caps = true});
        }

        // Node-type-name/label
        if (nodeParams.label orelse node.name) |node_label| {
            try ctx.print("\n{s}", .{node_label});
        }

        try ctx.print("\",", .{});
    }

    // Shape
    if (instanceParams.shape orelse nodeParams.shape) |shape| {
        try ctx.print("shape=\"{s}\",", .{shape});
    }

    // Foreground
    if (instanceParams.fgcolor orelse nodeParams.fgcolor) |fgcolor| {
        try ctx.print("fontcolor=\"{0s}\",", .{fgcolor});
    }

    // Background
    if (instanceParams.bgcolor orelse nodeParams.bgcolor) |bgcolor| {
        try ctx.print("style=filled,bgcolor=\"{0s}\",fillcolor=\"{0s}\",", .{bgcolor});
    }

    // end attr-list/node
    try ctx.print("];\n", .{});

    // Check for note:
    if(instanceParams.note) |note| {
        // TODO: generate node name (comment_NN?)? Or does dot support anonymous "inline"-nodes?
        try ctx.print(
            \\note_{0x}[label="{1s}",style=filled,fillcolor="#ffffaa",shape=note];
            \\note_{0x} -> "{2s}"[arrowtail=none,arrowhead=none,style=dashed];
            \\
        , .{@ptrToInt(instance), note, instance.name});
    }
}

fn renderRelationship(comptime Writer: type, ctx: *DotContext(Writer), instance: *DifNode, instanceMap: *DifNodeMap, edgeMap: *DifNodeMap) anyerror!void {
    if (instance.node_type != .Relationship) {
        return RenderError.UnexpectedType;
    }

    var sourceNodeName = instance.name.?;
    var edgeName = instance.data.Relationship.edge;
    var targetNodeName = instance.data.Relationship.target;

    var sourceNode = instanceMap.get(sourceNodeName) orelse {
        ctx.printError(instance, "No instance {s} found\n", .{sourceNodeName});
        return error.NoSuchInstance;
    };

    var targetNode = instanceMap.get(targetNodeName) orelse {
        ctx.printError(instance, "No instance {s} found\n", .{targetNodeName});
        return error.NoSuchInstance;
    };

    var edge = edgeMap.get(edgeName) orelse {
        ctx.printError(instance, "No edge {s} found\n", .{edgeName});
        return error.NoSuchEdge;
    };

    var instanceParams: EdgeParams = .{};
    var edgeParams: EdgeParams = .{};

    if (instance.first_child) |child| {
        try getFieldsFromChildSet(Writer, ctx, @TypeOf(instanceParams), child, &instanceParams);
    }

    if (edge.first_child) |child| {
        try getFieldsFromChildSet(Writer, ctx, @TypeOf(edgeParams), child, &edgeParams);
    }

    try ctx.print("\"{s}\" -> \"{s}\"[", .{ sourceNode.name, targetNode.name });

    // Label
    if (instanceParams.label orelse edgeParams.label) |label| {
        try ctx.print("label=\"{s}\",", .{label});
    } else {
        if (edge.name) |label| {
            try ctx.print("label=\"", .{});
            try printPrettify(Writer, ctx.writer, label, .{});
            try ctx.print("\",", .{});
        }
    }

    // Style
    var edge_style = instanceParams.edge_style orelse edgeParams.edge_style orelse dif.EdgeStyle.solid;

    // Start edge
    try ctx.print("style=\"{s}\",", .{std.meta.tagName(edge_style)});

    try ctx.print("dir=both,", .{});

    if(instanceParams.source_symbol orelse edgeParams.source_symbol) |source_symbol| {
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
    if(instanceParams.target_symbol orelse edgeParams.target_symbol) |target_symbol| {
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
fn renderGeneration(comptime Writer: type, ctx: *DotContext(Writer), instance: *DifNode, nodeMap: *DifNodeMap, edgeMap: *DifNodeMap, instanceMap: *DifNodeMap) anyerror!void {
    var node: *DifNode = instance;

    // Iterate over siblings
    while (true) {
        switch (node.node_type) {
            .Instantiation => {
                try renderInstantiation(Writer, ctx, node, nodeMap);
            },
            .Relationship => {
                try renderRelationship(Writer, ctx, node, instanceMap, edgeMap);
            },
            .Group => {
                // Recurse on groups
                if (node.first_child) |child| {
                    try ctx.print("subgraph cluster_{s} {{\n", .{node.name});

                    // Invisible point inside group, used to create edges to/from groups
                    try ctx.print("{s} [shape=point,style=invis,height=0,width=0];", .{node.name});
                    try renderGeneration(Writer, ctx, child, nodeMap, edgeMap, instanceMap);
                    try ctx.print("}}\n", .{});

                    // Checking group-fields in case of label, which shall be created outside of group
                    var groupParams: GroupParams = .{};
                    try getFieldsFromChildSet(Writer, ctx, @TypeOf(groupParams), child, &groupParams);
                    
                    // Check for note:
                    if(groupParams.note) |note| {
                        var note_idx = @ptrToInt(instance);
                        try ctx.print(
                            \\note_{0x}[label="{1s}",style=filled,fillcolor="#ffffaa",shape=note];
                            \\note_{0x} -> {2s}[lhead=cluster_{2s},arrowtail=none,arrowhead=none,style=dashed];
                            \\
                        , .{note_idx, note, node.name});
                    }
                }
            },
            else => {},
        }

        if (node.next_sibling) |next| {
            node = next;
        } else {
            break;
        }
    }

    // Group-level attributes
    var groupParams: GroupParams = .{};
    try getFieldsFromChildSet(Writer, ctx, @TypeOf(groupParams), instance, &groupParams);

    if (groupParams.label) |label| {
        try ctx.print("label=\"{s}\";labelloc=\"t\";\n", .{label});
    }

    if (groupParams.layout) |layout| {
        try ctx.print("layout=\"{s}\";\n", .{layout});
    }
}

pub fn difToDot(comptime Writer: type, ctx: *DotContext(Writer), root_node: *DifNode, map_set: DifNodeMapSet) !void {
    try ctx.print("strict digraph {{\ncompound=true;\n", .{});
    try renderGeneration(Writer, ctx, root_node, map_set.node_map, map_set.edge_map, map_set.instance_map);
    try ctx.print("}}\n", .{});
}
