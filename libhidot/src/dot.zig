/// Module for taking the DIF and convert it into proper DOT

const std = @import("std");
const main = @import("main.zig");
const bufwriter = @import("bufwriter.zig");
const testing = std.testing;
const debug = std.debug.print;

const dif = @import("dif.zig");
const DifNode = dif.DifNode;

// test "writeNodeFields" {
//     // Go through each fields and verify that it gets converted as expected
//     var buf: [1024]u8 = undefined;
//     var context = bufwriter.ArrayBuf {
//         .buf = buf[0..]
//     };

//     var writer = context.writer();

//     var source = 
//         \\node MyNode {
//         \\    label: "My label"
//         \\    color: #000000
//         \\    background: #FF0000
//         \\}
//         \\Node: MyNode
//         \\
//         ;

//     try main.hidotToDot(bufwriter.ArrayBufWriter, source, writer);
//     // Check that certain strings actually gets converted. It might not be 100% correct, but is intended to catch that
//     // basic flow of logic is happening
//     // debug("out: {s}\n", .{context.slice()});
//     try testing.expect(std.mem.indexOf(u8, context.slice(), "\"Node\"") != null);
//     try testing.expect(std.mem.indexOf(u8, context.slice(), "My label") != null);
//     try testing.expect(std.mem.indexOf(u8, context.slice(), "bgcolor=\"#FF0000\"") != null);
//     try testing.expect(std.mem.indexOf(u8, context.slice(), "color=\"#000000\"") != null);
// }


// test "writeRelationshipFields" {
//     // Go through each fields and verify that it gets converted as expected
//     var buf: [1024]u8 = undefined;
//     var context = bufwriter.ArrayBuf {
//         .buf = buf[0..]
//     };

//     var writer = context.writer();

//     var source = 
//         \\node MyNode {}
//         \\edge Uses {
//         \\    label: "Edge label"
//         \\    sourceSymbol: arrow_filled
//         \\    targetSymbol: arrow_open
//         \\}
//         \\NodeA: MyNode
//         \\NodeB: MyNode
//         \\NodeA Uses NodeB
//         \\
//         ;

//     try main.hidotToDot(bufwriter.ArrayBufWriter, source, writer);
//     // Check that certain strings actually gets converted. It might not be 100% correct, but is intended to catch that
//     // basic flow of logic is happening
//     // debug("out: {s}\n", .{context.slice()});
//     try testing.expect(std.mem.indexOf(u8, context.slice(), "Edge label") != null);
//     // try testing.expect(std.mem.indexOf(u8, context.slice(), "Uses") != null);
//     try testing.expect(std.mem.indexOf(u8, context.slice(), "arrowhead=vee") != null);
//     try testing.expect(std.mem.indexOf(u8, context.slice(), "arrowtail=normal") != null);
// }

const DifNodeMap = std.StringHashMap(*DifNode);

// Parse the entire node-tree from <node>, populate the maps with references to nodes, edges and instantiations indexed by their .name
fn findAllEdgesNodesAndInstances(node: *DifNode, nodeMap: *DifNodeMap, edgeMap: *DifNodeMap, instanceMap: *DifNodeMap) error{OutOfMemory}!void {
    switch(node.node_type) {
        .Node => {
            try nodeMap.put(node.name.?, node);
        },
        .Edge => {
            try edgeMap.put(node.name.?, node);
        },
        .Instantiation => {
            try instanceMap.put(node.name.?, node);
        },
        else => {}
    }
    
    if (node.first_child) |child| {
        try findAllEdgesNodesAndInstances(child, nodeMap, edgeMap, instanceMap);
    }

    if (node.next_sibling) |next| {
        try findAllEdgesNodesAndInstances(next, nodeMap, edgeMap, instanceMap);
    }
}

const RenderError = error {
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
};

const EdgeParams = struct {
    label: ?[]const u8 = null,

    // TODO:
    edge_style: ?dif.EdgeStyle = dif.EdgeStyle.solid,
    source_symbol: dif.EdgeEndStyle = dif.EdgeEndStyle.none,
    source_label: ?[]const u8 = null,
    target_symbol: dif.EdgeEndStyle = dif.EdgeEndStyle.arrow_open,
    target_label: ?[]const u8 = null,
};

const GroupParams = struct {
    label: ?[]const u8 = null,
    layout: ?[]const u8 = null,
    bgcolor: ?[]const u8 = null,
};

// Take a string and with simple heuristics try to make it more readable (replaces _ with space upon print)
fn printPrettify(comptime Writer: type, writer: Writer, label: []const u8) !void {
    for(label) |c| {
        try writer.print("{c}", .{switch(c) {
            '_' => ' ',
            else => c
        }});
    }
}

