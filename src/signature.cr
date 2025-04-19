# Represents a fully typed definition signature
record Signature,
  name : String,
  return_type : Crystal::ASTNode?,
  location : Crystal::Location,
  args = {} of String => Crystal::ASTNode?
