// catalog-api deliberately has ZERO external dependencies: stdlib net/http
// only. The in-container build therefore needs no module downloads.
module ems.example/catalog

go 1.24
