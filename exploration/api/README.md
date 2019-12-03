Endpoints
---------
Base endpoint: https://blah.io/api/v1

Endpoints:
"Stateless":
* POST /compile  returns result, or compilation errors. Format of result (png, svg, dot...) determine on request

Persistent:
* GET /diagram/:id.(png|svg|dot|hidot)  get diagram, in desired format
* PUT /diagram/:id  overwrite the diagram with new data to compile
* DELETE /diagram/:id
