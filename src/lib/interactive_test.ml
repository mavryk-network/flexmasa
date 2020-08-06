open Internal_pervasives

module Commands = struct
  let cmdline_fail fmt = Fmt.kstr (fun s -> fail (`Command_line s)) fmt

  let no_args = function
    | [] -> return ()
    | _more -> cmdline_fail "this command expects no arguments"

  let flag f sexps = List.mem sexps (Base.Sexp.Atom f) ~equal:Base.Sexp.equal

  let unit_loop_no_args ~description opts f =
    Console.Prompt.unit_and_loop ~description opts (fun sexps ->
        no_args sexps >>= fun () -> f ())

  module Sexp_options = struct
    type t = {name: string; placeholders: string list; description: string}
    type option = t

    let make_option name ?(placeholders = []) description =
      {name; placeholders; description}

    let pp_options l ppf () =
      let open More_fmt in
      vertical_box ~indent:2 ppf (fun ppf ->
          pf ppf "Options:" ;
          List.iter l ~f:(fun {name; placeholders; description} ->
              cut ppf () ;
              wrapping_box ~indent:2 ppf (fun ppf ->
                  let opt_ex ppf () =
                    prompt ppf (fun ppf ->
                        pf ppf "%s%s" name
                          ( if Poly.equal placeholders [] then ""
                          else
                            List.map ~f:(str " %s") placeholders
                            |> String.concat ~sep:"" )) in
                  pf ppf "* %a  %a" opt_ex () text description)))

    let find opt sexps f =
      List.find_map sexps
        ~f:
          Sexp.(
            function
            | List (Atom a :: more)
              when (String.equal a opt.name || String.equal a (":" ^ opt.name))
                   && Int.(List.length more = List.length opt.placeholders) ->
                Some (f more)
            | _ -> None)

    let find_new opt sexps g =
      let sub_list =
        List.drop_while sexps ~f:(function
          | Sexp.Atom a when String.equal a (":" ^ opt.name) -> false
          | _ -> true) in
      match sub_list with
      | Sexp.Atom _ :: Sexp.Atom o :: _ -> Some (g [Sexp.Atom o])
      | _ -> None

    let get opt sexps ~default ~f =
      match find_new opt sexps f with
      | Some n -> return n
      | None -> (
        match find opt sexps f with Some n -> return n | None -> default () )
      | exception e -> cmdline_fail "Getting option %s: %a" opt.name Exn.pp e

    let get_int_exn = function
      | Sexp.[Atom a] -> (
        try Int.of_string a with _ -> Fmt.failwith "%S is not an integer" a )
      | other -> Fmt.failwith "wrong structure: %a" Sexp.pp (Sexp.List other)

    let get_float_exn = function
      | Sexp.[Atom a] -> (
        try Float.of_string a with _ -> Fmt.failwith "%S is not a float" a )
      | other -> Fmt.failwith "wrong structure: %a" Sexp.pp (Sexp.List other)

    let port_number_doc _ ~default_port =
      make_option "port" ~placeholders:["<int>"]
        Fmt.(str "Use port number <int> instead of %d (default)." default_port)

    let port_number _state ~default_port sexps =
      match
        List.find_map sexps
          ~f:
            Base.Sexp.(
              function
              | List [Atom "port"; Atom p] -> (
                try Some (`Ok (Int.of_string p))
                with _ -> Some (`Not_an_int p) )
              | List (Atom "port" :: _ as other) -> Some (`Wrong_option other)
              | _other -> None)
      with
      | None -> return default_port
      | Some (`Ok p) -> return p
      | Some ((`Not_an_int _ | `Wrong_option _) as other) ->
          let problem =
            match other with
            | `Not_an_int s -> Fmt.str "This is not an integer: %S." s
            | `Wrong_option s ->
                Fmt.str "Usage is (port <int>), too many arguments here: %s."
                  Base.Sexp.(to_string_hum (List s)) in
          fail (`Command_line "Error parsing (port ...) option")
            ~attach:[("Problem", `Text problem)]
  end

  let du_sh_root state =
    unit_loop_no_args
      ~description:(Fmt.str "Run du -sh on %s" (Paths.root state))
      ["d"; "du-root"]
      (fun () ->
        Running_processes.run_cmdf state "du -sh %s" (Paths.root state)
        >>= fun du ->
        Console.display_errors_of_command state du
        >>= function
        | true ->
            Console.say state
              EF.(
                desc (haf "Disk-Usage:")
                  (af "%s" (String.concat ~sep:" " du#out)))
        | false -> return ())

  let processes state =
    Console.Prompt.unit_and_loop
      ~description:
        "Display status of processes-manager ('all' to include non-running)"
      ["p"; "processes"] (fun sxp ->
        let all = flag "all" sxp in
        Console.say state (Running_processes.ef ~all state))

  let curl_rpc state ~port ~path =
    Running_processes.run_cmdf state "curl http://localhost:%d/%s" port path
    >>= fun curl_res ->
    Console.display_errors_of_command state curl_res ~should_output:true
    >>= fun success ->
    if not success then return None
    else
      ( try
          Ezjsonm.value_from_string (String.concat ~sep:"\n" curl_res#out)
          |> return
        with e -> cmdline_fail "Parsing JSON: %s" (Exn.to_string e) )
      >>= fun json -> return (Some json)

  let do_jq _state ~msg ~f = function
    | None -> cmdline_fail "%s: No JSON" msg
    | Some json -> (
      try return (f json)
      with e ->
        cmdline_fail "%s: failed to analyze JSON: %s from %s" msg
          (Exn.to_string e)
          (Ezjsonm.value_to_string ~minify:false json) )

  let curl_unit_display ?(jq = fun e -> e) ?pp_json state cmd ~default_port
      ~path ~doc =
    let pp_option =
      Option.value_map pp_json ~default:[] ~f:(fun _ ->
          [ Sexp_options.make_option "raw"
              "Do not try to pretty print the output." ]) in
    let get_pp_json _state sexps =
      match pp_json with
      | None -> return More_fmt.json
      | Some _
        when List.exists sexps
               ~f:Sexp.(function List [Atom "raw"] -> true | _ -> false) ->
          return More_fmt.json
      | Some default -> return default in
    Console.Prompt.unit_and_loop ~description:doc
      ~details:
        (Sexp_options.pp_options
           (pp_option @ [Sexp_options.port_number_doc state ~default_port]))
      cmd
      (fun sexps ->
        Sexp_options.port_number state sexps ~default_port
        >>= fun port ->
        get_pp_json state sexps
        >>= fun pp_json ->
        curl_rpc state ~port ~path
        >>= fun json_opt ->
        do_jq ~msg:doc state json_opt ~f:jq
        >>= fun processed_json ->
        Console.sayf state
          More_fmt.(
            fun ppf () ->
              vertical_box ~indent:2 ppf (fun ppf ->
                  pf ppf "Curl-node:%d -> %s" port doc ;
                  cut ppf () ;
                  pp_json ppf processed_json)))

  let curl_metadata state ~default_port =
    curl_unit_display state ["m"; "metadata"] ~default_port
      ~path:"/chains/main/blocks/head/metadata"
      ~doc:"Display `/chains/main/blocks/head/metadata`."

  let curl_level state ~default_port =
    curl_unit_display state ["l"; "level"] ~default_port
      ~path:"/chains/main/blocks/head" ~doc:"Display current head block info."
      ~pp_json:Tezos_protocol.Pretty_print.(verbatim_protection block_head_rpc)

  let curl_baking_rights state ~default_port =
    curl_unit_display state ["bk"; "baking-rights"] ~default_port
      ~path:"/chains/main/blocks/head/helpers/baking_rights"
      ~doc:"Display baking rights."

  let all_levels state ~nodes =
    unit_loop_no_args
      ~description:"Get all “head” levels of all the nodes."
      ["al"; "all-levels"] (fun () ->
        Test_scenario.Queries.all_levels state ~nodes
        >>= fun results ->
        Console.say state
          EF.(
            desc (af "Node-levels:")
              (list
                 (List.map results ~f:(fun (id, result) ->
                      desc (haf "%s" id)
                        ( match result with
                        | `Failed -> af "Failed"
                        | `Level i -> af "[%d]" i
                        | `Null -> af "{Null}"
                        | `Unknown s -> af "¿%s?" s ))))))

  let mempool state ~default_port =
    curl_unit_display state ["mp"; "mempool"] ~default_port
      ~path:"/chains/main/mempool/pending_operations"
      ~doc:"Display the status of the mempool."
      ~pp_json:
        Tezos_protocol.Pretty_print.(
          verbatim_protection mempool_pending_operations_rpc)

  let show_process state =
    Console.Prompt.unit_and_loop
      ~description:"Show more of a process (by name-prefix)." ["show"]
      (function
      | [Atom name] ->
          let prefix = String.lowercase name in
          Running_processes.find_process_by_id state ~f:(fun n ->
              String.is_prefix (String.lowercase n) ~prefix)
          >>= fun procs ->
          List.fold procs ~init:(return []) ~f:(fun prevm {process; lwt} ->
              prevm
              >>= fun prev ->
              let open Running_processes in
              let out = output_path state process `Stdout in
              let err = output_path state process `Stderr in
              Running_processes.run_cmdf state "tail %s" out
              >>= fun tailout ->
              Running_processes.run_cmdf state "tail %s" err
              >>= fun tailerr ->
              return
                EF.(
                  desc_list
                    (haf "%S (%d)" process.Process.id lwt#pid)
                    [ desc (af "out: %s" out) (ocaml_string_list tailout#out)
                    ; desc (af "err: %s" err) (ocaml_string_list tailerr#out)
                    ]
                  :: prev))
          >>= fun ef -> Console.say state EF.(list ef)
      | _other -> cmdline_fail "command expects 1 argument: name-prefix")

  let kill_all state =
    unit_loop_no_args ~description:"Kill all known processes/process-groups."
      ["ka"; "killall"] (fun () -> Running_processes.kill_all state)

  let secret_keys state ~protocol =
    unit_loop_no_args
      ~description:"Show the protocol's “bootstrap” accounts."
      ["boa"; "bootstrap-accounts"] (fun () ->
        Console.sayf state
          More_fmt.(
            fun ppf () ->
              vertical_box ~indent:0 ppf (fun ppf ->
                  prompt ppf (fun ppf -> pf ppf "Bootstrap Accounts:") ;
                  List.iter (Tezos_protocol.bootstrap_accounts protocol)
                    ~f:(fun acc ->
                      let open Tezos_protocol.Account in
                      cut ppf () ;
                      pf ppf "* Account %S:@," (name acc) ;
                      pf ppf "  * Public Key Hash: %s@," (pubkey_hash acc) ;
                      pf ppf "  * Public Key:      %s@," (pubkey acc) ;
                      pf ppf "  * Private Key:     %s" (private_key acc)))))

  let show_connections state nodes =
    unit_loop_no_args ~description:"Show all node connections"
      ["ac"; "all-connections"] (fun () ->
        Helpers.dump_connections state nodes)

  let balances state ~default_port =
    Console.Prompt.unit_and_loop
      ~description:"Show the balances of all known accounts."
      ~details:
        (Sexp_options.pp_options
           [Sexp_options.port_number_doc state ~default_port])
      ["sb"; "show-balances"]
      (fun sexps ->
        Sexp_options.port_number state sexps ~default_port
        >>= fun port ->
        curl_rpc state ~port ~path:"/chains/main/blocks/head/context/contracts"
        >>= fun json_opt ->
        do_jq state ~msg:"Getting contract list" ~f:Jqo.get_strings json_opt
        >>= fun contracts ->
        curl_rpc state ~port ~path:"/chains/main/checkpoint"
        >>= fun chkpto ->
        do_jq state chkpto ~msg:"Getting checkpoint"
          ~f:
            Jqo.(
              fun json ->
                match field ~k:"history_mode" json |> get_string with
                | "archive" -> 1
                | _ ->
                    let sp = field ~k:"save_point" json |> get_int in
                    Int.max 1 sp)
        >>= fun save_point ->
        let balance block contract =
          let path =
            sprintf "/chains/main/blocks/%s/context/contracts/%s/balance" block
              contract in
          curl_rpc state ~port ~path
          >>= fun jo ->
          do_jq state jo ~msg:"Getting balance" ~f:(fun j ->
              Jqo.get_string j |> Int.of_string) in
        List.fold contracts ~init:(return []) ~f:(fun prevm hsh ->
            prevm
            >>= fun prev ->
            balance (Int.to_string save_point) hsh
            >>= fun init ->
            balance "head" hsh
            >>= fun current -> return ((hsh, init, current) :: prev))
        >>= fun results ->
        Console.say state
          EF.(
            desc_list
              (af "Balances from levels %d to “head” (port :%d)" save_point
                 port)
              (List.map results ~f:(fun (hsh, init, cur) ->
                   let tz i = Float.of_int i /. 1_000_000. in
                   desc (haf "%s:" hsh)
                     ( if init = cur then af "%f (unchanged)" (tz cur)
                     else
                       af "%f → %f (delta: %f)" (tz init) (tz cur)
                         (tz (cur - init)) )))))

  let better_call_dev state ~default_port =
    Console.Prompt.unit_and_loop
      ~description:"Show URIs to all contracts with `better-call.dev`."
      ~details:
        (Sexp_options.pp_options
           [Sexp_options.port_number_doc state ~default_port])
      ["bcd"; "better-call-dev"]
      (fun sexps ->
        Sexp_options.port_number state sexps ~default_port
        >>= fun port ->
        curl_rpc state ~port ~path:"/chains/main/blocks/head/context/contracts"
        >>= fun json_opt ->
        do_jq state ~msg:"Getting contract list" ~f:Jqo.get_strings json_opt
        >>= fun contracts ->
        let kt1s =
          List.filter contracts ~f:(fun c -> String.is_prefix c ~prefix:"KT1")
        in
        Console.sayf state
          Fmt.(
            fun ppf () ->
              vbox ~indent:2
                (fun ppf () ->
                  let block_url_arg =
                    kstr Uri.pct_encode
                      "blockUrl=http://127.0.0.1:%d/chains/main/blocks" port
                  in
                  let base =
                    Environment_configuration.better_call_dev_base_url state
                  in
                  match kt1s with
                  | [] ->
                      pf ppf "There are no KT1 contracts in this sandbox." ;
                      cut ppf () ;
                      pf ppf "You can still go to %s?%s" base block_url_arg
                  | some_kt1s ->
                      pf ppf "Links:" ;
                      cut ppf () ;
                      List.iter some_kt1s ~f:(fun c ->
                          if String.is_prefix c ~prefix:"KT1" then (
                            pf ppf "* %s/%s/operations?%s" base c block_url_arg ;
                            cut ppf () )))
                ppf ()))

  let arbitrary_command_on_all_clients ?make_admin
      ?(command_names = ["atc"; "all-clients"]) state ~clients =
    let details =
      let open Sexp_options in
      let only_opt =
        make_option "only"
          ~placeholders:["<name1>"; "<name2>"; "..."]
          "Restrict the clients by name." in
      let all =
        (match clients with [_] -> [] | _ -> [only_opt])
        @ Option.value_map make_admin ~default:[] ~f:(fun _ ->
              [make_option "admin" "Use the admin-client instead."]) in
      match all with [] -> None | _ -> Some (pp_options all) in
    Console.Prompt.unit_and_loop
      ~description:
        (Fmt.str "Run a tezos-client command on %s"
           ( match clients with
           | [] -> "NO CLIENT, so this is useless…"
           | [one] -> sprintf "the %S client." one.Tezos_client.id
           | more ->
               sprintf "all the following clients: %s."
                 ( List.map more ~f:(fun c -> c.Tezos_client.id)
                 |> String.concat ~sep:", " ) ))
      ?details command_names
      (fun sexps ->
        let args =
          let open Base.Sexp in
          List.filter_map sexps ~f:(function Atom s -> Some s | _ -> None)
        in
        let subset_of_clients =
          let open Base.Sexp in
          List.find_map sexps ~f:(function
            | List (Atom "only" :: l) ->
                Some
                  (List.map l ~f:(function
                    | Atom a -> a
                    | other ->
                        ksprintf failwith
                          "Option `only` only accepts a list of names: %s"
                          (to_string_hum other)))
            | _ -> None)
          |> function
          | None -> clients
          | Some more ->
              List.filter clients ~f:(fun c ->
                  List.mem more c.Tezos_client.id ~equal:String.equal) in
        let use_admin =
          match make_admin with
          | None -> `Client
          | Some of_client ->
              if
                List.exists sexps
                  ~f:
                    Base.Sexp.(
                      function List [Atom "admin"] -> true | _ -> false)
              then `Admin of_client
              else `Client in
        List.fold ~init:(return []) subset_of_clients ~f:(fun prevm client ->
            prevm
            >>= fun prev ->
            Running_processes.run_cmdf state "sh -c %s"
              ( ( match use_admin with
                | `Client -> Tezos_client.client_command state client args
                | `Admin mkadm ->
                    Tezos_admin_client.make_command state (mkadm client) args
                )
              |> Genspio.Compile.to_one_liner |> Caml.Filename.quote )
            >>= fun res ->
            Console.display_errors_of_command state res
            >>= function
            | true -> return ((client, String.concat ~sep:"\n" res#out) :: prev)
            | false -> return prev)
        >>= fun results ->
        let different_results =
          List.dedup_and_sort results ~compare:(fun (_, a) (_, b) ->
              String.compare a b) in
        Console.say state
          EF.(
            desc_list (af "Done")
              [ desc (haf "Command:")
                  (ocaml_string_list
                     ( ( match use_admin with
                       | `Client -> "<client>"
                       | `Admin _ -> "<admin>" )
                     :: args ))
              ; desc (haf "Results")
                  (list
                     (List.map different_results ~f:(fun (_, res) ->
                          let clients =
                            List.filter_map results ~f:(function
                              | c, r when String.equal res r ->
                                  Some c.Tezos_client.id
                              | _ -> None) in
                          desc
                            (haf "Client%s %s:"
                               ( if List.length subset_of_clients = 1 then ""
                               else "s" )
                               (String.concat ~sep:", " clients))
                            (markdown_verbatim res)))) ]))

  let arbitrary_commands_for_each_client ?make_admin
      ?(make_command_names = fun i -> [sprintf "c%d" i; sprintf "client-%d" i])
      state ~clients =
    List.mapi clients ~f:(fun i c ->
        arbitrary_command_on_all_clients state ?make_admin ~clients:[c]
          ~command_names:(make_command_names i))

  let arbitrary_commands_for_each_and_all_clients ?make_admin
      ?make_individual_command_names ?all_clients_command_names state ~clients
      =
    arbitrary_command_on_all_clients state ?make_admin ~clients
      ?command_names:all_clients_command_names
    :: arbitrary_commands_for_each_client state ?make_admin ~clients
         ?make_command_names:make_individual_command_names

  let protect_with_keyed_client msg ~client ~f =
    let msg =
      Fmt.str "Command-line %s with client %s (account: %s)" msg
        client.Tezos_client.Keyed.client.id client.Tezos_client.Keyed.key_name
    in
    Asynchronous_result.bind_on_error (f ()) ~f:(fun ~result:_ ->
      function
      | #Process_result.Error.t as e ->
          cmdline_fail "%s -> Error: %a" msg Process_result.Error.pp e
      | #System_error.t as e ->
          cmdline_fail "%s -> Error: %a" msg System_error.pp e
      | `Waiting_for (msg, `Time_out) ->
          cmdline_fail "WAITING-FOR “%s”: Time-out" msg
      | `Command_line _ as e -> fail e)

  let bake_command state ~clients =
    Console.Prompt.unit_and_loop
      ~description:
        Fmt.(
          str "Manually bake a block (with %s)."
            ( match clients with
            | [] -> "NO CLIENT, this is just wrong"
            | [one] -> one.Tezos_client.Keyed.client.id
            | m ->
                str "one of %s"
                  ( List.mapi m ~f:(fun ith one ->
                        str "%d: %s" ith one.Tezos_client.Keyed.client.id)
                  |> String.concat ~sep:", " ) ))
      ["bake"]
      (fun sexps ->
        let client =
          let open Base.Sexp in
          match sexps with
          | [] -> List.nth_exn clients 0
          | [Atom s] -> List.nth_exn clients (Int.of_string s)
          | _ -> Fmt.kstrf failwith "Wrong command line: %a" pp (List sexps)
        in
        protect_with_keyed_client "manual-baking" ~client ~f:(fun () ->
            Tezos_client.Keyed.bake state client "Manual baking !"))

  let generate_and_import_keys state client names =
    Console.say state
      EF.(
        desc
          (af "Importing keys for these signers:")
          (list (List.map names ~f:(fun name -> desc (haf "%s" name) (af "")))))
    >>= fun () ->
    List.fold names ~init:(return ()) ~f:(fun previous_m s ->
        previous_m
        >>= fun () ->
        let kp = Tezos_protocol.Account.of_name s in
        Tezos_client.import_secret_key state client
          ~name:(Tezos_protocol.Account.name kp)
          ~key:(Tezos_protocol.Account.private_key kp))

  let branch state client =
    Tezos_client.rpc state ~client:client.Tezos_client.Keyed.client `Get
      ~path:"/chains/main/blocks/head/hash"
    >>= fun br ->
    let branch = Jqo.get_string br in
    return branch

  type batch_action = {src: string; counter: int; size: int; fee: float}

  type multisig_action =
    {num_signers: int; outer_repeat: int; contract_repeat: int}

  type action =
    [`Batch_action of batch_action | `Multisig_action of multisig_action]

  type all_options =
    { counter_option: Sexp_options.option
    ; size_option: Sexp_options.option
    ; fee_option: Sexp_options.option
    ; num_signers_option: Sexp_options.option
    ; contract_repeat_option: Sexp_options.option }

  let get_batch_args state ~client opts more_args =
    protect_with_keyed_client "generate batch" ~client ~f:(fun () ->
        let src =
          client.key_name |> Tezos_protocol.Account.of_name
          |> Tezos_protocol.Account.pubkey_hash in
        Sexp_options.get opts.counter_option more_args
          ~f:Sexp_options.get_int_exn ~default:(fun () ->
            Tezos_client.rpc state ~client:client.client `Get
              ~path:
                (Fmt.str
                   "/chains/main/blocks/head/context/contracts/%s/counter" src)
            >>= fun counter_json ->
            return ((Jqo.get_string counter_json |> Int.of_string) + 1))
        >>= fun counter ->
        Sexp_options.get opts.size_option more_args ~f:Sexp_options.get_int_exn
          ~default:(fun () -> return 10)
        >>= fun size ->
        Sexp_options.get opts.fee_option more_args
          ~f:Sexp_options.get_float_exn ~default:(fun () -> return 0.02)
        >>= fun fee -> return (`Batch_action {src; counter; size; fee}))

  let get_multisig_args opts (more_args : Sexp.t list) =
    Sexp_options.get opts.size_option more_args ~f:Sexp_options.get_int_exn
      ~default:(fun () -> return 10)
    >>= fun outer_repeat ->
    Sexp_options.get opts.contract_repeat_option more_args
      ~f:Sexp_options.get_int_exn ~default:(fun () -> return 1)
    >>= fun contract_repeat ->
    Sexp_options.get opts.num_signers_option more_args
      ~f:Sexp_options.get_int_exn ~default:(fun () -> return 3)
    >>= fun num_signers ->
    return (`Multisig_action {num_signers; outer_repeat; contract_repeat})

  let to_action state ~client opts sexp =
    match sexp with
    | Sexp.List (Atom "batch" :: more_args) ->
        get_batch_args state ~client opts more_args
    | Sexp.List (Atom "multisig-batch" :: more_args) ->
        get_multisig_args opts more_args
    | Sexp.List (Atom a :: _) ->
        Fmt.kstr failwith "to_action - unexpected atom inside list: %s" a
    | Sexp.List z ->
        Fmt.kstr failwith "to_action - unexpected list. %s"
          (Sexp.to_string (List z))
    | Sexp.Atom b -> Fmt.kstr failwith "to_action - unexpected atom. %s" b

  let process_repeat_action sexp =
    match sexp with
    | Sexp.List (y :: _) -> (
      match y with
      | Sexp.List (Atom "repeat" :: Atom ":times" :: Atom n :: more_args) ->
          let c = Int.of_string n in
          let count = if c <= 0 then 1 else c in
          (count, Sexp.List more_args)
      | _ -> (1, sexp) )
    | _ -> (1, sexp)

  let process_random_choice sexp =
    match sexp with
    | Sexp.List (y :: _) -> (
      match y with
      | Sexp.List (Atom "random-choice" :: more_args) ->
          (true, Sexp.List more_args)
      | _ -> (false, sexp) )
    | other ->
        Fmt.kstr failwith
          "process_random_choice - expecting a list but got: %a" Sexp.pp other

  let process_action_cmds state ~client opts sexp ~random_choice =
    let rec loop (actions : action list) (exps : Base.Sexp.t list) =
      match exps with
      | [x] -> to_action state ~client opts x >>= fun a -> return (a :: actions)
      | x :: xs ->
          to_action state ~client opts x >>= fun a -> loop (a :: actions) xs
      | other ->
          Fmt.kstr failwith "process_action_cmds - something weird: %a" Sexp.pp
            (List other) in
    let exp_list =
      match sexp with
      | Sexp.List (y :: _) -> (
        match y with
        | Sexp.List z -> z
        | other ->
            Fmt.kstr failwith
              "process_action_cmds - inner fail - expecting a list within a \
               list but got: %a"
              Sexp.pp other )
      | other ->
          Fmt.kstr failwith
            "process_action_cmds - outer fail - expecting a list within a \
             list but got: %a"
            Sexp.pp other in
    loop [] exp_list
    >>= fun action_list ->
    if not random_choice then return action_list
    else
      let len = List.length action_list in
      if len = 0 then return []
      else
        let rand = Random.int len in
        let one_action = (List.to_array action_list).(rand) in
        return [one_action]

  let process_gen_batch state ~client act =
    protect_with_keyed_client "generate batch" ~client ~f:(fun () ->
        Helpers.Timing.duration
          (fun aFee ->
            branch state client
            >>= fun the_branch ->
            let json =
              Traffic_generation.Forge.batch_transfer ~src:act.src
                ~counter:act.counter ~fee:aFee ~branch:the_branch act.size
            in
            Tezos_client.Keyed.forge_and_inject state client ~json
            >>= fun json_result ->
            Console.sayf state More_fmt.(fun ppf () -> json ppf json_result))
          act.fee
        >>= fun ((), sec) ->
        Console.say state EF.(desc (haf "Execution time:") (af " %fs\n%!" sec)))

  let process_gen_multi_sig state ~client ~nodes act =
    protect_with_keyed_client "generate multisig" ~client ~f:(fun () ->
        Helpers.Timing.duration
          (fun () ->
            Traffic_generation.Multisig.deploy_and_transfer state client.client
              nodes ~num_signers:act.num_signers ~outer_repeat:act.outer_repeat
              ~contract_repeat:act.contract_repeat)
          ()
        >>= fun ((), sec) ->
        Console.say state EF.(desc (haf "Execution time:") (af " %fs\n%!" sec)))

  let run_actions state ~client ~nodes ~actions ~counter =
    Loop.n_times counter (fun _ ->
        List_sequential.iter actions ~f:(fun a ->
            match a with
            | `Batch_action ba -> process_gen_batch state ~client ba
            | `Multisig_action ma ->
                process_gen_multi_sig state ~client ~nodes ma))

  let process_dsl state ~client ~nodes opts sexp =
    protect_with_keyed_client "generate batch" ~client ~f:(fun () ->
        let n, sexp2 = process_repeat_action sexp in
        let b, sexp3 = process_random_choice sexp2 in
        process_action_cmds state ~client opts sexp3 ~random_choice:b
        >>= fun actions -> run_actions state ~client ~nodes ~actions ~counter:n)

  let generate_traffic_command state ~clients ~nodes =
    Console.Prompt.unit_and_loop
      ~description:
        Fmt.(
          str "Generate traffic from a client (%s); try `gen help`."
            ( match clients with
            | [] -> "NO CLIENT, this is just wrong"
            | [one] -> one.Tezos_client.Keyed.client.id
            | m ->
                str "use option (client ..) with one of %s"
                  ( List.mapi m ~f:(fun ith one ->
                        str "%d: %s" ith one.Tezos_client.Keyed.client.id)
                  |> String.concat ~sep:", " ) ))
      ["generate"; "gen"]
      (fun sexps ->
        let client =
          let open Sexp in
          match
            List.find_map sexps ~f:(function
              | List [Atom "client"; Atom s] ->
                  Some (List.nth_exn clients (Int.of_string s))
              | _ -> None)
          with
          | None -> List.nth_exn clients 0
          | Some c -> c
          | exception _ ->
              Fmt.kstr failwith "Wrong command line: %a" pp (List sexps) in
        let counter_option =
          Sexp_options.make_option ":counter" ~placeholders:["<int>"]
            "The counter to provide (get it from the node by default)." in
        let size_option =
          Sexp_options.make_option ":size" ~placeholders:["<int>"]
            "The batch size (default: 10)." in
        let fee_option =
          Sexp_options.make_option ":fee" ~placeholders:["<float-tz>"]
            "The fee per operation (default: 0.02)." in
        let level_option =
          Sexp_options.make_option ":level" ~placeholders:["<int>"]
            "The level." in
        let contract_repeat_option =
          Sexp_options.make_option ":operation-repeat" ~placeholders:["<int>"]
            "The number of repeated calls to execute the fully-signed \
             multi-sig contract (default: 1)." in
        let num_signers_option =
          Sexp_options.make_option ":num-signers" ~placeholders:["<int>"]
            "The number of signers required for the multi-sig contract \
             (default: 3)." in
        let repeat_all_option =
          Sexp_options.make_option "repeat"
            ~placeholders:[":times"; "<int>"; "<list of commands>"]
            "The number of times to repeat any dsl commands that follow \
             (default: 1)." in
        let random_choice_option =
          Sexp_options.make_option "random-choice"
            ~placeholders:["<list of commands>"]
            "Randomly chose a command from a list of dsl commands." in
        let all_opts : all_options =
          { counter_option
          ; size_option
          ; fee_option
          ; num_signers_option
          ; contract_repeat_option } in
        match sexps with
        | Atom "help" :: __ ->
            Console.sayf state
              More_fmt.(
                let cmd ppf name desc options =
                  cut ppf () ;
                  vertical_box ~indent:2 ppf (fun ppf ->
                      pf ppf "* Command `gen %s ...`:" name ;
                      cut ppf () ;
                      wrapping_box ppf (fun ppf -> desc ppf ()) ;
                      cut ppf () ;
                      Sexp_options.pp_options options ppf ()) in
                fun ppf () ->
                  pf ppf "Generating traffic: TODO" ;
                  cmd ppf "batch"
                    (const text "Make a batch operation (simple transfers).")
                    [counter_option; size_option; fee_option] ;
                  cmd ppf "multisig-batch"
                    (const text
                       "Make a batch operation (multi-sig transacitons).")
                    [ counter_option; contract_repeat_option; num_signers_option
                    ; size_option; fee_option ] ;
                  cmd ppf "dsl"
                    (const text
                       "Invoke commands using the dsl syntax. Example: \n\
                       \  dsl (repeat :times 5 (random-choice \n\
                       \  ((multisig-batch :size 5 :contract-repeat 3 \
                        :num-signers 4)\n\
                       \  (batch :size 10))))")
                    [repeat_all_option; random_choice_option] ;
                  cmd ppf "endorsement"
                    (const text "Make an endorsement for a given level")
                    [level_option])
        | Atom "endorsement" :: more_args ->
            protect_with_keyed_client "forge-and-inject" ~client ~f:(fun () ->
                branch state client
                >>= fun branch ->
                Sexp_options.get level_option more_args
                  ~f:Sexp_options.get_int_exn ~default:(fun () -> return 42)
                >>= fun level ->
                let json = Traffic_generation.Forge.endorsement ~branch level in
                Tezos_client.Keyed.forge_and_inject state client ~json
                >>= fun json_result ->
                Console.sayf state
                  More_fmt.(fun ppf () -> json ppf json_result))
        | Atom "batch" :: more_args ->
            get_batch_args state ~client all_opts more_args
            >>= fun ba ->
            run_actions state ~client ~nodes ~actions:[ba] ~counter:1
        | Atom "multisig-batch" :: more_args ->
            get_multisig_args all_opts more_args
            >>= fun ma ->
            run_actions state ~client ~nodes ~actions:[ma] ~counter:1
        | Atom "dsl" :: dsl_sexp ->
            let str = Sexp.to_string (Sexp.List dsl_sexp) in
            Console.say state EF.(desc (haf "dsl_sexp") (af " %s\n%!" str))
            >>= fun () ->
            process_dsl state ~client ~nodes all_opts (Sexp.List dsl_sexp)
        | other ->
            Fmt.kstr failwith "Wrong command line: %a" Sexp.pp (List other))

  let all_defaults state ~nodes =
    let default_port = (List.hd_exn nodes).Tezos_node.rpc_port in
    [ du_sh_root state; processes state
    ; show_connections state nodes
    ; curl_level state ~default_port
    ; balances state ~default_port
    ; curl_metadata state ~default_port
    ; curl_baking_rights state ~default_port
    ; mempool state ~default_port
    ; better_call_dev state ~default_port
    ; all_levels state ~nodes; show_process state; kill_all state ]
end

module Interactivity = struct
  type t = [`Full | `None | `On_error | `At_end]

  let is_interactive (state : < test_interactivity: t ; .. >) =
    Poly.equal state#test_interactivity `Full

  let pause_on_error state =
    match state#test_interactivity with
    | `Full | `On_error | `At_end -> true
    | `None -> false

  let pause_on_success state =
    match state#test_interactivity with
    | `Full | `At_end -> true
    | `None | `On_error -> false

  let cli_term ?(default : t = `None) () =
    let open Cmdliner in
    Term.(
      pure (fun interactive pause_end pause_error ->
          match (interactive, pause_end, pause_error) with
          | true, _, _ -> `Full
          | false, true, _ -> `At_end
          | false, false, true -> `On_error
          | false, false, false -> `None)
      $ Arg.(
          value
          & opt bool
              ( match default with
              | `None | `On_error | `At_end -> false
              | `Full -> true )
          & info ["interactive"] ~doc:"Add all pauses with command prompts.")
      $ Arg.(
          value
          & opt bool
              ( match default with
              | `None | `On_error -> false
              | `At_end | `Full -> true )
          & info ["pause-at-end"]
              ~doc:"Add a pause with a command prompt at the end of the test.")
      $ Arg.(
          value
          & opt bool
              ( match default with
              | `None -> false
              | `At_end | `Full | `On_error -> true )
          & info ["pause-on-error"]
              ~doc:
                "Add a pause with a command prompt at the end of the test, \
                 only in case of test failure."))
end

module Pauser = struct
  type t =
    { mutable extra_commands: Console.Prompt.item list
    ; default_end: [`Sleep of float] }

  let make ?(default_end = `Sleep 0.5) extra_commands =
    {extra_commands; default_end}

  let commands state = state#pauser.extra_commands
  let default_end state = state#pauser.default_end

  let add_commands state cl =
    state#pauser.extra_commands <- commands state @ cl

  let generic state ?(force = false) msgs =
    let do_pause = Interactivity.is_interactive state || force in
    Console.say state
      EF.(
        desc
          (if do_pause then haf "Pause" else haf "Not pausing")
          (list ~param:{default_list with space_before_separator= false} msgs))
    >>= fun () ->
    if do_pause then Console.Prompt.(command state ~commands:(commands state))
    else return ()

  let run_test state f ~pp_error () =
    let finish () =
      Console.say state EF.(af "Killing all processes.")
      >>= fun () ->
      Running_processes.kill_all state
      >>= fun () ->
      Console.say state EF.(af "Waiting for processes to all die.")
      >>= fun () -> Running_processes.wait_all state in
    Caml.Sys.catch_break false ;
    let cond = Lwt_condition.create () in
    let catch_signals () =
      Lwt_unix.on_signal Caml.Sys.sigint (fun i ->
          Caml.Printf.eprintf
            "\nReceived signal SIGINT (%d), type `q` to quit prompts.\n\n%!" i ;
          Lwt_condition.broadcast cond `Sig_int)
      |> ignore ;
      Lwt_unix.on_signal Caml.Sys.sigterm (fun i ->
          Caml.Printf.eprintf
            "\nReceived signal SIGTERM (%d), type `q` to quit prompts.\n\n%!" i ;
          Lwt_condition.broadcast cond `Sig_term)
      |> ignore in
    let wait_on_signals () =
      System_error.catch Lwt_condition.wait cond
      >>= fun sig_name -> return (`Woken_up_by_signal sig_name) in
    Dbg.e
      EF.(wf "Running test %s on %s" state#application_name (Paths.root state)) ;
    let wrap_result f = f () >>= fun o -> return (`Successful_procedure o) in
    let run_with_signal_catching ~name procedure =
      Lwt.(
        pick
          [ ( wrap_result (fun () -> procedure ())
            >>= fun res ->
            match res.Attached_result.result with
            | Ok _ ->
                Dbg.e EF.(wf "Procedure %s ended: ok" name) ;
                return res
            | Error (`System_error (_, System_error.Exception Lwt.Canceled)) ->
                Dbg.e EF.(wf "Procedure %s was cancelled" name) ;
                System.sleep 2.
                >>= fun _ ->
                Dbg.e EF.(wf "Procedure %s slept 2." name) ;
                return res
            | Error e ->
                Dbg.e
                  EF.(wf "Procedure %s ended with error %a" name pp_error e) ;
                return res )
          ; ( wait_on_signals ()
            >>= fun res ->
            Dbg.e EF.(wf "Signal-wait %S go woken up" name) ;
            return res ) ]) in
    let last_pause_status = ref `Not_done in
    let rec protect ~name procedure =
      catch_signals () ;
      Dbg.e EF.(wf "protecting %S" name) ;
      let last_pause () =
        protect ~name:"Last-pause" (fun () ->
            generic state ~force:true
              EF.
                [ haf
                    "Last pause before the application will Kill 'Em All and \
                     Quit." ]
            >>= fun () ->
            last_pause_status := `Done ;
            return ()) in
      Asynchronous_result.bind_all
        ( try
            Dbg.e EF.(wf "protecting: %S in-try" name) ;
            run_with_signal_catching ~name procedure
          with e ->
            System_error.fail_fatalf
              ~attach:[("protected", `String_value name)]
              "protecting %S: ocaml-exn: %a" name Exn.pp e )
        ~f:(fun result ->
          match result.result with
          | Ok (`Successful_procedure o) -> return (`Was_ok o)
          | Ok (`Woken_up_by_signal `Sig_term) ->
              Console.say state
                EF.(
                  desc (shout "Received SIGTERM")
                    (wf
                       "Will not pause because it's the wrong thing to do; \
                        killing everything and quitting."))
              >>= fun () -> return `Quit_with_error
          | Ok (`Woken_up_by_signal `Sig_int) ->
              Console.say state
                EF.(
                  desc (shout "Received SIGINT")
                    (wf
                       "Please the command `q` (a.k.a. `quit`) for quitting \
                        prompts."))
              >>= fun () -> return `Error_that_can_be_interactive
          | Error (`System_error (`Fatal, System_error.Exception End_of_file))
            ->
              Console.say state
                EF.(
                  desc
                    (shout "Received End-of-File (Ctrl-D?)")
                    (wf
                       "Cannot pause because interactivity broken; killing \
                        everything and quitting."))
              >>= fun () -> return `Quit_with_error
          | Error _ ->
              Console.say state
                EF.(
                  desc
                    (shout "An error happened")
                    (custom (fun ppf ->
                         Attached_result.pp ~pp_error ppf result)))
              >>= fun () -> return `Error_that_can_be_interactive)
      >>= fun todo_next ->
      match todo_next with
      | `Was_ok ()
        when Interactivity.pause_on_success state
             && Poly.equal !last_pause_status `Not_done ->
          last_pause ()
      | `Was_ok () -> (
          finish ()
          >>= fun () ->
          match default_end state with
          | `Sleep n ->
              Console.say state EF.(wf "Test done, sleeping %.02f seconds" n)
              >>= fun () -> System.sleep n )
      | `Error_that_can_be_interactive when Interactivity.pause_on_error state
        ->
          last_pause ()
      | `Error_that_can_be_interactive | `Quit_with_error ->
          finish () >>= fun () -> Asynchronous_result.die 4 in
    protect f ~name:"Main-function"
    >>= fun () ->
    Dbg.e EF.(wf "Finiching Interactive_test.run_test") ;
    return ()
end
