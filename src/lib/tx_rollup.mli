open Internal_pervasives

type t = {
  level : int;
  name : string;
  node_mode :
    [ `Observer | `Accuser | `Batcher | `Maintenance | `Operator | `Custom ];
  node : Tezos_executable.t;
  client : Tezos_executable.t;
}

val executables : t -> Tezos_executable.t list

val run :
  < application_name : string
  ; console : Console.t
  ; env_config : Environment_configuration.t
  ; paths : Paths.t
  ; runner : Running_processes.State.t
  ; .. > ->
  protocol:Tezos_protocol.t ->
  tx_rollup:t option ->
  keys_and_daemons:
    ('a * Tezos_protocol.Account.t * Tezos_client.t * 'b * 'c) list ->
  nodes:Tezos_node.t list ->
  base_port:int ->
  ( unit,
    [> `Process_error of Process_result.Error.error
    | `System_error of [ `Fatal ] * System_error.static
    | `Waiting_for of string * [ `Time_out ] ] )
  Attached_result.t
  Lwt.t
(** [run state protocol tx_rollup keys_and_daemons nodes base_port] runs the
    tx_rollup sandbox *)

val cmdliner_term :
  < manpager : Manpage_builder.State.t ; .. > ->
  unit ->
  t option Cmdliner.Term.t
