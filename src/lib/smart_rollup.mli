open Internal_pervasives

type t = {
  id : string;
  level : int;
  kernel : [ `Tx | `Evm | `Custom of string * string * string ];
  setup_file : string option;
  node_mode : [ `Accuser | `Batcher | `Maintenance | `Observer | `Operator ];
  node_init_options : string list;
  node_run_options : string list;
  node : Mavryk_executable.t;
  installer : Mavryk_executable.t;
  evm_node : Mavryk_executable.t;
}

val executables : t -> Mavryk_executable.t list

(* Originate a smart rollup with the kernel passed from the command line or the
   default tx-rollup *)
val run :
  < application_name : string
  ; console : Console.t
  ; env_config : Environment_configuration.t
  ; paths : Paths.t
  ; runner : Running_processes.State.t
  ; .. > ->
  smart_rollup:t option ->
  protocol:Mavryk_protocol.t ->
  keys_and_daemons:
    (Mavryk_node.t
    * Mavryk_protocol.Account.t
    * Mavryk_client.t
    * Mavryk_client.Keyed.t
    * Mavryk_daemon.t list)
    list ->
  nodes:Mavryk_node.t list ->
  base_port:int ->
  ( unit,
    [> `Process_error of Process_result.Error.error
    | `System_error of [ `Fatal ] * System_error.static ] )
  Asynchronous_result.t

val cmdliner_term :
  < manpager : Manpage_builder.State.t ; .. > ->
  unit ->
  t option Cmdliner.Term.t
