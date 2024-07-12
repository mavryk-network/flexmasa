open Internal_pervasives

(** User-activated Upgrades, a.k.a. Hard Forks *)

(** This module provides helpers to make “hard-fork” protocol changes happen in
    sandboxes.

    See ["src/lib/interactive_mini_network.ml"] for an example of usage. *)

type t = private {
  level : int;
  protocol_kind : Mavryk_protocol.Protocol_kind.t;
  protocol_hash : string;
  name : string;
  baker : Mavryk_executable.t;
  endorser : Mavryk_executable.t;
  accuser : Mavryk_executable.t;
}

val cmdliner_term :
  < manpager : Manpage_builder.State.t ; .. > ->
  docs:string ->
  ?prefix:string ->
  unit ->
  t option Cmdliner.Term.t
(** For a given [prefix] (default ["hard-fork"]), provide a family of
    ["--<prefix>*"] command-line options allowing to configure a
    user-activated-upgrade. *)

val executables : t -> Mavryk_executable.t list
(** Get all the protocol-specific executable definitions (the “daemons”)
    involved in this hard-fork. *)

val node_network_config : t -> string * [> Ezjsonm.t ]
(** Generate the JSON field for the ["{ network : { ... } }"] part of a node's
    configuration file. *)

val keyed_daemons :
  t ->
  client:Mavryk_client.t ->
  key:string ->
  node:Mavryk_node.t ->
  adaptive_issuance:Mavryk_daemon.ai_vote ->
  Mavryk_daemon.t list
(** Prepare the baker and endorse daemons to secure the hard-fork. *)
