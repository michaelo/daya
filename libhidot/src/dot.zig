/// Module for taking the DIF and convert it into proper DOT

const std = @import("std");
const main = @import("main.zig");
const bufwriter = @import("bufwriter.zig");
const testing = std.testing;
const debug = std.debug.print;

const dif = @import("dif.zig");
const Dif = dif.Dif;

fn writeNodeFields(comptime Writer: type, node: *const dif.NodeInstance, def: *const dif.NodeDefinition, writer: Writer) !void {
    try writer.writeAll("[");
    if(def.label) |value| {
        try writer.print("label=\"{s}\\n{s}\",", .{node.name,value});
    }
    if(def.shape) |value| {
        try writer.print("shape=\"{s}\",", .{std.meta.tagName(value)});
    }
    if(def.bg_color) |value| {
        try writer.print("style=filled,bgcolor=\"{0s}\",fillcolor=\"{0s}\",", .{value});
    }
    if(def.fg_color) |value| {
        try writer.print("fontcolor=\"{0s}\",", .{value});
        // color=\"{0s}\", -- lines
    }
    try writer.writeAll("]");
}

test "writeNodeFields" {
    // Go through each fields and verify that it gets converted as expected
    var buf: [1024]u8 = undefined;
    var context = bufwriter.ArrayBuf {
        .buf = buf[0..]
    };

    var writer = context.writer();

    var source = 
        \\node MyNode {
        \\    label: "My label"
        \\    color: #000000
        \\    background: #FF0000
        \\}
        \\Node: MyNode
        \\
        ;

    try main.hidotToDot(bufwriter.ArrayBufWriter, source, writer);
    // Check that certain strings actually gets converted. It might not be 100% correct, but is intended to catch that
    // basic flow of logic is happening
    // debug("out: {s}\n", .{context.slice()});
    try testing.expect(std.mem.indexOf(u8, context.slice(), "\"Node\"") != null);
    try testing.expect(std.mem.indexOf(u8, context.slice(), "My label") != null);
    try testing.expect(std.mem.indexOf(u8, context.slice(), "bgcolor=\"#FF0000\"") != null);
    try testing.expect(std.mem.indexOf(u8, context.slice(), "color=\"#000000\"") != null);
}


fn writeRelationshipFields(comptime Writer: type, def: *const dif.Relationship, writer: Writer) !void {
    try writer.writeAll("[");
    if(def.edge.label) |value| {
        try writer.print("label=\"{s}\",", .{value});
    }
    if(def.edge.edge_style) |value| {
        try writer.print("style=\"{s}\",", .{std.meta.tagName(value)});
    }
    {
        var arrow = switch(def.edge.target_symbol) {
            .arrow_open => "vee",
            .arrow_closed => "onormal",
            .arrow_filled => "normal",
            .none => "none",
            // else => return error.NoSuchArrow,
        };
        try writer.print("arrowhead={s},", .{arrow});
    }

    {
        var arrow = switch(def.edge.source_symbol) {
            .arrow_open => "vee",
            .arrow_closed => "onormal",
            .arrow_filled => "normal",
            .none => "none",
            // else => return error.NoSuchArrow,
        };
        // TODO: Currently setting dir=both here, but perhaps we should define a set of common defaults at top? E.g. fill, dir=both etc?
        try writer.print("arrowtail={s},dir=both,", .{arrow});
    }

    try writer.writeAll("]");
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
        \\    label: "Edge label"
        \\    sourceSymbol: arrow_filled
        \\    targetSymbol: arrow_open
        \\}
        \\NodeA: MyNode
        \\NodeB: MyNode
        \\NodeA Uses NodeB
        \\
        ;

    try main.hidotToDot(bufwriter.ArrayBufWriter, source, writer);
    // Check that certain strings actually gets converted. It might not be 100% correct, but is intended to catch that
    // basic flow of logic is happening
    // debug("out: {s}\n", .{context.slice()});
    try testing.expect(std.mem.indexOf(u8, context.slice(), "Edge label") != null);
    // try testing.expect(std.mem.indexOf(u8, context.slice(), "Uses") != null);
    try testing.expect(std.mem.indexOf(u8, context.slice(), "arrowhead=vee") != null);
    try testing.expect(std.mem.indexOf(u8, context.slice(), "arrowtail=normal") != null);
}

/// Take the Dif and convert it to well-defined DOT. Returns size of dot-buffer
pub fn difToDot(comptime Writer: type, src_dif: *Dif, writer: Writer) !void {
    try writer.writeAll("strict digraph {\n");
    // var len: usize = 0;
    /////////////////////////////
    // The actual graph output
    /////////////////////////////

    // TODO: Pr node, resolve the corresponding nodeDefinition and create entry
    for(src_dif.nodeInstance.slice()) |el| {
        try writer.print("    \"{s}\"", .{el.name});
        _ = try writeNodeFields(Writer, &el, el.type, writer);
        try writer.writeAll("\n");
    }

    // Iterate over all relations
    for(src_dif.nodeInstance.slice()) |*el| {
        for(el.relationships.slice()) |*rel| {
            try writer.print("    \"{s}\"->\"{s}\"", .{el.name, rel.target.name});
            _ = try writeRelationshipFields(Writer, rel, writer);
            try writer.writeAll("\n");

        }
    }


    // Finish
    try writer.writeAll("}\n");

    // return len;
}


pub fn difToDebug(src_dif: *Dif, out_buf: []u8) !usize {
    // TODO: Replace with proper dot-definitions
    var len: usize = 0;
    for(src_dif.nodeDefinitions.slice()) |el| {
        len += (try std.fmt.bufPrint(out_buf[len..],
        \\nodeDefinition: {s}
        \\  label: "{s}"
        \\  shape: {s}
        \\  fg_color: {s}
        \\  bg_color: {s}
        \\
        , .{el.name, el.label, el.shape, el.fg_color, el.bg_color})).len;
    }

    for(src_dif.edgeDefinitions.slice()) |el| {
        len += (try std.fmt.bufPrint(out_buf[len..],
            \\edgeDefinition: {s}
            \\  label: "{s}"
            \\  edge_style: {s}
            \\  source_symbol: {s}
            \\  target_symbol: {s}
            \\
            , .{el.name, el.label, el.edge_style, el.source_symbol, el.target_symbol})).len;
    }

    for(src_dif.nodeInstance.slice()) |el| {
        len += (try std.fmt.bufPrint(out_buf[len..], "nodeInstance: {s}\n", .{el.name})).len;
    }

    return len;
}
