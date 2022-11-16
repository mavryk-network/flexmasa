open Internal_pervasives

type t = {
  level : int;
  name : string;
  node : Tezos_executable.t;
  client : Tezos_executable.t;
}

module Account : sig
  type t = {
    name : string;
    operation_hash : string;
    address : string;
    origination_account : string;
    out : string list;
  }
  (** This module is used for creating the gas accounts and parsing the rollup
      account information. *)

  val fund :
    < application_name : string
    ; console : Console.t
    ; env_config : Environment_configuration.t
    ; paths : Paths.t
    ; runner : Running_processes.State.t
    ; .. > ->
    client:Tezos_client.t ->
    amount:string ->
    from:string ->
    destination:string ->
    ( < err : string list ; out : string list ; status : Unix.process_status >,
      [> `Process_error of Process_result.Error.error
      | `System_error of [ `Fatal ] * System_error.static ] )
    Asynchronous_result.t
  (** [fund state client amount sender recipient] is an octez-client call to
      transfer an [amount] form from [sender] to [recipient]. *)

  val fund_multiple :
    < application_name : string
    ; console : Console.t
    ; env_config : Environment_configuration.t
    ; paths : Paths.t
    ; runner : Running_processes.State.t
    ; .. > ->
    client:Tezos_client.t ->
    from:string ->
    recipients:(string * string) list ->
    ( < err : string list ; out : string list ; status : Unix.process_status >,
      [> `Process_error of Process_result.Error.error
      | `System_error of [ `Fatal ] * System_error.static ] )
    Asynchronous_result.t
  (** [fund_multiple state client sender recipients] is an octez-client call to
      transfer tez from [sender] to a list of [recipients]. Recipients is a
      (destination account, tezos amount) list. *)
end

module Tx_node : sig
  (** A type for the tx_rollup node mode.*)
  type mode = Observer | Accuser | Batcher | Maintenance | Operator | Custom

  (** A type for tx_rollup_node operation signers.*)
  type operation_signer =
    | Operator_signer of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Batch of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Finalize_commitment of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Remove_commitment of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Rejection of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Dispatch_withdrawal of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)

  type node = {
    id : string;
    port : int option;
    endpoint : int option;
    protocol : Tezos_protocol.Protocol_kind.t;
    exec : Tezos_executable.t;
    client : Tezos_client.t;
    mode : mode;
    cors_origin : string option;
    account : Account.t;
    operation_signers : operation_signer list;
    tx_rollup : t;
  }
  (** A type for the tx_rollup_node configuration.*)

  val operation_signers :
    client:Tezos_client.t ->
    id:string ->
    operator:string ->
    batch:string ->
    ?finalize:string ->
    ?remove:string ->
    ?rejection:string ->
    ?dispatch:string ->
    unit ->
    operation_signer list
  (** [signers] is a list of operation signers for rollup operations. *)

  val operation_signer_map :
    operation_signer ->
    f:(Tezos_protocol.Account.t * Tezos_client.Keyed.t -> 'a) ->
    'a
  (** [operation_signer_map f signer] applies [f] to [signer]*)

  val make :
    ?id:string ->
    ?port:int ->
    ?endpoint:int ->
    protocol:Tezos_protocol.Protocol_kind.t ->
    exec:Tezos_executable.t ->
    client:Tezos_client.t ->
    mode:mode ->
    ?cors_origin:string ->
    account:Account.t ->
    ?operation_signers:operation_signer list ->
    tx_rollup:t ->
    unit ->
    node

  val start_script :
    < env_config : Environment_configuration.t ; paths : Paths.t ; .. > ->
    node ->
    unit Genspio.Language.t
  (** [start script node] runs the tx_rollup_node commands init and run
      according to [node]. *)

  val process :
    'a ->
    node ->
    ('a -> node -> 'b Genspio.Language.t) ->
    Running_processes.Process.t

  val cmdliner_term :
    < manpager : Manpage_builder.State.t ; .. > -> unit -> mode Cmdliner.Term.t
  (** A cmdliner term for the tx_rollup_node "mode" option. *)
end

val origination_account :
  client:Tezos_client.t ->
  string ->
  Tezos_protocol.Account.t * Tezos_client.Keyed.t

val originate_and_confirm :
  < application_name : string
  ; console : Console.t
  ; env_config : Environment_configuration.t
  ; paths : Paths.t
  ; runner : Running_processes.State.t
  ; .. > ->
  name:string ->
  client:Tezos_client.t ->
  account:string ->
  ?confirmations:int ->
  unit ->
  ( Account.t * string list,
    [> `Process_error of Process_result.Error.error
    | `System_error of [ `Fatal ] * System_error.static ] )
  Asynchronous_result.t
(** [originate_and_confirm state name client acc] is an octez-client call to
    originate a transaction rollup called [name]. [acc] is the gas account. *)

val publish_deposit_contract :
  < application_name : string
  ; console : Console.t
  ; env_config : Environment_configuration.t
  ; paths : Paths.t
  ; runner : Running_processes.State.t
  ; .. > ->
  Tezos_protocol.Protocol_kind.t ->
  string ->
  Tezos_client.t ->
  string ->
  ( string,
    [> `Process_error of Process_result.Error.error
    | `System_error of [ `Fatal ] * System_error.static ] )
  Asynchronous_result.t

val executables : t -> Tezos_executable.t list

val cmdliner_term :
  < manpager : Manpage_builder.State.t ; .. > ->
  docs:string ->
  unit ->
  t option Cmdliner.Term.t
(** A cmdliner term for the tx_rollup option. *)
