Exploration: language / syntax
==============================

Need to determine which syntax the diagrams shall be authored with.
I propose supporting two dialects:
1) Common DOT
2) "HiDot" - a higher level language which gets compiled to dot


HiDot
-----
Features:
* Minimalistic
* Consistent and elegant
* Intuitive / possible to read as text
* No waste (no redundant characters to express logics)
* Possible to create types to be used on nodes and edges
* Possible import types


Compiler thoughts
-----
It must be guaranteed that if the compiler passes, the resulting dot must also be compilable by dot.
I.e. the compiler shall only produce valid dot.