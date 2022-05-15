hidot: Rapid text-based graphing tool
============================

Example usage of compiler:

    hidot myfile.hidot output.dot
    hidot myfile.hidot output.png
    hidot myfile.hidot output.svg

hidot is a tool and library to convert from the hidot format to regular .dot, .png og .svg.

The hidot-format is intended to allow for rapid graphing from text sources. Mostly relationship-like diagrams such as (UML's= activity-, component-diagrams etc. There are currently no plan to add features for sequence-diagrams and such.

It can be thought of as "a subset of dot with custom types" (*).

The subset of attributes and such is highly opiniated, and very much subject to change.

(*): This is also to be read as; There are many, many diagram-situations which are not intended to be solved by hidot.


Hidot format example:
---------------

file: common_types.hidot:

    // Define node-types
    node Interface {
        label="<Interface>";
        shape=diamond;
        fgcolor=#000000;
        bgcolor=#ffffff;
    }

    node Module {
        label="[Module]";
        shape=box;
        fgcolor=#000000;
        bgcolor=#ffffff;
    }

    // Define edge-/relationship-types
    edge implements {
        label="Implements";
        style=dashed;
        target_symbol=arrow_open;
    }

    edge depends_on; // rely on defaults

    edge relates_to {
        source_symbol=arrow_open;
        target_symbol=arrow_open;
    }

file: mygraph.hidot

    @common_node_types.hidot // imports the file as described above. Limitation: path can't contain newline
    label="My example diagram";

    // Declare the module-instances, optionally grouped
    IIterator: Interface;

    group Core {
        label="Core";

        MySomething: Module;
        MyElse: Module;
    }

    SomeDependency: Module {
        // An instantiation can override base-node fields
        bgcolor="#ffdddd";
    }

    // Describe relationships between modules
    MySomething implements IIterator;
    MySomething depends_on SomeDependency;
    MySomething relates_to MyElse {
        // A relationship can override base-edge fields
        target_symbol=arrow_filled;
    }


Result:

![Result of hidot to png compilation](examples/readme_example.hidot.png)

Hidot grammar
-----------
Types of statements:

* Declare a node-type:

        node NodeType;

        node OtherNodeType {
            label="Custom label";
            shape=diamond;
        }

* Declare an edge-type

        // will default to a simple, one-directional arrow when used in a relationship
        edge owns;

        // will render a two-way arrow when used in a relationship
        edge twowaydataflow {
            source_symbol=arrow_filled;
            target_symbol=arrow_filled;
        }

* Create a specific instance of a node

        myinstance: NodeType;

        otherinstance: OtherNodeType;

* Specify a relationship between two node-instanes using an edge

        myinstance owns otherinstance;

        otherinstance twowaydataflow {
            label="Overridden label for edge";
        }

For the different types there are a set of allowed parameters that can be specificed:

* For node or instance:
    * label: string
    * bgcolor: string/quoted #rrggbb, forwarded directly to dot.
    * fgcolor: see bgcolor.
    * shape: string, forwarded directly to dot: https://graphviz.org/doc/info/shapes.html
* for edge or relationship:
    * label: string
    * source_symbol: none|arrow_filled|arrow_closed|arrow_open. default: none
    * target_symbol: see source_symbol. default: arrow_open
    * edge_style: solid|dotted|dashed|bold. default: solid
* An instance automatically inherits the parameters of their node-type. The labels are concatinated with a newline, the remaining fields are overridden.
* If no lable is specified, the name is used
* The parameters of an edge can be overridden pr releationship-entry

Components
-----------

The system is split into the following components:
* Compiler library (/libhidot) - the core compiler, can be linked into e.g compiler exe, web service, and possibly in the end as WASM to make the web frontend standalone.
* Compiler executable (/compiler)
* Web service
* Web frontend

### Compiler

...

### Service / backend

Two parts:
1. An endpoint which takes hidot and returns dot, PNG or SVG.
1. Provider of the static frontend

### Frontend

Minimal, single-page, input-form to provide hidot data and desired output-format (dot, png, svg).


### Web component for easy inclusion into sites

...

TODO
---------
* Integrate dot / libdot
    * including libs for png and svg?
* Implement a semantic step to verify that the DIF makes sense
* .hidot
    * TBD: Implement more advanced (composed) shapes? E.g. an UML-like class with sections?
    * Implement import-functionality
    * Explicitly define behaviour wrt duplicate definitions; shall the latter be invalid behaviour, or shall they be fused? Either simply adding children, or explicitly checking for type and override values.
    * Support "comments"/"annotations": a post-it-like block with text tied to a particular instantiation or relationship.
    * Simplify syntax: allow } as EOS. Don't require quotes around #-colors.
* Finish v1 hidot-syntax: what is scope?
* Ensure compilator supports entire hidot-syntax
* Lower importance:
    * Implement web service
    * Implement frontend
* Nice-to-haves:
    * Accept a list of "instantiations" to only render whatever relates to them. Accept "degrees of separation" as well?
    * Support "playback"-functionality? Render node-by-node as they are instantiated, ordered by source?
    * Mode to allow anonymous types? E.g. don't require predefined nodes/edges, more simular to how dot behaves.


Attributions
============
* graphviz - hidot currently uses graphviz/dot as the low level graph tool
