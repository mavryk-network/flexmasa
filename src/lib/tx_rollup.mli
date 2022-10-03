open Internal_pervasives

module Account : sig
  type t =
    {name: string; operation_hash: string; address: string; out: string list}

  val originate_and_confirm :
       < application_name: string
       ; console: Console.t
       ; env_config: Environment_configuration.t
       ; paths: Paths.t
       ; runner: Running_processes.State.t
       ; .. >
    -> name:string
    -> client:Tezos_client.t
    -> acc:string
    -> ?confirmations:int
    -> unit
    -> ( t * string list
       , [> `Process_error of Process_result.Error.error
         | `System_error of [`Fatal] * System_error.static ] )
       Asynchronous_result.t
  (** [originate_and_confirm state name client acc] is a call to tezo-client [client] call to
      originate transactional rollup [name]. [acc] is the gass account. *)
end

module Tx_node : sig
  type mode = Observer | Accuser | Batcher | Maintenance | Operator | Custom

  type t =
    { id: string
    ; port: int option
    ; endpoint: int
    ; protocol: Tezos_protocol.Protocol_kind.t
    ; exec: Tezos_executable.t
    ; client: Tezos_client.t
    ; mode: mode
    ; cors_origin: string option
    ; account: Account.t
    ; operation_signers: string list }

  val signers :
       operator:string
    -> batcher:string
    -> ?finalize_commitment:string
    -> ?remove_commitment:string
    -> ?rejection:string
    -> ?dispatch_withdrawals:string
    -> unit
    -> string list
  (** [signers] is a list of operation signers for the specific rollup operations. *)

  val make :
       ?id:string
    -> ?port:int
    -> endpoint:int
    -> protocol:Tezos_protocol.Protocol_kind.t
    -> exec:Tezos_executable.t
    -> client:Tezos_client.t
    -> mode:mode
    -> ?cors_origin:string
    -> account:Account.t
    -> operation_signers:string list
    -> unit
    -> t
  (** [make] is a type for builing a tx_rollup_node command. *)

  val start_script :
       < env_config: Environment_configuration.t ; paths: Paths.t ; .. >
    -> t
    -> unit Genspio.Language.t
  (** [start script] runs the tx_rollup_node commans init and run accourning to [t]. *)

  val process :
    'a -> t -> ('a -> t -> 'b Genspio.Language.t) -> Running_processes.Process.t

  val cmdliner_term :
       < manpager: Manpage_builder.State.t ; .. >
    -> extra_doc:string
    -> mode Cmdliner.Term.t
  (** A cmdliner term for the tx_rollup_node "mode" option. *)
end

type t =
  { level: int
  ; name: string
  ; node: Tezos_executable.t
  ; client: Tezos_executable.t
  ; mode: Tx_node.mode }

val executables : t -> Tezos_executable.t list
(** List of executables for the Transactional Rollup *)

val cmdliner_term :
     < manpager: Manpage_builder.State.t ; .. >
  -> docs:string
  -> unit
  -> t option Cmdliner.Term.t
(** List of executables for the Transactional Rollup *)
