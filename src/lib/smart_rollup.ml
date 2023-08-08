open Internal_pervasives

type mode = [ `Operator | `Batcher | `Observer | `Maintenance | `Accuser ]

type t = {
  id : string;
  level : int;
  kernel : [ `Tx | `Evm | `Custom of string * string * string ];
  node_mode : mode;
  node_init_options : string list;
  node_run_options : string list;
  node : Tezos_executable.t;
  client : Tezos_executable.t;
  installer : Tezos_executable.t;
  evm_proxy_server : Tezos_executable.t;
}

let make_path ~state p = Paths.root state // sprintf "smart-rollup" // p

let make_dir state p =
  Running_processes.run_successful_cmdf state "mkdir -p %s" p

module Node = struct
  (* The mode of the smart-rollup node. *)

  let mode_string = function
    | `Operator -> "operator"
    | `Batcher -> "batcher"
    | `Observer -> "observer"
    | `Maintenance -> "maintenance"
    | `Accuser -> "accuser"

  (* A type for the smart-rollup node config. *)
  type config = {
    node_id : string;
    mode : mode;
    operator_addr : string;
    rpc_addr : string option;
    rpc_port : int option;
    endpoint : int option;
    protocol : Tezos_protocol.Protocol_kind.t;
    exec : Tezos_executable.t;
    client : Tezos_client.t;
    smart_rollup : t;
  }

  type t = config

  let make_config ~smart_rollup ?node_id ~mode ~operator_addr ?rpc_addr
      ?rpc_port ?endpoint ~protocol ~exec ~client () : config =
    let node_id =
      sprintf "%s-smart-rollup-%s-node-%s" smart_rollup.id (mode_string mode)
        (Option.value node_id ~default:"000")
    in
    {
      node_id;
      mode;
      operator_addr;
      rpc_addr;
      rpc_port;
      endpoint;
      protocol;
      exec;
      client;
      smart_rollup;
    }

  (* smart-rollup node directory. *)
  let node_dir state node p = make_path ~state (sprintf "%s" node.node_id // p)
  let data_dir state node = node_dir state node "data-dir"
  let reveal_data_dir state node = data_dir state node // "wasm_2_0_0"

  (* octez-smart-rollup node command.*)
  let call state ~config command =
    let open Tezos_executable.Make_cli in
    let client_dir = Tezos_client.base_dir ~state config.client in
    Tezos_executable.call state config.exec ~protocol_kind:config.protocol
      ~path:(node_dir state config "exec")
      (Option.value_map config.endpoint ~default:[] ~f:(fun e ->
           opt "endpoint" (sprintf "http://localhost:%d" e))
      (* The base-dir is the octez_client directory. *)
      @ opt "base-dir" client_dir
      @ command)

  let int_run_options state ~config =
    let open Tezos_executable.Make_cli in
    (* The directory where the node config is stored. *)
    opt "data-dir" (data_dir state config)
    @ Option.value_map config.rpc_addr
        ~f:(fun a -> opt "rpc-addr" (sprintf "%s" a))
        ~default:[]
    @ Option.value_map config.rpc_port
        ~f:(fun p -> opt "rpc-port" (sprintf "%d" p))
        ~default:[]

  let custom_opt options : string list =
    let open Tezos_executable.Make_cli in
    List.concat_map options ~f:(fun s ->
        match String.lsplit2 ~on:'=' s with
        | None -> flag s
        | Some (o, v) -> opt o v)

  (* Command to initiate a smart-rollup node [config] *)
  let init state config soru_addr =
    let options : string list =
      custom_opt config.smart_rollup.node_init_options
    in

    call state ~config
      ([
         "init";
         mode_string config.mode;
         "config";
         "for";
         soru_addr;
         "with";
         "operators";
         config.operator_addr;
       ]
      @ int_run_options state ~config
      @ options)

  let run state config soru_addr =
    let options : string list =
      custom_opt config.smart_rollup.node_run_options
    in
    call state ~config
      ([
         "run";
         mode_string config.mode;
         "for";
         soru_addr;
         "with";
         "operators";
         config.operator_addr;
       ]
      @ int_run_options state ~config
      @ options)

  (* Start a running smart-rollup node. *)
  let start state config soru_addr =
    Running_processes.Process.genspio config.node_id
      (Genspio.EDSL.check_sequence ~verbosity:`Output_all
         [
           ("init smart-rollup-node", init state config soru_addr);
           ("run smart-rollup-node", run state config soru_addr);
         ])

  (* Pause until the node is responsive.*)
  let wait_for_responce state ~config =
    let try_once () =
      sprintf "curl http://localhost:%d/block/global/block/head"
        (Option.value_exn config.rpc_port)
      |> fun call ->
      Running_processes.run_cmdf ~id_prefix:"smart-rollup-node" state "%s" call
      >>= fun res -> return Poly.(res#status = Unix.WEXITED 0)
    in
    let attempts = 5 in
    let rec loop nth =
      if nth >= attempts then
        Process_result.Error.wrong_behavior
          ~attach:
            [
              ( "node-id",
                (`String_value config.node_id : Attached_result.content) );
            ]
          "Bootstrapping failed %d times." nth
      else
        try_once () >>= function
        | true -> return ()
        | false ->
            System.sleep Float.(of_int nth * 1.0) >>= fun () -> loop (nth + 1)
    in
    loop 1
end

module Evm_proxy_server = struct
  type config = {
    id : string;
    rpc_addr : string;
    rpc_port : int;
    rollup_node_endpoint : int;
    exec : Tezos_executable.t;
    protocol : Tezos_protocol.Protocol_kind.t;
    smart_rollup : t;
  }

  type t = config

  let make ~smart_rollup ?(id = "evm-proxy-server") ?(rpc_addr = "127.0.0.1")
      ~rpc_port ~rollup_node_endpoint ~exec ~protocol () : t =
    {
      id;
      rpc_addr;
      rpc_port;
      rollup_node_endpoint;
      exec;
      protocol;
      smart_rollup;
    }

  let server_dir state id p = make_path ~state (sprintf "%s" id // p)

  let call state ~config ~command =
    let open Tezos_executable.Make_cli in
    Tezos_executable.call state config.exec ~protocol_kind:config.protocol
      ~path:(server_dir state config.id "exec")
      (command
      @ opt "rollup-node-endpoint"
          (sprintf "http://localhost:%d" config.rollup_node_endpoint)
      @ opt "rpc-addr" config.rpc_addr
      @ opt "rpc-port" (Int.to_string config.rpc_port))

  (* Start a running evm-proxy-server. *)
  let run state config =
    Running_processes.Process.genspio config.id
      (call state ~config ~command:[ "run" ])
end

module Kernel = struct
  type config = {
    name : string;
    installer_kernel : string;
    reveal_data_dir : string;
    exec : Tezos_executable.t;
    smart_rollup : t;
    node : Node.t;
  }

  (* smart-rollup kernel dirctory *)
  let kernel_dir ~state smart_rollup p =
    make_path ~state (sprintf "%s-kernel" smart_rollup.id // p)

  let make_config state ~smart_rollup ~node : config =
    let name = smart_rollup.id in
    let installer_kernel =
      kernel_dir ~state smart_rollup (sprintf "%s-installer.hex" name)
    in
    let reveal_data_dir = Node.reveal_data_dir state node in
    let exec = smart_rollup.installer in
    { name; installer_kernel; reveal_data_dir; exec; smart_rollup; node }

  (* The cli arguments for the octez_client smart rollup originatation. *)
  type cli_args = { kind : string; michelson_type : string; hex : string }

  let make_args ~kind ~michelson_type ~hex : cli_args =
    { kind; michelson_type; hex }

  (* Write wasm byte code to file  *)
  let write_wasm ~state ~smart_rollup ~filename ~content =
    let path = kernel_dir ~state smart_rollup filename in
    System.write_file state path ~content >>= fun () -> return path

  (* check the extension of user provided kernel. *)
  let check_extension path =
    let open Stdlib.Filename in
    match extension path with
    | ".hex" -> `Hex path
    | ".wasm" -> `Wasm path
    | _ -> raise (Invalid_argument (sprintf "Wrong file type at: %S" path))

  (* Build the installer_kernel and preimage with the smart_rollup_installer executable. *)
  let installer_create state ~exec ~path ~output ~preimages_dir =
    Running_processes.run_successful_cmdf state
      "%s get-reveal-installer --upgrade-to %s --output %s --preimages-dir %s"
      (Tezos_executable.kind_string exec)
      path output preimages_dir

  (* Build the kernel with the smart_rollup_installer executable. *)
  let build state ~smart_rollup ~node : (cli_args, _) Asynchronous_result.t =
    let config = make_config state ~smart_rollup ~node in
    (* make dierctories *)
    make_dir state (kernel_dir ~state smart_rollup "") >>= fun _ ->
    make_dir state config.reveal_data_dir >>= fun _ ->
    begin
      (* Decided which kernel will be originated. *)
      match smart_rollup.kernel with
      | `Custom kernel -> return kernel
      | `Evm ->
          write_wasm ~state ~smart_rollup ~filename:"evm_kernel.wasm"
            ~content:Smart_rollup_kernels.evm_kernel
          >>= fun path ->
          return ("wasm_2_0_0", "pair (pair bytes (ticket unit)) nat", path)
      | `Tx ->
          write_wasm ~state ~smart_rollup ~filename:"tx_kernel.wasm"
            ~content:Smart_rollup_kernels.tx_kernel
          >>= fun path ->
          return ("wasm_2_0_0", "pair string (ticket string)", path)
    end
    >>= fun (kind, michelson_type, kernel_path) ->
    let cli_args h =
      h >>= fun hex -> return (make_args ~kind ~michelson_type ~hex)
    in
    let content path = System.read_file state path in
    System.size state kernel_path >>= fun s ->
    if s > 24 * 1048 then
      (* wasm files larger that 24kB are passed to installer_create. We can't do anything with large .hex files *)
      match check_extension kernel_path with
      | `Hex p ->
          raise
            (Invalid_argument
               (sprintf
                  "%s is over the max operation size (24kB). Try a .wasm file \n"
                  p))
      | `Wasm _ ->
          installer_create state ~exec:config.exec.kind ~path:kernel_path
            ~output:config.installer_kernel
            ~preimages_dir:config.reveal_data_dir
          >>= fun _ -> cli_args (content config.installer_kernel)
    else
      match check_extension kernel_path with
      | `Hex p -> cli_args (content p)
      | `Wasm p ->
          content p >>= fun was ->
          cli_args (return Hex.(was |> of_string |> show))
end

(* octez-client call to originate a smart-rollup. *)
let originate state ~client ~account ~kernel () =
  let open Kernel in
  Tezos_client.successful_client_cmd state ~client
    [
      "originate";
      "smart";
      "rollup";
      "from";
      account;
      "of";
      "kind";
      kernel.kind;
      "of";
      "type";
      kernel.michelson_type;
      "with";
      "kernel";
      kernel.hex;
      "--burn-cap";
      "999";
    ]

(* octez-client call confirming an operation. *)
let confirm state ~client ~confirmations ~operation_hash () =
  Tezos_client.successful_client_cmd state ~client
    [
      "wait";
      "for";
      operation_hash;
      "to";
      "be";
      "included";
      "--confirmations";
      Int.to_string confirmations;
    ]

(* A type for octez client output from a smart-rollup origination. *)
type origination_result = {
  operation_hash : string;
  address : string;
  origination_account : string;
  out : string list;
}

(* Parse octez-client output of smart-rollup origination. *)
let parse_origination ~lines =
  let rec prefix_from_list ~prefix = function
    | [] -> None
    | x :: xs ->
        if not (String.is_prefix x ~prefix) then prefix_from_list ~prefix xs
        else
          Some
            (String.lstrip
               (String.chop_prefix x ~prefix |> Option.value ~default:x))
  in
  let l = List.map lines ~f:String.lstrip in
  (* This is parsing the unicode output from the octez-client *)
  Option.(
    prefix_from_list ~prefix:"Operation hash is" l >>= fun op ->
    String.chop_prefix ~prefix:"'" op >>= fun suf ->
    String.chop_suffix ~suffix:"'" suf >>= fun operation_hash ->
    prefix_from_list ~prefix:"From:" l >>= fun origination_account ->
    prefix_from_list ~prefix:"Address:" l >>= fun address ->
    return { operation_hash; address; origination_account; out = lines })

let originate_and_confirm state ~client ~account ~kernel ~confirmations () =
  originate state ~client ~account ~kernel () >>= fun res ->
  return (parse_origination ~lines:res#out) >>= fun origination_result ->
  match origination_result with
  | None ->
      System_error.fail_fatalf
        "smart_rollup.originate_and_confirm - failed to parse output."
  | Some origination_result ->
      confirm state ~client ~confirmations
        ~operation_hash:origination_result.operation_hash ()
      >>= fun conf -> return (origination_result, conf)

(* A list of smart rollup executables. *)
let executables ({ client; node; installer; _ } : t) =
  [ client; node; installer ]

let run state ~smart_rollup ~protocol ~keys_and_daemons ~nodes ~base_port =
  match smart_rollup with
  | None -> return ()
  | Some soru -> begin
      List.hd_exn keys_and_daemons |> return >>= fun (_, _, client, _, _) ->
      let add_keys state client account =
        (* Import keys of account*)
        let name, pubkey_hash, priv_key =
          Tezos_protocol.Account.
            (name account, pubkey_hash account, private_key account)
        in
        Tezos_client.import_secret_key state client ~name ~key:priv_key
        >>= fun () -> return (name, pubkey_hash, priv_key)
      in
      add_keys state client (Tezos_protocol.soru_node_operator protocol)
      >>= fun (operator_name, operator_hash, _) ->
      (* Configure smart-rollup node. *)
      let rollup_node_port = Test_scenario.Unix_port.(next_port nodes) in
      Node.make_config ~smart_rollup:soru ~mode:soru.node_mode
        ~operator_addr:operator_hash ~rpc_addr:"0.0.0.0"
        ~rpc_port:rollup_node_port ~endpoint:base_port ~protocol:protocol.kind
        ~exec:soru.node ~client ()
      |> return
      >>= fun soru_node ->
      Kernel.build state ~smart_rollup:soru ~node:soru_node >>= fun kernel ->
      (* Originate smart-rollup.*)
      originate_and_confirm state ~client ~kernel ~account:operator_name
        ~confirmations:1 ()
      >>= fun (origination_res, _) ->
      (* Start smart-rollup node. *)
      Running_processes.start state
        Node.(start state soru_node origination_res.address)
      >>= fun { process = _; lwt = _ } ->
      return () >>= fun _ ->
      begin
        (* If using one of Flextesa preconfigured kerenel, originiate the L1 helper contracts. *)
        match soru.kernel with
        | `Evm ->
            (* Imort admin account and client for evm-rollup FA1.2 contracts. *)
            let admin = Tezos_protocol.contract_admin protocol in
            add_keys state client admin >>= fun (admin_name, admin_hash, _) ->
            (* Write the fa12 to file. It is too large to pass to cmdline as a string. *)
            let sc_dir = make_path ~state "l1-smart-contracts" in
            make_dir state sc_dir >>= fun _ ->
            let fa12_dest = sc_dir // "fa12.tz" in
            System.write_file state fa12_dest
              ~content:Sandbox_smart_contracts.fa12
            >>= fun () ->
            (* Originate FA1.2 token contract. *)
            let fa12_init =
              let elt =
                let pub_keys =
                  Tezos_protocol.bootstrap_accounts protocol
                  |> List.map ~f:(fun a -> Tezos_protocol.Account.pubkey_hash a)
                  |> List.sort ~compare:String.compare
                in
                List.map pub_keys ~f:(fun pk ->
                    let bal = 10_000_000_000L in
                    Fmt.str "Elt %S (Pair %Ld {})" pk bal)
                |> String.concat ~sep:"; "
              in
              Fmt.str "(Pair { %s } (Pair %S (Pair False 1)))" elt admin_hash
            in
            Smart_contract.originate_smart_contract state ~client
              ~account:admin_name
              { name = "fa12"; michelson = fa12_dest; init_storage = fa12_init }
            >>= fun fa12_contract_addr ->
            List.max_elt protocol.time_between_blocks ~compare:Int.compare
            |> Option.value_exn |> Float.of_int |> System.sleep
            >>= fun () ->
            let bridge_init =
              Fmt.str "(Pair (Pair %S %S) (Some %S))" admin_hash
                fa12_contract_addr origination_res.address
            in

            Smart_contract.(
              originate_smart_contract state ~client ~account:admin_name
                {
                  name = "evm-bridge";
                  michelson = Sandbox_smart_contracts.evm_bridge;
                  init_storage = bridge_init;
                })
            >>= fun evm_bridge_address ->
            (* Wait for the rollup node to bootstrap. *)
            Node.wait_for_responce state ~config:soru_node >>= fun () ->
            (* Start the evm-proxy-sever. *)
            let evm_proxy_port = Test_scenario.Unix_port.(next_port nodes) in
            Evm_proxy_server.make ~smart_rollup:soru ~rpc_port:evm_proxy_port
              ~rollup_node_endpoint:rollup_node_port ~exec:soru.evm_proxy_server
              ~protocol:protocol.kind ()
            |> return
            >>= fun evm_proxy_server ->
            Running_processes.start state
              (Evm_proxy_server.run state evm_proxy_server)
            >>= fun { process = _; lwt = _ } ->
            return () >>= fun _ ->
            (* Print evm-proxy-server rpc port.*)
            EF.
              [
                desc
                  (af "evm-proxy-server is listening on")
                  (af "rpc_port: `%d`" evm_proxy_server.rpc_port);
                desc
                  (af "FA1.2 contract address:")
                  (af "`%s`" fa12_contract_addr);
                desc
                  (af "EVM bridge contract address:")
                  (af "`%s`" evm_bridge_address);
              ]
            |> return
        | `Tx ->
            (* Originate mint_and_deposit_to_rollup contract. *)
            Smart_contract.(
              originate_smart_contract state ~client ~account:operator_name
                {
                  name = "mint_and_deposit_to_rollup";
                  michelson = Sandbox_smart_contracts.mint_and_deposit_to_rollup;
                  init_storage = "Unit";
                })
            >>= fun mint_addr ->
            (* Pring contract address. *)
            EF.
              [
                desc
                  (af "mint_and_deposit_to_rollup contract address:")
                  (af "`%s`" mint_addr);
              ]
            |> return
        | _ -> return []
      end
      >>= fun included_rollups ->
      (* Print smart-rollup info. *)
      Console.say state
        EF.(
          desc_list
            (haf "%S smart optimistic rollup is ready:" soru.id)
            ([
               desc (af "Address:") (af "`%s`" origination_res.address);
               desc
                 (af "A rollup node in %S mode is listening on"
                    (Node.mode_string soru_node.mode))
                 (af "rpc_port: `%d`"
                    (Option.value_exn
                       ?message:
                         (Some
                            "Failed to get rpc port for the smart rollup node.")
                       soru_node.rpc_port));
             ]
            @ included_rollups))
    end

let cmdliner_term state () =
  let open Cmdliner in
  let open Term in
  let docs =
    Manpage_builder.section state ~rank:2 ~name:"SMART OPTIMISTIC ROLLUPS"
  in
  let extra_doc =
    Fmt.str " for the smart optimistic rollup (requires --start-smart-rollup)."
  in
  let parce_rollup_arg arg =
    match String.split arg ~on:':' with
    | [ "none" ] -> `No_rollup
    | [ "tx" ] -> `Tx
    | [ "evm" ] -> `Evm
    | [ "custom"; kind; michelson_type; path ] ->
        `Custom (kind, michelson_type, path)
    | other -> Fmt.failwith "Nope: %a" Fmt.Dump.(list string) other
  in
  let custom_id (_, _, p) =
    match Kernel.check_extension p with
    | `Hex p | `Wasm p -> Stdlib.Filename.(basename p |> chop_extension)
  in
  const
    (fun
      start
      soru
      level
      custom_kernel
      node_mode
      node_init_options
      node_run_options
      node
      client
      installer
      evm_proxy_server
    ->
      let check_options l =
        (* make sure users follow the rules regarding allowable options. *)
        let check s =
          if
            List.exists [ "data-dir"; "rpc-addr"; "rpc-port" ] ~f:(fun e ->
                String.is_prefix ~prefix:e s)
          then
            `Error
              (Fmt.str
                 "This option is set by Flextesa. It cannot by changed. %S" s)
          else `Ok s
        in
        List.map l ~f:(fun e ->
            match check e with `Ok s -> s | `Error s -> failwith s)
      in
      let make id kernel =
        {
          id;
          level;
          kernel;
          node_mode;
          node_init_options = check_options node_init_options;
          node_run_options = check_options node_run_options;
          node;
          client;
          installer;
          evm_proxy_server;
        }
      in
      match parce_rollup_arg start with
      | `Tx -> Some (make "tx" `Tx)
      | `Evm -> Some (make "evm" `Evm)
      | `Custom args -> Some (make (custom_id args) (`Custom args))
      | `No_rollup -> (
          match soru with
          (* --smart-rollup is depricated in favor of of --start-smart-rollup 2023-06-23 *)
          | true -> begin
              match custom_kernel with
              | None ->
                  Some (make "tx" `Tx)
                  (* without --custom-kernel --smart-rollup defaults to the tx rollup. *)
              | Some args ->
                  Some
                    (make (custom_id args)
                       (`Custom (Option.value_exn custom_kernel)))
            end
          | false -> None))
  $ Arg.(
      value
      & opt string "none"
          (info [ "start-smart-rollup" ]
             ~doc:
               "Start an optimistic smart rollup with one of the following \
                options: `tx` starts a transaction smart rollup (tx_kernel). \
                `evm` starts an EVM smart rollup (Octez evem_kernel). \
                `custom:KIND:TYPE:PATH` starts an smart rollup with a user \
                provided kernel. "
             ~docs ~docv:"OPTION"))
  $ Arg.(
      value
      & flag
          (info [ "smart-rollup" ] ~deprecated:"use --start-smart-rollup OPTION"
             ~doc:"Use --start-smart-rollup" ~docs))
  $ Arg.(
      value
      & opt int 5
          (info
             [ "smart-rollup-start-level" ]
             ~doc:(sprintf "Origination `level` %s" extra_doc)
             ~docs ~docv:"LEVEL"))
  $ Arg.(
      value
      & opt (some (t3 ~sep:':' string string string)) None
      & info [ "custom-kernel" ] ~docs
          ~deprecated:"use --start-smart-rollup custom:KIND:TYPE:PATH"
          ~doc:"Use --start-smart-rollup custom:KIND:TYPE:PATH"
          ~docv:"KIND:TYPE:PATH")
  $ Arg.(
      value
      & opt
          (enum
             [
               ("operator", `Operator);
               ("batcher", `Batcher);
               ("observer", `Observer);
               ("maintenance", `Maintenance);
               ("accuser", `Accuser);
             ])
          `Operator
      & info ~docs
          [ "smart-rollup-node-mode" ]
          ~doc:(sprintf "Set the rollup node's `mode`%s" extra_doc))
  $ Arg.(
      value
      & opt (list ~sep:' ' string) []
      & info ~docs
          [ "smart-rollup-node-init-with" ]
          ~doc:
            "Initiate the smart-rollup-node config with the provided `flag` or \
             `option=value`. Use quotes to provide multiple flags and options \
             separated by spaces. (e.g. \"OPT1=VAL1 FLAG OPT2=VAL2\"). The \
             following options aren't available: data-dir, rpc-addr, rpc-port."
          ~docv:"FLAG|OPTION=VALUE")
  $ Arg.(
      value
      & opt (list ~sep:' ' string) []
      & info ~docs
          [ "smart-rollup-node-run-with" ]
          ~doc:
            "Run the smart-rollup-node with the provided `flag` or \
             `option=value`. Use quotes to provide multiple flags and options \
             separated by spaces. (e.g. \"OPT1=VAL1 FLAG OPT2=VAL2\") The \
             following options aren't available: data-dir, rpc-addr, rpc-port."
          ~docv:"FLAG|OPTION=VALUE")
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_node
      ~prefix:"octez"
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_client
      ~prefix:"octez"
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_installer
      ~prefix:"octez"
  $ Tezos_executable.cli_term ~extra_doc state `Evm_proxy_server ~prefix:"octez"
