open Internal_pervasives

module Account : sig
  type t =
    { name: string
    ; operation_hash: string
    ; address: string
    ; origination_account: string
    ; out: string list }

  val fund :
       < application_name: string
       ; console: Console.t
       ; env_config: Environment_configuration.t
       ; paths: Paths.t
       ; runner: Running_processes.State.t
       ; .. >
    -> client:Tezos_client.t
    -> amount:string
    -> from:string
    -> dst:string
    -> ( < err: string list ; out: string list ; status: Unix.process_status >
       , [> `Process_error of Process_result.Error.error
         | `System_error of [`Fatal] * System_error.static ] )
       Asynchronous_result.t
  (** [fund state client tez acc dst] is a client call to send [amount] of tez form from [acc] to [dist]. *)

  val fund_multiple :
       < application_name: string
       ; console: Console.t
       ; env_config: Environment_configuration.t
       ; paths: Paths.t
       ; runner: Running_processes.State.t
       ; .. >
    -> client:Tezos_client.t
    -> from:string
    -> recipiants:(string * string) list
    -> ( < err: string list ; out: string list ; status: Unix.process_status >
       , [> `Process_error of Process_result.Error.error
         | `System_error of [`Fatal] * System_error.static ] )
       Asynchronous_result.t
  (** [fund_multiple state client from recipiants] is a client call to transfer tez form from [from] to a
      list of [recipants]. Recipaints is a (destination account, tezos amount) list. *)
end

module Tx_node : sig
  type mode = Observer | Accuser | Batcher | Maintenance | Operator | Custom

  type operation_signer =
    | Operator of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Batch of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Finalize_commitment of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Remove_commitment of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Rejection of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Dispatch_withdrawal of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)

  type t =
    { id: string
    ; port: int option
    ; endpoint: int option
    ; protocol: Tezos_protocol.Protocol_kind.t
    ; exec: Tezos_executable.t
    ; client: Tezos_client.t
    ; mode: mode
    ; cors_origin: string option
    ; account: Account.t
    ; operation_signers: operation_signer list }

  val operation_signers :
       client:Tezos_client.t
    -> id:string
    -> operator:string
    -> batch:string
    -> ?finalize:string
    -> ?remove:string
    -> ?rejection:string
    -> ?dispatch:string
    -> unit
    -> operation_signer list
  (** [signers] is a list of operation signers for rollup operations. *)

  val operation_signer_map :
       operation_signer
    -> f:(Tezos_protocol.Account.t * Tezos_client.Keyed.t -> 'a)
    -> 'a
  (** [operation_signer_map f signer] applies [f] to [signer]*)

  val rpc_port : int ref
  val next_port : int ref -> Tezos_node.t list -> int ref

  val make :
       ?id:string
    -> ?port:int
    -> ?endpoint:int
    -> protocol:Tezos_protocol.Protocol_kind.t
    -> exec:Tezos_executable.t
    -> client:Tezos_client.t
    -> mode:mode
    -> ?cors_origin:string
    -> account:Account.t
    -> ?operation_signers:operation_signer list
    -> unit
    -> t

  val start_script :
       < env_config: Environment_configuration.t ; paths: Paths.t ; .. >
    -> t
    -> unit Genspio.Language.t
  (** [start script] runs the tx_rollup_node commands init and run accourning to [t]. *)

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

val origination_account :
     client:Tezos_client.t
  -> string
  -> Tezos_protocol.Account.t * Tezos_client.Keyed.t

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
  -> ( Account.t * string list
     , [> `Process_error of Process_result.Error.error
       | `System_error of [`Fatal] * System_error.static ] )
     Asynchronous_result.t
(** [originate_and_confirm state name client acc] is a tezo-client [client] call to
      originate a transactional rollup called [name]. [acc] is the gas account. *)

val publish_deposit_contract :
     < application_name: string
     ; console: Console.t
     ; env_config: Environment_configuration.t
     ; paths: Paths.t
     ; runner: Running_processes.State.t
     ; .. >
  -> string
  -> Tezos_client.t
  -> string
  -> ( string
     , [> `Process_error of Process_result.Error.error
       | `System_error of [`Fatal] * System_error.static ] )
     Asynchronous_result.t

val executables : t -> Tezos_executable.t list

val cmdliner_term :
     < manpager: Manpage_builder.State.t ; .. >
  -> docs:string
  -> unit
  -> t option Cmdliner.Term.t
(** A cmdliner term for the tx_rollup option. *)
