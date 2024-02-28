open Internal_pervasives
open Console

(** A.k.a the [chain_id] *)
module Genesis_block_hash = struct
  let path state = Paths.root state // "genesis.json"

  let to_json _state genesis =
    Ezjsonm.dict [ ("genesis-block-hash", `String genesis) ]

  (** See implementation of {!Tezos_node}, this corresponds to the Chain-id
      ["NetXKMbjQL2SBox"] *)
  let default = "BLdZYwNF8Rn6zrTWkuRRNyrj6bQWPkfBog2YKhWhn5z3ApmpzBf"

  let of_protocol_kind : Tezos_protocol.Protocol_kind.t -> string =
    (*
      $ flextesa van --first --seed atlasbox- --attempts 100_000_000  Box1
     Flextesa.vanity-chain-id:  Looking for "Box1"
     Flextesa.vanity-chain-id:
       Results:
         * Seed: "atlasbox-402009"
           → block: "BMWbP36nAMgD7LT4aT8LXXiAzMyzNSBeS1R9Tpz1N6RrNPSPepQ"
           → chain-id: "NetXSq4NpQeBox1"
     $ ./flextesa van --first --seed alphabox- --attempts 100_000_000  BoxA
     Flextesa.vanity-chain-id:  Looking for "BoxA"
     Flextesa.vanity-chain-id:
       Results:
         * Seed: "alphabox-31164447"
           → block: "BKzFLDivozSLzqkZsRMpovuiiT53LzaJQP78ZujEXhmwCrb3qMi"
           → chain-id: "NetXmGq7LPFBoxA"
    *)
    function
    | `Atlas -> "BMWbP36nAMgD7LT4aT8LXXiAzMyzNSBeS1R9Tpz1N6RrNPSPepQ"
    | `Alpha -> "BKzFLDivozSLzqkZsRMpovuiiT53LzaJQP78ZujEXhmwCrb3qMi"

  module Choice = struct
    type t = [ `Random | `Force of string | `Old_default | `From_protocol_kind ]

    let pp : t Fmt.t =
     fun ppf ->
      let open Fmt in
      function
      | `Random -> pf ppf "Random"
      | `Old_default -> pf ppf "Old-Default:%s" default
      | `Force v -> pf ppf "Forced:%s" v
      | `From_protocol_kind -> pf ppf "From-protocol-kind"

    let pp_short : t Fmt.t =
     fun ppf ->
      let open Fmt in
      function
      | `Random -> pf ppf "Random"
      | `Old_default -> pf ppf "Old-default"
      | `Force _ -> pf ppf "Forced"
      | `From_protocol_kind -> pf ppf "From-protocol-kind"

    let cmdliner_term () : t Cmdliner.Term.t =
      let open Cmdliner in
      let open Term in
      ret
        (pure (function
           | None | Some "from-protocol-kind" | Some "default" ->
               `Ok `From_protocol_kind
           | Some "legacy-default" -> `Ok `Old_default
           | Some "random" -> `Ok `Random
           | Some force -> `Ok (`Force force))
        $ Arg.(
            let doc =
              Fmt.str
                {md|Set the genesis block hash (from which the chain-id is derived).
The default behavior (or the values "default" or "from-protocol-kind") is to pick
a "vanity-suffix-chain-id" which depends on the kind of protocol:
`Box6` for Carthage
and `Box7` for Delphi.
The value "random" means to pick a random number.
The value "legacy-default" picks the same default as older versions of Flextesa.
Any other value is treated as a custom block hash.
This option is ignored when the `--keep-root` option allows
the chain to resume
(the previously chosen genesis-hash will be still in effect).
|md}
            in
            value
              (opt (some string) None
                 (info [ "genesis-block-hash" ]
                    ~docv:"BLOCK-HASH|<special-value>" ~doc))))
      [@@warning "-3"]
  end

  let chain_id_of_hash hash =
    let open Mavai_base58_digest.Identifier in
    Chain_id.of_base58_block_hash hash

  let process_choice state ~protocol_kind choice =
    let json_file = path state in
    let pp_hash_fancily ppf h =
      let open More_fmt in
      pf ppf "`%s` (corresponding chain-id: `%s`)" h (chain_id_of_hash h)
    in
    match Stdlib.Sys.file_exists json_file with
    | true ->
        System.read_file state json_file >>= fun json_str ->
        System_error.catch_exn
          ~attach:[ ("json-content", `Verbatim [ json_str ]) ]
          (fun () ->
            match Ezjsonm.value_from_string json_str with
            | `O [ ("genesis-block-hash", `String hash) ] -> hash
            | _ ->
                Fmt.failwith "invalid json for genesis-block-hash: %S" json_str)
        >>= fun hash ->
        Console.sayf state
          More_fmt.(
            fun ppf () ->
              wf ppf "Genesis-block-hash already set: %a%a" pp_hash_fancily hash
                (fun ppf -> function
                  | `From_protocol_kind -> pf ppf "."
                  | choice ->
                      pf ppf " (user choice “%a” is then ignored)." Choice.pp
                        choice)
                choice)
        >>= fun () -> return hash
    | false ->
        let hash =
          match choice with
          | `Old_default -> default
          | `Force v -> v
          | `From_protocol_kind -> of_protocol_kind protocol_kind
          | `Random ->
              let seed =
                Fmt.str "%d:%f" (Random.int 1_000_000) (Unix.gettimeofday ())
              in
              let open Mavai_base58_digest.Identifier in
              let block_hash = Block_hash.hash_string seed in
              Block_hash.encode block_hash
        in
        Console.sayf state
          More_fmt.(
            fun ppf () ->
              wf ppf
                "Genesis-block-hash not set, using: %a (from user choice: \
                 “%a”)."
                pp_hash_fancily hash Choice.pp_short choice)
        >>= fun () ->
        Running_processes.run_successful_cmdf state "mkdir -p %s"
          Stdlib.Filename.(dirname json_file |> quote)
        >>= fun _ ->
        System.write_file state json_file
          ~content:(to_json state hash |> Ezjsonm.value_to_string)
        >>= fun () -> return hash
end

let run_dsl_cmd state clients nodes dsl_command =
  let parsed_cmd = Parsexp.Single.parse_string (sprintf "( %s )" dsl_command) in
  match parsed_cmd with
  | Error err ->
      fail
        (`Msg
          ("Error: Parsing dsl command produced an error: "
          ^ Parsexp.Parse_error.message err
          ^ "for input string: " ^ dsl_command))
  | Ok sexp ->
      return sexp >>= fun dsl_sexp ->
      Traffic_generation.Dsl.run state ~nodes ~clients dsl_sexp

let run state ~protocol ~size ~base_port ~clear_root ~no_daemons_for ?hard_fork
    ~genesis_block_choice ?external_peer_ports ~nodes_history_mode_edits
    node_exec client_exec baker_exec endorser_exec accuser_exec test_kind
    ?smart_rollup ~smart_contracts ~adaptive_issuance () =
  (if clear_root then
   Console.say state EF.(wf "Clearing root: `%s`" (Paths.root state))
   >>= fun () -> Helpers.clear_root state
  else Console.say state EF.(wf "Keeping root: `%s`" (Paths.root state)))
  >>= fun () ->
  Genesis_block_hash.process_choice state
    ~protocol_kind:protocol.Tezos_protocol.kind genesis_block_choice
  >>= fun genesis_block_hash ->
  Helpers.System_dependencies.precheck state `Or_fail
    ~protocol_kind:protocol.kind
    ~executables:
      ([ node_exec; client_exec ]
      @ (if state#test_baking then
         if
           Tezos_protocol.Protocol_kind.wants_endorser_daemon
             protocol.Tezos_protocol.kind
         then [ baker_exec; endorser_exec; accuser_exec ]
         else [ baker_exec; accuser_exec ]
        else [])
      @ Option.value_map hard_fork ~default:[] ~f:Hard_fork.executables
      @ Option.value_map smart_rollup ~default:[] ~f:Smart_rollup.executables)
  >>= fun () ->
  Console.say state EF.(wf "Starting up the network.") >>= fun () ->
  let node_custom_network =
    let base =
      Tezos_node.Config_file.network ~genesis_hash:genesis_block_hash ()
    in
    `Json
      (Ezjsonm.dict
         (base
         @ Option.value_map ~default:[] hard_fork ~f:(fun hf ->
               [ Hard_fork.node_network_config hf ])))
  in
  Test_scenario.network_with_protocol ?external_peer_ports ~protocol ~size
    ~do_activation:clear_root ~nodes_history_mode_edits ~base_port state
    ~node_exec ~client_exec ~node_custom_network
  >>= fun (nodes, protocol) ->
  Console.say state EF.(wf "Network started, preparing scenario.") >>= fun () ->
  let to_keyed acc client =
    let key, priv = Tezos_protocol.Account.(name acc, private_key acc) in
    let keyed_client =
      Tezos_client.Keyed.make client ~key_name:key ~secret_key:priv
    in
    keyed_client
  in
  let keys_and_daemons =
    let pick_a_node_and_client idx =
      match List.nth nodes (Int.rem (1 + idx) (List.length nodes)) with
      | Some node -> (node, Tezos_client.of_node node ~exec:client_exec)
      | None -> assert false
    in
    Tezos_protocol.bootstrap_accounts protocol
    |> List.filter_mapi ~f:(fun idx acc ->
           let node, client = pick_a_node_and_client idx in
           let key = Tezos_protocol.Account.name acc in
           if List.mem ~equal:String.equal no_daemons_for key then None
           else
             Some
               ( node,
                 acc,
                 client,
                 to_keyed acc client,
                 Option.value_map hard_fork ~default:[]
                   ~f:
                     (Hard_fork.keyed_daemons ~client ~node ~key
                        ~adaptive_issuance)
                 @ [
                     Tezos_daemon.baker_of_node ~exec:baker_exec ~client node
                       ~key ~adaptive_issuance ~protocol_kind:protocol.kind;
                     Tezos_daemon.endorser_of_node ~exec:endorser_exec ~client
                       ~protocol_kind:protocol.kind node ~key;
                   ] ))
  in
  List_sequential.iter keys_and_daemons ~f:(fun (_, _, _, kc, _) ->
      Tezos_client.Keyed.initialize state kc >>= fun _ -> return ())
  >>= fun () ->
  Interactive_test.Pauser.add_commands state
    Interactive_test.Commands.
      [
        generate_traffic_command state
          ~clients:(List.map keys_and_daemons ~f:(fun (_, _, _, kc, _) -> kc))
          ~nodes;
      ];
  (if state#test_baking then
   let accusers =
     List.map nodes ~f:(fun node ->
         let client = Tezos_client.of_node node ~exec:client_exec in
         Tezos_daemon.accuser_of_node ~exec:accuser_exec
           ~protocol_kind:protocol.kind ~client node)
   in
   List_sequential.iter accusers ~f:(fun acc ->
       Running_processes.start state (Tezos_daemon.process state acc)
       >>= fun { process = _; lwt = _ } -> return ())
   >>= fun () ->
   List_sequential.iter keys_and_daemons
     ~f:(fun (_node, _acc, client, kc, daemons) ->
       Tezos_client.wait_for_node_bootstrap state client >>= fun () ->
       let key_name = kc.Tezos_client.Keyed.key_name in
       say state
         EF.(
           desc_list
             (haf "Registration-as-delegate:")
             [
               desc (af "Client:") (af "%S" client.Tezos_client.id);
               desc (af "Key:") (af "%S" key_name);
             ])
       >>= fun () ->
       Tezos_client.register_as_delegate state client ~key_name >>= fun () ->
       say state
         EF.(
           desc_list (haf "Starting daemons:")
             [
               desc (af "Client:") (af "%S" client.Tezos_client.id);
               desc (af "Key:") (af "%S" key_name);
             ])
       >>= fun () ->
       List_sequential.iter daemons ~f:(fun daemon ->
           Running_processes.start state (Tezos_daemon.process state daemon)
           >>= fun { process = _; lwt = _ } -> return ()))
  else
    List.fold ~init:(return []) keys_and_daemons
      ~f:(fun prev_m (_node, _acc, client, keyed, _) ->
        prev_m >>= fun prev ->
        Tezos_client.wait_for_node_bootstrap state client >>= fun () ->
        return (keyed :: prev))
    >>= fun clients ->
    Interactive_test.Pauser.add_commands state
      Interactive_test.Commands.[ bake_command state ~clients ];
    return ())
  >>= fun () ->
  Console.say state
    EF.(
      wf "initiailizing history file: `%s`"
        (Traffic_generation.Commands.history_file_path state))
  >>= fun () ->
  Traffic_generation.Commands.init_cmd_history state
  (* clear the command history file *)
  >>= fun () ->
  Smart_rollup.run state ~smart_rollup ~protocol ~keys_and_daemons ~nodes
    ~base_port
  >>= fun () ->
  Smart_contract.run state ~smart_contracts ~keys_and_daemons >>= fun () ->
  let clients = List.map keys_and_daemons ~f:(fun (_, _, c, _, _) -> c) in
  Helpers.Shell_environement.(
    let path = Paths.root state // "shell.env" in
    let env = build state ~protocol ~clients in
    write state env ~path >>= fun () -> return (help_command state env ~path))
  >>= fun shell_env_help ->
  let keyed_clients =
    List.map keys_and_daemons ~f:(fun (_, _, _, kc, _) -> kc)
  in
  Interactive_test.Pauser.add_commands state
    Interactive_test.Commands.(
      (shell_env_help :: all_defaults state ~nodes)
      @ [
          secret_keys state ~protocol;
          forge_and_inject_piece_of_json state ~clients:keyed_clients;
        ]
      @ arbitrary_commands_for_each_and_all_clients state ~clients);
  Test_scenario.Queries.(
    match test_kind with
    | `Interactive ->
        Interactive_test.Pauser.generic state ~force:true
          EF.[ haf "Sandbox is READY \\o/" ]
    | `Dsl_traffic (`Dsl_command dsl_command, `After `Interactive) ->
        run_dsl_cmd state keyed_clients nodes dsl_command >>= fun () ->
        Interactive_test.Pauser.generic state ~force:true
          EF.[ haf "Sandbox is READY \\o/" ]
    | `Dsl_traffic (`Dsl_command dsl_command, `After (`Until lvl)) ->
        run_dsl_cmd state keyed_clients nodes dsl_command >>= fun () ->
        let opt = `At_least lvl in
        run_wait_level protocol state nodes opt lvl
    | `Random_traffic (`Any, `Until level) ->
        System.sleep 10. >>= fun () ->
        Traffic_generation.Random.run state ~protocol ~nodes
          ~clients:keyed_clients ~until_level:level `Any
    | `Wait_level (`At_least lvl as opt) ->
        run_wait_level protocol state nodes opt lvl)

let cmd () =
  let open Cmdliner in
  let open Term in
  let pp_error = Test_command_line.Common_errors.pp in
  let base_state =
    Test_command_line.Command_making_state.make ~application_name:"Flextesa"
      ~command_name:"mininet" ()
  in
  let docs = Manpage_builder.section_test_scenario base_state in
  let term =
    const
      (fun
        test_kind
        (`Clear_root clear_root)
        size
        base_port
        (`External_peers external_peer_ports)
        (`No_daemons_for no_daemons_for)
        protocol
        bnod
        bcli
        bak
        endo
        accu
        hard_fork
        genesis_block_choice
        nodes_history_mode_edits
        state
        smart_rollup
        smart_contracts
        adaptive_issuance
      ->
        let actual_test =
          run state ~size ~base_port ~protocol bnod bcli bak endo accu
            ?hard_fork ?smart_rollup ~clear_root ~nodes_history_mode_edits
            ~external_peer_ports ~no_daemons_for ~genesis_block_choice
            ~smart_contracts ~adaptive_issuance test_kind
        in
        Test_command_line.Run_command.or_hard_fail state ~pp_error
          (Interactive_test.Pauser.run_test ~pp_error state actual_test))
    $ term_result ~usage:true
        Arg.(
          pure
            Result.(
              fun level_opt random_traffic dsl_cmd ->
                match (level_opt, random_traffic, dsl_cmd) with
                | None, None, None -> return `Interactive
                | Some l, None, None -> return (`Wait_level (`At_least l))
                | Some l, Some kind, None ->
                    return (`Random_traffic (kind, `Until l))
                | None, None, Some cmd ->
                    return
                      (`Dsl_traffic (`Dsl_command cmd, `After `Interactive))
                | Some l, None, Some cmd ->
                    return (`Dsl_traffic (`Dsl_command cmd, `After (`Until l)))
                | _, Some _, Some _ ->
                    fail
                      (`Msg
                        "Error: option `--random-traffic` can't be combined \
                         with  `--traffic`.")
                | None, Some _, None ->
                    fail
                      (`Msg
                        "Error: option `--random-traffic` requires also \
                         `w--until-level`."))
          $ value
              (opt (some int) None
                 (info [ "until-level" ] ~docs
                    ~doc:"Run the sandbox until a given level (not interactive)"))
          $ value
              (opt
                 (some (enum [ ("any", `Any) ]))
                 None
                 (info [ "random-traffic" ] ~docs
                    ~doc:"Generate random traffic (requires `--until-level`)."))
          $ value
              (opt (some string) None
                 (info [ "traffic" ] ~docs
                    ~doc:
                      "Generate traffic using the dsl syntax. Upon completion \
                       of the specified commands, the program will wait until \
                       the block heigh specified by `--until-level` is \
                       reached, and then exit.  If `--until-level is not \
                       supplied, the interactive mode will be entered upon \
                       completion of the commands. ")))
    $ Arg.(
        pure (fun kr -> `Clear_root (not kr))
        $ value
            (flag
               (info [ "keep-root" ]
                  ~doc:
                    "Do not erase the root path before starting (this also \
                     makes the sandbox start-up bypass the protocol-activation \
                     step).")))
    $ Arg.(
        value & opt int 5
        & info [ "size"; "S" ] ~docs ~doc:"Set the size of the network.")
    $ Arg.(
        value & opt int 20_000
        & info [ "base-port"; "P" ] ~docs ~doc:"Base port number to build upon.")
    $ Arg.(
        pure (fun l -> `External_peers l)
        $ value
            (opt_all int []
               (info
                  [ "add-external-peer-port" ]
                  ~docv:"PORT-NUMBER" ~docs
                  ~doc:"Add $(docv) to the peers of the network nodes.")))
    $ Arg.(
        pure (fun l -> `No_daemons_for l)
        $ value
            (opt_all string []
               (info [ "no-daemons-for" ] ~docv:"ACCOUNT-NAME" ~docs
                  ~doc:"Do not start daemons for $(docv).")))
    $ Tezos_protocol.cli_term base_state
    $ Tezos_executable.cli_term base_state `Node ~prefix:"tezos"
    $ Tezos_executable.cli_term base_state `Client ~prefix:"tezos"
    $ Tezos_executable.cli_term base_state `Baker ~prefix:"tezos"
    $ Tezos_executable.cli_term base_state `Endorser ~prefix:"tezos"
    $ Tezos_executable.cli_term base_state `Accuser ~prefix:"tezos"
    $ Hard_fork.cmdliner_term ~docs base_state ()
    $ Genesis_block_hash.Choice.cmdliner_term ()
    $ Tezos_node.History_modes.cmdliner_term base_state
    $ Test_command_line.Full_default_state.cmdliner_term base_state ()
    $ Smart_rollup.cmdliner_term base_state ()
    $ Smart_contract.cmdliner_term base_state ()
    $ Arg.(
        value
        & opt (enum [ ("on", `On); ("off", `Off); ("pass", `Pass) ]) `Pass
        & info
            [ "adaptive-issuance-vote" ]
            ~docs ~docv:"VOTE"
            ~doc:"Set the adaptive issuance vote for all bakers to $(docv).")
  in
  let info =
    let doc = "Small network sandbox with bakers, endorsers, and accusers." in
    let man : Manpage.block list =
      Manpage_builder.make base_state
        ~intro_blob:
          "This test builds a small sandbox network, start various daemons, \
           and then gives the user an interactive command prompt to inspect \
           the network."
        [
          `P
            "One can also run this sandbox with `--no-baking` to make baking \
             interactive-only.";
          `P
            "There is also the option of running the sandbox non-interactively \
             for a given number of blocks, cf. `--until-level LEVEL`.";
        ]
    in
    info "mini-network" ~man ~doc
  in
  (term, info)
  [@@warning "-3"]
