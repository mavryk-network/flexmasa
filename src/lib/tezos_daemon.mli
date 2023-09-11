type args = private
  | Baker : string -> args
  | Endorser : string -> args
  | Accuser : args

type ai_vote = [ `On | `Off | `Pass ]

type t = private {
  node : Tezos_node.t;
  client : Tezos_client.t;
  exec : Tezos_executable.t;
  protocol_kind : Tezos_protocol.Protocol_kind.t;
  args : args;
  name_tag : string option;
  adaptive_issuance : ai_vote;
}

val of_node :
  ?adaptive_issuance:ai_vote ->
  ?name_tag:string ->
  Tezos_node.t ->
  args ->
  protocol_kind:Tezos_protocol.Protocol_kind.t ->
  exec:Tezos_executable.t ->
  client:Tezos_client.t ->
  t

val baker_of_node :
  ?name_tag:string ->
  Tezos_node.t ->
  key:string ->
  adaptive_issuance:ai_vote ->
  protocol_kind:Tezos_protocol.Protocol_kind.t ->
  exec:Tezos_executable.t ->
  client:Tezos_client.t ->
  t

val endorser_of_node :
  ?name_tag:string ->
  Tezos_node.t ->
  key:string ->
  protocol_kind:Tezos_protocol.Protocol_kind.t ->
  exec:Tezos_executable.t ->
  client:Tezos_client.t ->
  t

val accuser_of_node :
  ?name_tag:string ->
  Tezos_node.t ->
  protocol_kind:Tezos_protocol.Protocol_kind.t ->
  exec:Tezos_executable.t ->
  client:Tezos_client.t ->
  t

val arg_to_string : args -> string

val process :
  < env_config : Environment_configuration.t ; paths : Paths.t ; .. > ->
  t ->
  Running_processes.Process.t
