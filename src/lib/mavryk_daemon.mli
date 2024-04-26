type args = private
  | Baker : string -> args
  | Endorser : string -> args
  | Accuser : args

type ai_vote = [ `On | `Off | `Pass ]

type t = private {
  node : Mavryk_node.t;
  client : Mavryk_client.t;
  exec : Mavryk_executable.t;
  protocol_kind : Mavryk_protocol.Protocol_kind.t;
  args : args;
  name_tag : string option;
  adaptive_issuance : ai_vote;
}

val of_node :
  ?adaptive_issuance:ai_vote ->
  ?name_tag:string ->
  Mavryk_node.t ->
  args ->
  protocol_kind:Mavryk_protocol.Protocol_kind.t ->
  exec:Mavryk_executable.t ->
  client:Mavryk_client.t ->
  t

val baker_of_node :
  ?name_tag:string ->
  Mavryk_node.t ->
  key:string ->
  adaptive_issuance:ai_vote ->
  protocol_kind:Mavryk_protocol.Protocol_kind.t ->
  exec:Mavryk_executable.t ->
  client:Mavryk_client.t ->
  t

val endorser_of_node :
  ?name_tag:string ->
  Mavryk_node.t ->
  key:string ->
  protocol_kind:Mavryk_protocol.Protocol_kind.t ->
  exec:Mavryk_executable.t ->
  client:Mavryk_client.t ->
  t

val accuser_of_node :
  ?name_tag:string ->
  Mavryk_node.t ->
  protocol_kind:Mavryk_protocol.Protocol_kind.t ->
  exec:Mavryk_executable.t ->
  client:Mavryk_client.t ->
  t

val arg_to_string : args -> string

val process :
  < env_config : Environment_configuration.t ; paths : Paths.t ; .. > ->
  t ->
  Running_processes.Process.t
