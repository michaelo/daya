/// Module for taking the DIF and convert it into proper DOT

const std = @import("std");
const main = @import("main.zig");
const bufwriter = @import("bufwriter.zig");
const testing = std.testing;
const debug = std.debug.print;

const dif = @import("dif.zig");
const DifNode = dif.DifNode;

// fn writeNodeFields(comptime Writer: type, node: *const dif.NodeInstance, def: *const dif.NodeDefinition, writer: Writer) !void {
//     try writer.writeAll("[");
//     if(def.label) |value| {
//         try writer.print("label=\"{s}\\n{s}\",", .{node.name,value});
//     }
//     if(def.shape) |value| {
//         try writer.print("shape=\"{s}\",", .{std.meta.tagName(value)});
//     }
//     if(def.bg_color) |value| {
//         try writer.print("style=filled,bgcolor=\"{0s}\",fillcolor=\"{0s}\",", .{value});
//     }
//     if(def.fg_color) |value| {
//         try writer.print("fontcolor=\"{0s}\",", .{value});
//         // color=\"{0s}\", -- lines
//     }
//     try writer.writeAll("]");
// }

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


// fn writeRelationshipFields(comptime Writer: type, def: *const dif.Relationship, writer: Writer) !void {
//     try writer.writeAll("[");
//     if(def.edge.label) |value| {
//         try writer.print("label=\"{s}\",", .{value});
//     }
//     if(def.edge.edge_style) |value| {
//         try writer.print("style=\"{s}\",", .{std.meta.tagName(value)});
//     }
//     {
//         var arrow = switch(def.edge.target_symbol) {
//             .arrow_open => "vee",
//             .arrow_closed => "onormal",
//             .arrow_filled => "normal",
//             .none => "none",
//             // else => return error.NoSuchArrow,
//         };
//         try writer.print("arrowhead={s},", .{arrow});
//     }

//     {
//         var arrow = switch(def.edge.source_symbol) {
//             .arrow_open => "vee",
//             .arrow_closed => "onormal",
//             .arrow_filled => "normal",
//             .none => "none",
//             // else => return error.NoSuchArrow,
//         };
//         // TODO: Currently setting dir=both here, but perhaps we should define a set of common defaults at top? E.g. fill, dir=both etc?
//         try writer.print("arrowtail={s},dir=both,", .{arrow});
//     }

//     try writer.writeAll("]");
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

// TODO: Extract the relevant, valid fields for a node

const NodeParams = struct {
    label: ?[]const u8 = null,
    bgcolor: ?[]const u8 = null,
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
    bgcolor: ?[]const u8 = null,
};

fn getFieldsFromChildSet(comptime ParamsType: type, first_sibling: *DifNode, result: *ParamsType) void {
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
                        } else if(std.mem.eql(u8, "shape", param_name)) {
                            result.shape = node.data.Value.value;
                        }
                    },
                    EdgeParams => {
                        if(std.mem.eql(u8, "label", param_name)) {
                            result.label = node.data.Value.value;
                        }
                    },
                    GroupParams => {
                        if(std.mem.eql(u8, "label", param_name)) {
                            result.label = node.data.Value.value;
                        } else if(std.mem.eql(u8, "bgcolor", param_name)) {
                            result.bgcolor = node.data.Value.value;
                        }
                    },
                    else => {
                        debug("ERROR: Unsupported ParamsType\n", .{});
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

    // label: default name of instance + label of node type
    //        if children: look for label there and replace instance.name if found

    var node = nodeMap.get(nodeName) orelse {
        w("ERROR: No node {s} found\n", .{nodeName});
        return RenderError.NoSuchNode;
    };
    // TODO: Dilemma; all other fields but label are overrides - if we could solve that, then we could just let
    //       both getNodeFieldsFromChildSet-calls take the same set according to presedence (node, then instantiation)
    if(instance.first_child) |child| {
        getFieldsFromChildSet(@TypeOf(instanceParams), child, &instanceParams);
        // getNodeFieldsFromChildSet(child, &instanceParams);
    }

    if(node.first_child) |child| {
        getFieldsFromChildSet(@TypeOf(nodeParams), child, &nodeParams);
        // getNodeFieldsFromChildSet(child, &nodeParams);
    }

    var instanceLabel = instanceParams.label orelse instance.name; // child-label-attr, orelse .name

    // Extract relevant fields from immediate children: label, fgcolor, bgcolor, edge, shape
    // TODO: Fault on detected grandchildren? No, this should be solved elsewhere...

    // Extract fields from node
    
    // Print node name and start attr-list
    try writer.print("    \"{s}\"[", .{instance.name});

    // Compose label
    try writer.print("label=\"{s}", .{instanceLabel});
    if(node.name != null and node.name.?.len > 0) {
        try writer.print("\n{s}", .{node.name});
    }
    try writer.print("\",", .{});

    // Shape
    // var maybe_shape = instanceParams.shape orelse nodeParams.shape orelse null;
    if(instanceParams.shape orelse nodeParams.shape) |shape| {
        try writer.print("shape=\"{s}\",", .{shape});
    }

    // Foreground


    // Background
    // var maybe_bgcolor = instanceParams.bgcolor orelse nodeParams.bgcolor orelse null;
    if(instanceParams.bgcolor orelse nodeParams.bgcolor) |bgcolor| {
        try writer.print("style=filled,bgcolor=\"{0s}\",fillcolor=\"{0s}\",", .{bgcolor});
    }

    // end attr-list/node
    try writer.writeAll("];\n");
    

    // compose a node by instance name, instance type(node), + immediate children-values, if any.

}

