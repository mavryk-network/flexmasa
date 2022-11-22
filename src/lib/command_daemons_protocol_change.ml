open Internal_pervasives
open Console

let failf fmt = ksprintf (fun s -> fail (`Scenario_error s)) fmt

let wait_for_voting_period ?level_within_period state ~protocol ~client
    ~attempts period =
  let is_expected_period (voting_period : (string * Ezjsonm.value) list)
      period_name =
    match Stdlib.List.assoc_opt "voting_period" voting_period with
    | Some (`O obj) -> (
        match Stdlib.List.assoc_opt "kind" obj with
        | Some (`String p) -> String.equal p period_name
        | _ -> false)
    | _ -> false
  in
  let period_name = Tezos_protocol.voting_period_to_string protocol period in
  let message =
    sprintf "Waiting for voting period: `%s`%s" period_name
      (Option.value_map level_within_period ~default:""
         ~f:(sprintf " (and level-within-period ≥ %d)"))
  in
  Console.say state EF.(wf "%s" message) >>= fun () ->
  Helpers.wait_for state ~attempts
    ~seconds:(fun () -> return 10.)
    (fun nth ->
      Asynchronous_result.map_option level_within_period ~f:(fun lvl ->
          Tezos_client.rpc state ~client `Get
            ~path:"/chains/main/blocks/head/metadata"
          >>= fun json ->
          try
            let voting_period_position =
              Jqo.field ~k:"voting_period_info" json
              |> Jqo.field ~k:"position" |> Jqo.get_int
            in
            return (voting_period_position >= lvl)
          with e ->
            failf "Cannot get level.voting_period_position: %s"
              (Exn.to_string e))
      >>= fun lvl_ok ->
      Tezos_client.rpc state ~client `Get
        ~path:"/chains/main/blocks/head/votes/current_period"
      >>= function
      | `O voting_period
        when is_expected_period voting_period period_name
             (* If we ware at the voting_period we are done wating. *)
             && Poly.(lvl_ok = None || lvl_ok = Some true) ->
          return (`Done (nth - 1))
      | _ ->
          Tezos_client.successful_client_cmd state ~client
            [ "show"; "voting"; "period" ]
          >>= fun res ->
          Console.say state
            EF.(
              desc_list (wf "Voting period:")
                [ markdown_verbatim (String.concat ~sep:"\n" res#out) ])
          >>= fun () -> return (`Not_done message))

let run state ~protocol ~next_protocol_kind ~size ~base_port ~no_daemons_for
    ?external_peer_ports ~node_exec ~client_exec ~first_baker_exec
    ~first_endorser_exec ~first_accuser_exec ~second_baker_exec
    ~second_endorser_exec ~second_accuser_exec ~admin_exec
    ~extra_dummy_proposals_batch_size ~extra_dummy_proposals_batch_levels
    ~waiting_attempts test_variant wait_level () =
  Helpers.clear_root state >>= fun () ->
  Helpers.System_dependencies.precheck state `Or_fail
    ~protocol_kind:protocol.Tezos_protocol.kind
    ~executables:
      ([ node_exec; client_exec ]
      @
      if state#test_baking then
        if
          Tezos_protocol.Protocol_kind.wants_endorser_daemon
            protocol.Tezos_protocol.kind
        then
          [
            first_baker_exec;
            first_endorser_exec;
            first_accuser_exec;
            second_baker_exec;
            second_endorser_exec;
            second_accuser_exec;
          ]
        else
          [
            first_baker_exec;
            first_accuser_exec;
            second_baker_exec;
            second_accuser_exec;
          ]
      else [])
  >>= fun () ->
  Test_scenario.network_with_protocol ?external_peer_ports ~protocol ~size
    ~base_port state ~node_exec ~client_exec
  >>= fun (nodes, protocol) ->
  let accusers =
    List.concat_map nodes ~f:(fun node ->
        let client = Tezos_client.of_node node ~exec:client_exec in
        [
          Tezos_daemon.accuser_of_node ~protocol_kind:protocol.kind
            ~exec:first_accuser_exec ~client node ~name_tag:"first";
          Tezos_daemon.accuser_of_node ~protocol_kind:protocol.kind
            ~exec:second_accuser_exec ~client node ~name_tag:"second";
        ])
  in
  List_sequential.iter accusers ~f:(fun acc ->
      Running_processes.start state (Tezos_daemon.process state acc)
      >>= fun _ -> return ())
  >>= fun () ->
  let keys_and_daemons =
    let pick_a_node_and_client idx =
      match List.nth nodes ((1 + idx) % List.length nodes) with
      | Some node -> (node, Tezos_client.of_node node ~exec:client_exec)
      | None -> assert false
    in
    Tezos_protocol.bootstrap_accounts protocol
    |> List.filter_mapi ~f:(fun idx acc ->
           let node, client = pick_a_node_and_client idx in
           let key = Tezos_protocol.Account.name acc in
           let if_proto_wants protokind f =
             if Tezos_protocol.Protocol_kind.wants_endorser_daemon protokind
             then [ f () ]
             else []
           in
           if List.mem ~equal:String.equal no_daemons_for key then None
           else
             Some
               ( acc,
                 client,
                 [
                   Tezos_daemon.baker_of_node ~protocol_kind:protocol.kind
                     ~exec:first_baker_exec ~client node ~key ~name_tag:"first";
                   Tezos_daemon.baker_of_node ~protocol_kind:next_protocol_kind
                     ~exec:second_baker_exec ~client ~name_tag:"second" node
                     ~key;
                 ]
                 @ if_proto_wants protocol.kind (fun () ->
                       Tezos_daemon.endorser_of_node
                         ~protocol_kind:protocol.kind ~exec:first_endorser_exec
                         ~name_tag:"first" ~client node ~key)
                 @ if_proto_wants next_protocol_kind (fun () ->
                       Tezos_daemon.endorser_of_node
                         ~protocol_kind:next_protocol_kind
                         ~exec:second_endorser_exec ~name_tag:"second" ~client
                         node ~key) ))
  in
  List_sequential.iter keys_and_daemons ~f:(fun (acc, client, daemons) ->
      Tezos_client.wait_for_node_bootstrap state client >>= fun () ->
      let key, priv = Tezos_protocol.Account.(name acc, private_key acc) in
      Tezos_client.import_secret_key state client ~name:key ~key:priv
      >>= fun () ->
      say state
        EF.(
          desc_list
            (haf "Registration-as-delegate:")
            [
              desc (af "Client:") (af "%S" client.Tezos_client.id);
              desc (af "Key:") (af "%S" key);
            ])
      >>= fun () ->
      Tezos_client.register_as_delegate state client ~key_name:key >>= fun () ->
      say state
        EF.(
          desc_list (haf "Starting daemons:")
            [
              desc (af "Client:") (af "%S" client.Tezos_client.id);
              desc (af "Key:") (af "%S" key);
            ])
      >>= fun () ->
      List_sequential.iter daemons ~f:(fun daemon ->
          Running_processes.start state (Tezos_daemon.process state daemon)
          >>= fun _ -> return ()))
  >>= fun () ->
  let client_0 =
    Tezos_client.of_node (List.nth_exn nodes 0) ~exec:client_exec
  in
  let make_admin = Tezos_admin_client.of_client ~exec:admin_exec in
  Interactive_test.Pauser.add_commands state
    Interactive_test.Commands.(
      all_defaults state ~nodes
      @ [ secret_keys state ~protocol ]
      @ arbitrary_commands_for_each_and_all_clients state ~make_admin
          ~clients:(List.map nodes ~f:(Tezos_client.of_node ~exec:client_exec)));
  (* Flextesa sandbox tests assume the node already knows about the protocol. We skip protocol injection. *)
  return (Some Tezos_protocol.Protocol_kind.(canonical_hash next_protocol_kind))
  >>= fun prot_opt ->
  (match prot_opt with
  | Some s -> return s
  | None -> failf "protocol injection problem?")
  >>= fun new_protocol_hash ->
  Test_scenario.Queries.wait_for_all_levels_to_be state
    ~attempts:waiting_attempts
    ~seconds:(fun () -> return 10.)
    nodes
    (* TODO: wait for /chains/main/blocks/head/votes/listings to be
       non-empty instead of counting blocks *)
    (`At_least protocol.Tezos_protocol.blocks_per_voting_period)
  >>= fun () ->
  Interactive_test.Pauser.generic state
    EF.
      [
        wf "Test becomes interactive.";
        wf "Please type `q` to start a voting/protocol-change period.";
      ]
  >>= fun () ->
  wait_for_voting_period state ~protocol ~client:client_0
    ~attempts:waiting_attempts `Proposal ~level_within_period:3
  >>= fun _ ->
  let submit_prop acc client hash =
    Tezos_client.successful_client_cmd state ~client
      [
        "submit";
        "proposals";
        "for";
        Tezos_protocol.Account.name acc;
        hash;
        "--force";
      ]
    >>= fun _ ->
    Console.sayf state
      Fmt.(
        fun ppf () ->
          pf ppf "%s voted for %s" (Tezos_protocol.Account.name acc) hash)
  in
  List_sequential.iter keys_and_daemons ~f:(fun (acc, client, _) ->
      submit_prop acc client new_protocol_hash)
  >>= fun () ->
  let make_dummy_protocol_hashes t tag =
    List.map
      (List.init extra_dummy_proposals_batch_size ~f:(fun s ->
           sprintf "proto-%s-%d" tag s))
      ~f:(fun s ->
        ( t,
          Tezai_base58_digest.Identifier.Protocol_hash.(hash_string s |> encode)
        ))
  in
  let extra_dummy_protocols =
    List.bind extra_dummy_proposals_batch_levels ~f:(fun l ->
        make_dummy_protocol_hashes l (sprintf "%d" l))
  in
  Console.say state
    EF.(
      wf "Going to also vote for %s"
        (String.concat ~sep:", " (List.map extra_dummy_protocols ~f:snd)))
  >>= fun () ->
  List_sequential.iteri extra_dummy_protocols ~f:(fun nth (level, proto_hash) ->
      match List.nth keys_and_daemons (nth % List.length keys_and_daemons) with
      | None ->
          failf "Too many dummy protocols Vs available voting power (%d)" nth
      | Some (acc, client, _) ->
          wait_for_voting_period state ~protocol ~client:client_0
            ~attempts:waiting_attempts `Proposal ~level_within_period:level
          >>= fun _ -> submit_prop acc client proto_hash)
  >>= fun () ->
  wait_for_voting_period state ~protocol ~client:client_0
    ~attempts:waiting_attempts `Exploration
  >>= fun _ ->
  List_sequential.iter keys_and_daemons ~f:(fun (acc, client, _) ->
      Tezos_client.successful_client_cmd state ~client
        [
          "submit";
          "ballot";
          "for";
          Tezos_protocol.Account.name acc;
          new_protocol_hash;
          "yea";
        ]
      >>= fun _ ->
      Console.sayf state
        Fmt.(
          fun ppf () ->
            pf ppf "%s voted Yea to test %s"
              (Tezos_protocol.Account.name acc)
              new_protocol_hash))
  >>= fun () ->
  wait_for_voting_period state ~protocol ~client:client_0
    ~attempts:waiting_attempts `Promotion
  >>= fun _ ->
  let protocol_switch_will_happen =
    match test_variant with
    | `Full_upgrade -> true
    | `Nay_for_promotion -> false
  in
  List_sequential.iter keys_and_daemons ~f:(fun (acc, client, _) ->
      Tezos_client.successful_client_cmd state ~client
        [
          "submit";
          "ballot";
          "for";
          Tezos_protocol.Account.name acc;
          new_protocol_hash;
          (if protocol_switch_will_happen then "yea" else "nay");
        ]
      >>= fun _ ->
      Console.sayf state
        Fmt.(
          fun ppf () ->
            pf ppf "%s voted Yea to promote %s"
              (Tezos_protocol.Account.name acc)
              new_protocol_hash))
  >>= fun () ->
  wait_for_voting_period state ~protocol ~client:client_0
    ~attempts:waiting_attempts `Proposal
  >>= fun _ ->
  Tezos_client.successful_client_cmd state ~client:client_0
    [ "show"; "voting"; "period" ]
  >>= fun res ->
  let protocol_to_wait_for =
    if protocol_switch_will_happen then new_protocol_hash
    else protocol.Tezos_protocol.hash
  in
  Helpers.wait_for state ~attempts:waiting_attempts
    ~seconds:(fun () -> return 4.)
    (fun _ ->
      Console.say state EF.(wf "Checking actual protocol transition")
      >>= fun () ->
      Tezos_client.rpc state ~client:client_0 `Get
        ~path:"/chains/main/blocks/head/metadata"
      >>= fun json ->
      (try Jqo.field ~k:"protocol" json |> Jqo.get_string |> return
       with e -> failf "Cannot parse metadata: %s" (Exn.to_string e))
      >>= fun proto_hash ->
      if not (String.equal proto_hash protocol_to_wait_for) then
        return
          (`Not_done
            (sprintf "Protocol not done: %s Vs %s" proto_hash
               protocol_to_wait_for))
      else return (`Done ()))
  >>= fun () ->
  match wait_level with
  | `Interactive_pause ->
      Interactive_test.Pauser.generic state
        EF.
          [
            wf "Test finished, protocol is now %s, things should keep baking."
              protocol_to_wait_for;
            markdown_verbatim (String.concat ~sep:"\n" res#out);
          ]
  | `Wait_level (`At_least lvl as opt) ->
      Test_scenario.Queries.run_wait_level protocol state nodes opt lvl

let cmd () =
  let open Cmdliner in
  let open Term in
  let pp_error = Test_command_line.Common_errors.pp in
  let base_state =
    Test_command_line.Command_making_state.make ~application_name:"Flextesa"
      ~command_name:"daemons-upgrade" ()
  in
  let docs = Manpage_builder.section_test_scenario base_state in
  let variants =
    [
      ( "full-upgrade",
        `Full_upgrade,
        "Go through the whole voting process and do the protocol change." );
      ( "nay-for-promotion",
        `Nay_for_promotion,
        "Go through the whole voting process but vote Nay at the last period \
         and hence stay on the same protocol." );
    ]
  in
  let term =
    const
      (fun
        size
        base_port
        (`Attempts waiting_attempts)
        (`External_peers external_peer_ports)
        (`No_daemons_for no_daemons_for)
        protocol
        node_exec
        client_exec
        admin_exec
        first_baker_exec
        first_endorser_exec
        first_accuser_exec
        second_baker_exec
        second_endorser_exec
        second_accuser_exec
        (`Next_protocol next_protocol_kind)
        (`Extra_dummy_proposals_batch_size extra_dummy_proposals_batch_size)
        (`Extra_dummy_proposals_batch_levels extra_dummy_proposals_batch_levels)
        test_variant
        wait_level
        state
      ->
        let actual_test =
          run state ~size ~base_port ~protocol ~node_exec ~client_exec
            ~first_baker_exec ~first_endorser_exec ~first_accuser_exec
            ~second_baker_exec ~second_endorser_exec ~second_accuser_exec
            ~admin_exec ~external_peer_ports ~no_daemons_for ~next_protocol_kind
            test_variant ~waiting_attempts ~extra_dummy_proposals_batch_size
            ~extra_dummy_proposals_batch_levels wait_level
        in
        Test_command_line.Run_command.or_hard_fail state ~pp_error
          (Interactive_test.Pauser.run_test ~pp_error state actual_test))
    $ Arg.(
        value & opt int 5
        & info [ "size"; "S" ] ~docs ~doc:"Set the size of the network.")
    $ Arg.(
        value & opt int 20_000
        & info [ "base-port"; "P" ] ~docs ~doc:"Base port number to build upon.")
    $ Arg.(
        const (fun n -> `Attempts n)
        $ value
            (opt int 60
               (info [ "waiting-attempts" ] ~docs
                  ~doc:
                    "Number of attempts done while waiting for voting periods")))
    $ Arg.(
        const (fun l -> `External_peers l)
        $ value
            (opt_all int []
               (info
                  [ "add-external-peer-port" ]
                  ~docv:"PORT-NUMBER" ~docs
                  ~doc:"Add $(docv) to the peers of the network nodes.")))
    $ Arg.(
        const (fun l -> `No_daemons_for l)
        $ value
            (opt_all string []
               (info [ "no-daemons-for" ] ~docv:"ACCOUNT-NAME" ~docs
                  ~doc:"Do not start daemons for $(docv).")))
    $ Tezos_protocol.cli_term base_state
    $ Tezos_executable.cli_term base_state `Node "octez"
    $ Tezos_executable.cli_term base_state `Client "octez"
    $ Tezos_executable.cli_term base_state `Admin "octez"
    $ Tezos_executable.cli_term base_state `Baker "first"
    $ Tezos_executable.cli_term base_state `Endorser "first"
    $ Tezos_executable.cli_term base_state `Accuser "first"
    $ Tezos_executable.cli_term base_state `Baker "second"
    $ Tezos_executable.cli_term base_state `Endorser "second"
    $ Tezos_executable.cli_term base_state `Accuser "second"
    $ Arg.(
        const (fun p -> `Next_protocol p)
        $ value
            Tezos_protocol.Protocol_kind.(
              opt (enum names) default
                (info [ "next-protocol-kind" ] ~docs
                   ~doc:"The protocol to be injected.")))
    $ Arg.(
        const (fun l -> `Extra_dummy_proposals_batch_size l)
        $ value
            (opt int 0
               (info ~docs
                  [ "extra-dummy-proposals-batch-size" ]
                  ~docv:"NUMBER"
                  ~doc:
                    "Submit $(docv) extra proposals per batch. $(docv) \
                     shouldn't exeed the nubmer of bootstrap-accounts. (See \
                     Protocol Options: --number-of-boot-strap-accounts)")))
    $ Arg.(
        const (fun x -> `Extra_dummy_proposals_batch_levels x)
        $ value
            (opt (list ~sep:',' int) []
               (info
                  [ "extra-dummy-proposals-batch-levels" ]
                  ~docs ~docv:"NUMBER"
                  ~doc:
                    "Set the levels within the proposal period where batches \
                     of extra proposals appear, e.g. `3,5,7`.")))
    $ Arg.(
        let doc =
          sprintf "Which variant of the test to run (one of {%s})"
            (List.map ~f:(fun (n, _, _) -> n) variants
            |> String.concat ~sep:", ")
        in
        value
          (opt
             (enum (List.map variants ~f:(fun (n, v, _) -> (n, v))))
             `Full_upgrade
             (info ~docs [ "test-variant" ] ~doc)))
    $ Arg.(
        pure (fun l ->
            match l with
            | Some l -> `Wait_level (`At_least l)
            | None -> `Interactive_pause)
        $ value
            (opt (some int) None
               (info [ "until-level" ] ~docs
                  ~doc:"Run the sandbox until a given level (not interactive)")))
    $ Test_command_line.cli_state ~name:"daemons-upgrade" ()
  in
  let info =
    let doc =
      "Vote and Protocol-upgrade with bakers, endorsers, and accusers."
    in
    let man : Manpage.block list =
      [
        `S "DAEMONS-UPGRADE TEST";
        `P
          "This test builds and runs a sandbox network to do a full voting \
           round followed by a protocol change while all the daemons.";
        `P
          (sprintf
             "There are for now %d variants (see option `--test-variant`):"
             (List.length variants));
        `Blocks
          (List.concat_map variants ~f:(fun (n, _, desc) ->
               [ `Noblank; `P (sprintf "* `%s`: %s" n desc) ]));
        `P
          "The upgrade protocol is designated by `--next-protocol-kind`  \
           (which should be the one understood by the `--second-*` \
           executables).";
        `P "When the test is interactive:";
        `Blocks
          (List.concat_mapi
             ~f:(fun i s -> [ `Noblank; `P (sprintf "%d) %s" (i + 1) s) ])
             [
               "It starts a sandbox assuming the protocol of the `--first-*` \
                executables (use the `--protocol-hash` option to make sure it \
                matches).";
               "An interactive pause is done to let the user play with the \
                `first` protocol.";
               "Once the user quits the prompt (`q` or `quit` command), a full \
                voting round happens with a single proposal.";
               "Once the potential protocol switch has happened (and been \
                verified), the test re-enters an interactive prompt to let the \
                user play with the protocol (the first or second one, \
                depending on the `--test-variant` option).";
             ]);
      ]
    in
    info "daemons-upgrade" ~man ~doc
  in
  (term, info)
  [@@warning "-3"]
