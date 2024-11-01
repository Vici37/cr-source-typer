# Represents a fully typed definition signature
record Signature,
  name : String,
  def_object_id : UInt64,
  return_type : Crystal::ASTNode,
  location : Crystal::Location,
  # TODO
  block_arg : String? = nil,
  args = {} of String => Crystal::ASTNode
