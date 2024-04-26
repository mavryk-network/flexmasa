open Internal_pervasives

type t = {
  level : int;
  protocol_kind : Mavryk_protocol.Protocol_kind.t;
  protocol_hash : string;
  name : string;
  baker : Mavryk_executable.t;
  endorser : Mavryk_executable.t;
  accuser : Mavryk_executable.t;
}

let cmdliner_term base_state ~docs ?(prefix = "hard-fork") () =
  let open Cmdliner in
  let open Cmdliner.Term in
  let extra_doc = Fmt.str " for the hard-fork (requires --%s)" prefix in
  pure (fun hard_fork baker endorser accuser ->
      Option.map hard_fork ~f:(fun (level, protocol_kind, protocol_hash_opt) ->
          let protocol_hash =
            match protocol_hash_opt with
            | None | Some "" ->
                Mavryk_protocol.Protocol_kind.canonical_hash protocol_kind
            | Some s -> s
          in
          {
            level;
            name = prefix;
            protocol_kind;
            protocol_hash;
            baker;
            endorser;
            accuser;
          }))
  $ Arg.(
      value
        (opt
           (some
              (t3 ~sep:':' int
                 (enum Mavryk_protocol.Protocol_kind.names)
                 (some string)))
           None
           (info [ prefix ]
              ~doc:
                "Make a hard-fork happen (PROTOCOL-HASH is optional, the \
                 default is the canonical one for the given protocol-kind)."
              ~docs ~docv:"LEVEL:PROTOCOL-KIND:[PROTOCOL-HASH]")))
  $ Mavryk_executable.cli_term ~extra_doc base_state `Baker ~prefix
  $ Mavryk_executable.cli_term ~extra_doc base_state `Endorser ~prefix
  $ Mavryk_executable.cli_term ~extra_doc base_state `Accuser ~prefix
  [@@warning "-3"]

let executables { protocol_kind; baker; endorser; accuser; _ } =
  if Mavryk_protocol.Protocol_kind.wants_endorser_daemon protocol_kind then
    [ baker; endorser; accuser ]
  else [ baker; accuser ]

let node_network_config t =
  let open Ezjsonm in
  ( "user_activated_upgrades",
    list Fn.id
      [
        dict
          [
            ("level", int t.level);
            ("replacement_protocol", string t.protocol_hash);
          ];
      ] )

let keyed_daemons t ~client ~key ~node ~adaptive_issuance =
  let protocol_kind = t.protocol_kind in
  [
    Mavryk_daemon.baker_of_node ~name_tag:t.name ~exec:t.baker ~client node ~key
      ~adaptive_issuance ~protocol_kind;
    Mavryk_daemon.endorser_of_node ~name_tag:t.name ~exec:t.endorser ~client
      ~protocol_kind node ~key;
  ]