// Extracts a set of predefined key/values, based on the particular ParamsType
fn getFieldsFromChildSet(comptime ParamsType: type, first_sibling: *DifNode, result: *ParamsType) !void {
    var node = first_sibling;
    while(true) {
        // check node type: We're only looking for value-types
        if(node.node_type == .Value) {
            if(node.name) |param_name| {
                switch(ParamsType) {
                    NodeParams => {
                        if(std.mem.eql(u8, "label", param_name)) {
                            result.label = node.data.Value.value;
                        } else if(std.mem.eql(u8, "bgcolor", param_name)) {
                            result.bgcolor = node.data.Value.value;
                        } else if(std.mem.eql(u8, "fgcolor", param_name)) {
                            result.fgcolor = node.data.Value.value;
                        } else if(std.mem.eql(u8, "shape", param_name)) {
                            result.shape = node.data.Value.value;
                        }
                    },
                    EdgeParams => {
                        if(std.mem.eql(u8, "label", param_name)) {
                            result.label = node.data.Value.value;
                        } else if(std.mem.eql(u8, "edge_style", param_name)) {
                            result.edge_style = try dif.EdgeStyle.fromString(node.data.Value.value);
                        } else if(std.mem.eql(u8, "source_symbol", param_name)) {
                            result.source_symbol = try dif.EdgeEndStyle.fromString(node.data.Value.value);
                        } else if(std.mem.eql(u8, "target_symbol", param_name)) {
                            result.target_symbol = try dif.EdgeEndStyle.fromString(node.data.Value.value);
                        } else if(std.mem.eql(u8, "source_label", param_name)) {
                            result.source_label = node.data.Value.value;
                        } else if(std.mem.eql(u8, "target_label", param_name)) {
                            result.target_label = node.data.Value.value;
                        }
                    },
                    GroupParams => {
                        if(std.mem.eql(u8, "label", param_name)) {
                            result.label = node.data.Value.value;
                        } else if(std.mem.eql(u8, "bgcolor", param_name)) {
                            result.bgcolor = node.data.Value.value;
                        } else if(std.mem.eql(u8, "layout", param_name)) {
                            result.layout = node.data.Value.value;
                        }
                    },
                    else => {
                        debug("ERROR: Unsupported ParamsType {s}\n", .{ParamsType});
                        unreachable;
                    }
                }
            }
        }

        if(node.next_sibling) |next| {
            node = next;
        } else {
            break;
        }
    }
}

fn renderInstantiation(comptime Writer: type, writer: Writer, instance: *DifNode, nodeMap: *DifNodeMap) anyerror!void {
    if(instance.node_type != .Instantiation) {
        return RenderError.UnexpectedType;
    }

    const w = debug;

    var instanceParams: NodeParams = .{};
    var nodeParams: NodeParams = .{};

    var nodeName = instance.data.Instantiation.target;

    var node = nodeMap.get(nodeName) orelse {
        w("ERROR: No node {s} found\n", .{nodeName});
        return RenderError.NoSuchNode;
    };

    // TODO: Dilemma; all other fields but label are overrides - if we could solve that, then we could just let
    //       both getNodeFieldsFromChildSet-calls take the same set according to presedence (node, then instantiation)
    if(instance.first_child) |child| {
        try getFieldsFromChildSet(@TypeOf(instanceParams), child, &instanceParams);
    }

    if(node.first_child) |child| {
        try getFieldsFromChildSet(@TypeOf(nodeParams), child, &nodeParams);
    }

    var instanceLabel = instanceParams.label orelse instance.name; // child-label-attr, orelse .name
    
    // Print node name and start attr-list
    try writer.print("    \"{s}\"[", .{instance.name});

    // Compose label
    try writer.print("label=\"{s}", .{instanceLabel});
    if(nodeParams.label orelse node.name) |node_label| {
        try writer.print("\n{s}", .{node_label});
    }
    try writer.print("\",", .{});

    // Shape
    if(instanceParams.shape orelse nodeParams.shape) |shape| {
        try writer.print("shape=\"{s}\",", .{shape});
    }

    // Foreground
    if(instanceParams.fgcolor orelse nodeParams.fgcolor) |fgcolor| {
        try writer.print("fontcolor=\"{0s}\",", .{fgcolor});
    }

    // Background
    if(instanceParams.bgcolor orelse nodeParams.bgcolor) |bgcolor| {
        try writer.print("style=filled,bgcolor=\"{0s}\",fillcolor=\"{0s}\",", .{bgcolor});
    }

    // end attr-list/node
    try writer.writeAll("];\n");
}