fn renderRelationship(comptime Writer: type, writer: Writer, instance: *DifNode, instanceMap: *DifNodeMap, edgeMap: *DifNodeMap) anyerror!void {
    if(instance.node_type != .Relationship) {
        return RenderError.UnexpectedType;
    }

    var sourceNodeName = instance.name.?;
    var edgeName = instance.data.Relationship.edge;
    var targetNodeName = instance.data.Relationship.target;

    var sourceNode = instanceMap.get(sourceNodeName) orelse {
        return error.NoSuchInstance;
    };

    var targetNode = instanceMap.get(targetNodeName) orelse {
        return error.NoSuchInstance;
    };

    var edge = edgeMap.get(edgeName) orelse {
        return error.NoSuchEdge;
    };

    var instanceParams: EdgeParams = .{};
    var edgeParams: EdgeParams = .{};

    if(instance.first_child) |child| {
        getFieldsFromChildSet(@TypeOf(instanceParams), child, &instanceParams);
    }

    if(edge.first_child) |child| {
        getFieldsFromChildSet(@TypeOf(edgeParams), child, &edgeParams);
    }

    
    try writer.print("\"{s}\" -> \"{s}\"[", .{sourceNode.name, targetNode.name});

    // Label
    var label = instanceParams.label orelse edgeParams.label orelse edge.name;
    try writer.print("label=\"{s}\",", .{label});
    // Style

    // Start edge

    // End edge

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
    getFieldsFromChildSet(@TypeOf(groupParams), instance, &groupParams);

    if(groupParams.label) |label| {
        try writer.print("label=\"{s}\";labelloc=\"t\";\n", .{label});
    }
}

pub fn difToDot(comptime Writer: type, writer: Writer, rootNode: *DifNode) !void {
    // TODO: Currently no scoping of node-types
    // TODO: Take allocator as argument
    var nodeMap = DifNodeMap.init(testing.allocator);
    defer nodeMap.deinit();

    var edgeMap = DifNodeMap.init(testing.allocator);
    defer edgeMap.deinit();

    var instanceMap = DifNodeMap.init(testing.allocator);
    defer instanceMap.deinit();

    try findAllEdgesNodesAndInstances(rootNode, &nodeMap, &edgeMap, &instanceMap);

    // TODO: Need to find all nodes (TBD: scoped by groups?)
    // TODO: Need to find all edges (global)
    // Then, instantiate by group
    // Relationships can be defined at last? At least if there's no scoping-concerns for DOT
    // w("hello: {s}!\n", .{rootNode.name});
    try writer.writeAll("strict digraph {\n");

    // TODO: Implement "include"-support? Enough to append to top node?
    try renderGeneration(Writer, writer, rootNode, &nodeMap, &edgeMap, &instanceMap);

    try writer.writeAll("}\n");
}
