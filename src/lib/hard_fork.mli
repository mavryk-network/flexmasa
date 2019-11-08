open Internal_pervasives

type t =
  { level: int
  ; protocol_hash: string
  ; name: string
  ; baker: Tezos_executable.t
  ; endorser: Tezos_executable.t
  ; accuser: Tezos_executable.t }

val cmdliner_term :
     < manpager: Manpage_builder.State.t ; .. >
  -> docs:string
  -> ?prefix:string
  -> unit
  -> t option Cmdliner.Term.t

val executables : t -> Tezos_executable.t list
val node_network_config : t -> string * [> Ezjsonm.t]

val keyed_daemons :
     t
  -> client:Tezos_client.t
  -> key:string
  -> node:Tezos_node.t
  -> Tezos_daemon.t list