fn renderRelationship(comptime Writer: type, writer: Writer, instance: *DifNode, instanceMap: *DifNodeMap, edgeMap: *DifNodeMap) anyerror!void {
    if(instance.node_type != .Relationship) {
        return RenderError.UnexpectedType;
    }

    var sourceNodeName = instance.name.?;
    var edgeName = instance.data.Relationship.edge;
    var targetNodeName = instance.data.Relationship.target;

    var sourceNode = instanceMap.get(sourceNodeName) orelse {
        debug("ERROR: No instance {s} found\n", .{sourceNodeName});
        return error.NoSuchInstance;
    };

    var targetNode = instanceMap.get(targetNodeName) orelse {
        debug("ERROR: No instance {s} found\n", .{targetNodeName});
        return error.NoSuchInstance;
    };

    var edge = edgeMap.get(edgeName) orelse {
        return error.NoSuchEdge;
    };

    var instanceParams: EdgeParams = .{};
    var edgeParams: EdgeParams = .{};

    if(instance.first_child) |child| {
        try getFieldsFromChildSet(@TypeOf(instanceParams), child, &instanceParams);
    }

    if(edge.first_child) |child| {
        try getFieldsFromChildSet(@TypeOf(edgeParams), child, &edgeParams);
    }

    
    try writer.print("\"{s}\" -> \"{s}\"[", .{sourceNode.name, targetNode.name});

    // Label
    if(instanceParams.label orelse edgeParams.label) |label| {
        try writer.print("label=\"{s}\",", .{label});
    } else {
        if(edge.name) |label| {
            try writer.print("label=\"", .{});
            try printPrettify(Writer, writer, label);
            try writer.print("\",", .{});
        }
    }

    // Style
    var edge_style = instanceParams.edge_style orelse dif.EdgeStyle.solid;

    // Start edge
    try writer.print("style=\"{s}\",", .{std.meta.tagName(edge_style)});

    try writer.print("dir=both,", .{});

    {
        var arrow = switch(instanceParams.source_symbol) {
            .arrow_open => "vee",
            .arrow_closed => "onormal",
            .arrow_filled => "normal",
            .none => "none",
            // else => return error.NoSuchArrow,
        };
        // TODO: Currently setting dir=both here, but perhaps we should define a set of common defaults at top? E.g. fill, dir=both etc?
        try writer.print("arrowtail={s},dir=both,", .{arrow});
    }

    // End edge
    {
        var arrow = switch(instanceParams.target_symbol) {
            .arrow_open => "vee",
            .arrow_closed => "onormal",
            .arrow_filled => "normal",
            .none => "none",
            // else => return error.NoSuchArrow,
        };
        try writer.print("arrowhead={s},", .{arrow});
    }

    try writer.writeAll("];\n");
}

/// Recursive
fn renderGeneration(comptime Writer: type, writer: Writer, instance: *DifNode, nodeMap: *DifNodeMap, edgeMap: *DifNodeMap, instanceMap: *DifNodeMap) anyerror!void {
    var node: *DifNode = instance;

    // Iterate over siblings
    while(true) {
        switch(node.node_type) {
            .Instantiation => {
                try renderInstantiation(Writer, writer, node, nodeMap);
            },
            .Relationship => {
                try renderRelationship(Writer, writer, node, instanceMap, edgeMap);
            },
            .Group => {
                // Recurse on groups
                try writer.print("subgraph cluster_{s} {{\n", .{node.name});
                if(node.first_child) |child| {
                    try renderGeneration(Writer, writer, child, nodeMap, edgeMap, instanceMap);
                }
                try writer.writeAll("}\n");
            },
            else => {}
        }

        if (node.next_sibling) |next| {
            node = next;
        } else {
            break;
        }
    }

    // Group-level attributes
    var groupParams: GroupParams = .{};
    try getFieldsFromChildSet(@TypeOf(groupParams), instance, &groupParams);

    if(groupParams.label) |label| {
        try writer.print("label=\"{s}\";labelloc=\"t\";\n", .{label});
    }

    if(groupParams.layout) |layout| {
        try writer.print("layout=\"{s}\";\n", .{layout});
    }
}

pub fn difToDot(comptime Writer: type, writer: Writer, allocator: std.mem.Allocator, rootNode: *DifNode) !void {
    // Att: Currently no scoping of node-types
    // TODO: Take allocator as argument
    var nodeMap = DifNodeMap.init(allocator);
    defer nodeMap.deinit();

    var edgeMap = DifNodeMap.init(allocator);
    defer edgeMap.deinit();

    var instanceMap = DifNodeMap.init(allocator);
    defer instanceMap.deinit();

    try findAllEdgesNodesAndInstances(rootNode, &nodeMap, &edgeMap, &instanceMap);

    try writer.writeAll("strict digraph {\n");
    // try writer.writeAll("layout=fdp;");

    // TODO: Implement "include"-support? Enough to append to top node?
    try renderGeneration(Writer, writer, rootNode, &nodeMap, &edgeMap, &instanceMap);

    try writer.writeAll("}\n");
}
