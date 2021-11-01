/// Module for taking the DIF and convert it into proper DOT

const std = @import("std");
const dif = @import("dif.zig");
const Dif = dif.Dif;

fn writeNodeFields(node: *const dif.NodeInstance, def: *const dif.NodeDefinition, writer: std.fs.File.Writer) !void {
    try writer.writeAll("[");
    if(def.label) |value| {
        try writer.print("label=\"{s}\\n{s}\",", .{node.name,value});
    }
    if(def.shape) |value| {
        try writer.print("shape=\"{s}\",", .{std.meta.tagName(value)});
    }
    try writer.writeAll("]");
}

fn writeRelationshipFields(def: *const dif.Relationship, writer: std.fs.File.Writer) !void {
    try writer.writeAll("[");
    if(def.edge.label) |value| {
        try writer.print("label=\"{s}\",", .{value});
    }
    if(def.edge.edge_style) |value| {
        try writer.print("style=\"{s}\",", .{std.meta.tagName(value)});
    }
    try writer.writeAll("]");
}

/// Take the Dif and convert it to well-defined DOT. Returns size of dot-buffer
pub fn difToDotFile(src_dif: *Dif, file: std.fs.File) !usize {
    var writer = file.writer();
    try writer.writeAll("strict digraph {\n");
    var len: usize = 0;
    /////////////////////////////
    // The actual graph output
    /////////////////////////////

    // TODO: Pr node, resolve the corresponding nodeDefinition and create entry
    for(src_dif.nodeInstance.slice()) |el| {
        try writer.print("    \"{s}\"", .{el.name});
        _ = try writeNodeFields(&el, el.type, writer);
        try writer.writeAll("\n");
    }

    // Iterate over all relations
    for(src_dif.nodeInstance.slice()) |*el| {
        for(el.relationships.slice()) |*rel| {
            try writer.print("    \"{s}\"->\"{s}\"", .{el.name, rel.target.name});
            _ = try writeRelationshipFields(rel, writer);
            try writer.writeAll("\n");

        }
    }


    // Finish
    try writer.writeAll("}\n");

    return len;
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
