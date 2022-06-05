Exploration: language / syntax
==============================

Need to determine which syntax the diagrams shall be authored with.
I propose supporting two dialects:
1) Common DOT
2) "Daya" - a higher level language which gets compiled to dot


Daya
-----
Features:
* Minimalistic, opinionated
* Consistent and elegant
* Intuitive / possible to read as text
* Limit waste (no redundant characters to express logics)
* Possible to create types to be used on nodes and edges
* Possible import files with e.g. types or even whole charts or sections thereof


Compiler thoughts
-----
It must be guaranteed that if the compiler passes, the resulting dot must also be compilable by dot.
I.e. the compiler shall only produce valid dot.