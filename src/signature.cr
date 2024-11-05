# Represents a fully typed definition signature
record Signature,
  name : String,
  return_type : Crystal::ASTNode,
  location : Crystal::Location,
  # TODO
  block_arg : String? = nil,
  args = {} of String => Crystal::ASTNode
