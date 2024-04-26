open Internal_pervasives

type mode = [ `Operator | `Batcher | `Observer | `Maintenance | `Accuser ]

type t = {
  id : string;
  level : int;
  kernel : [ `Tx | `Evm | `Custom of string * string * string ];
  setup_file : string option;
  node_mode : mode;
  node_init_options : string list;
  node_run_options : string list;
  node : Mavryk_executable.t;
  installer : Mavryk_executable.t;
  evm_node : Mavryk_executable.t;
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
    rpc_port : int;
    endpoint : int option;
    protocol : Mavryk_protocol.Protocol_kind.t;
    exec : Mavryk_executable.t;
    client : Mavryk_client.t;
    smart_rollup : t;
  }

  type t = config

  let make_config ~smart_rollup ?node_id ~mode ~operator_addr ?rpc_addr
      ~rpc_port ?endpoint ~protocol ~exec ~client () : config =
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

  (* mavkit-smart-rollup node command.*)
  let call state ~config command =
    let open Mavryk_executable.Make_cli in
    let client_dir = Mavryk_client.base_dir ~state config.client in
    Mavryk_executable.call state config.exec ~protocol_kind:config.protocol
      ~path:(node_dir state config "exec")
      (Option.value_map config.endpoint ~default:[] ~f:(fun e ->
           opt "endpoint" (sprintf "http://localhost:%d" e))
      (* The base-dir is the mavkit_client directory. *)
      @ opt "base-dir" client_dir
      @ command)

  let int_run_options state ~config =
    let open Mavryk_executable.Make_cli in
    (* The directory where the node config is stored. *)
    opt "data-dir" (data_dir state config)
    @ Option.value_map config.rpc_addr
        ~f:(fun a -> opt "rpc-addr" (sprintf "%s" a))
        ~default:[]
    @ opt "rpc-port" (Int.to_string config.rpc_port)

  let custom_opt options : string list =
    let open Mavryk_executable.Make_cli in
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
      sprintf "curl http://localhost:%d/block/global/block/head" config.rpc_port
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

module Evm_node = struct
  type config = {
    id : string;
    rpc_addr : string;
    rpc_port : int;
    rollup_node_endpoint : string;
    exec : Mavryk_executable.t;
    protocol : Mavryk_protocol.Protocol_kind.t;
    smart_rollup : t;
  }

  let make_config ~smart_rollup ?(id = "evm-node") ?(rpc_addr = "0.0.0.0")
      ~rpc_port ~rollup_node_endpoint ~exec ~protocol () : config =
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
  let data_dir state config = server_dir state config.id "data-dir"

  let call state ~config ~command =
    let open Mavryk_executable.Make_cli in
    Mavryk_executable.call state config.exec ~protocol_kind:config.protocol
      ~path:(server_dir state config.id "exec")
      (command
      @ opt "rpc-addr" config.rpc_addr
      @ opt "rpc-port" (Int.to_string config.rpc_port)
      @ opt "data-dir" (data_dir state config))

  (* Start a running mavkit-evm-node. *)
  let run state config =
    make_dir state (data_dir state config) >>= fun _ ->
    Running_processes.Process.genspio config.id
      (Genspio.EDSL.check_sequence ~verbosity:`Output_all
         [
           ( "run evm-node",
             call state ~config
               ~command:
                 [
                   "run";
                   "proxy";
                   "with";
                   "endpoint";
                   config.rollup_node_endpoint;
                 ] );
         ])
    |> return
end

module Kernel = struct
  type config = {
    name : string;
    installer_kernel : string;
    reveal_data_dir : string;
    setup_file : string option;
    exec : Mavryk_executable.t;
    smart_rollup : t;
    node : Node.t;
  }

  (* smart-rollup kernel directory *)
  let kernel_dir ~state smart_rollup p =
    make_path ~state (sprintf "%s-kernel" smart_rollup.id // p)

  let make_config state ~smart_rollup ~node : config =
    let name = smart_rollup.id in
    let installer_kernel =
      kernel_dir ~state smart_rollup (sprintf "%s-installer.hex" name)
    in
    let reveal_data_dir = Node.reveal_data_dir state node in
    {
      name;
      installer_kernel;
      reveal_data_dir;
      setup_file = smart_rollup.setup_file;
      exec = smart_rollup.installer;
      smart_rollup;
      node;
    }

  (* The cli arguments for the mavkit_client smart rollup origination. *)
  type cli_args = {
    name : string;
    kind : string;
    michelson_type : string;
    hex : string;
  }

  let make_args ~name ~kind ~michelson_type ~hex : cli_args =
    { name; kind; michelson_type; hex }

  (* Write wasm byte code to file.  *)
  let write_wasm ~state ~smart_rollup ~filename ~content =
    let path = kernel_dir ~state smart_rollup filename in
    System.write_file state path ~content >>= fun () -> return path

  (* Write the evm-kernel setup-file for the smart-rollup-installer. *)
  let evm_setup_file ~smart_rollup ~bridge_addr ?(chain_id = 123123) state =
    let content =
      let addr = Hex.(of_string bridge_addr |> show) in
      let chain_id_encode =
        Fmt.str "%x" chain_id |> fun s ->
        let init_list = String.to_list s in
        let rec reverse_bytes acc = function
          | [] -> acc
          | _ :: [] ->
              reverse_bytes [] ('0' :: init_list)
              (* If List.length list is odd, start over and append a zero. *)
          | x :: y :: z -> reverse_bytes (x :: y :: acc) z
        in
        reverse_bytes [] init_list |> String.of_char_list
      in
      Fmt.str
        "{instructions: [set: {value: %s, to: /evm/ticketer}, set: {value: %s \
         , to: /evm/chain_id}]}"
        addr chain_id_encode
    in
    let path = kernel_dir ~state smart_rollup "setup-file.yaml" in
    make_dir state (Stdlib.Filename.dirname path) >>= fun _ ->
    System.write_file state path ~content >>= fun () -> return path

  (* check the extension of user provided kernel. *)
  let check_extension path =
    let open Stdlib.Filename in
    match extension path with
    | ".hex" -> `Hex path
    | ".wasm" -> `Wasm path
    | _ -> raise (Invalid_argument (sprintf "Wrong file type at: %S" path))

  (* Build the installer_kernel and preimage with the smart_rollup_installer executable. *)
  let installer_create ?setup_file state ~exec ~path ~output ~preimages_dir =
    let options =
      let open Mavryk_executable.Make_cli in
      opt "upgrade-to" path @ opt "output" output
      @ opt "preimages-dir" preimages_dir
      @ Option.value_map setup_file ~default:[] ~f:(fun setup_file ->
            opt "setup-file" setup_file)
      |> String.concat ~sep:" "
    in
    Running_processes.run_successful_cmdf state "%s get-reveal-installer %s"
      (Mavryk_executable.kind_string exec)
      options

  (* Build the kernel with the smart_rollup_installer executable. *)
  let build state ~smart_rollup ~node : (cli_args, _) Asynchronous_result.t =
    let config = make_config state ~smart_rollup ~node in
    (* make directories *)
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
          return
            ( "wasm_2_0_0",
              "or (or (pair bytes (ticket (pair nat (option bytes)))) bytes) \
               bytes",
              path )
      | `Tx ->
          write_wasm ~state ~smart_rollup ~filename:"tx_kernel.wasm"
            ~content:Smart_rollup_kernels.tx_kernel
          >>= fun path ->
          return ("wasm_2_0_0", "pair string (ticket string)", path)
    end
    >>= fun (kind, michelson_type, kernel_path) ->
    let cli_args h =
      h >>= fun hex ->
      return (make_args ~name:config.name ~kind ~michelson_type ~hex)
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
          installer_create state ?setup_file:config.setup_file
            ~exec:config.exec.kind ~path:kernel_path
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

(* mavkit-client call to originate a smart-rollup. *)
let originate state ~client ~account ~kernel () =
  let open Kernel in
  Mavryk_client.successful_client_cmd state ~client
    [
      "originate";
      "smart";
      "rollup";
      kernel.name;
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

(* mavkit-client call confirming an operation. *)
let confirm state ~client ~confirmations ~operation_hash () =
  Mavryk_client.successful_client_cmd state ~client
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

(* A type for mavkit client output from a smart-rollup origination. *)
type origination_result = {
  operation_hash : string;
  address : string;
  origination_account : string;
  out : string list;
}

(* Parse mavkit-client output of smart-rollup origination. *)
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
  (* This is parsing the unicode output from the mavkit-client *)
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
let executables ({ node; installer; _ } : t) = [ node; installer ]

let run state ~smart_rollup ~protocol ~keys_and_daemons ~nodes ~base_port =
  match smart_rollup with
  | None -> return ()
  | Some soru -> (
      List.hd_exn keys_and_daemons |> return >>= fun (_, _, client, _, _) ->
      (* Create admin account for rollup operations *)
      let admin_name, admin_hash, admin_secret =
        let acc = Mavryk_protocol.Account.of_name "rollup-admin" in
        Mavryk_protocol.Account.(name acc, pubkey_hash acc, private_key acc)
      in
      (* Import the rollup-admin to the client. *)
      Mavryk_client.Keyed.initialize state
        { client; key_name = admin_name; secret_key = admin_secret }
      >>= fun _ ->
      (* Import the dictator keys to the client. *)
      Mavryk_client.Keyed.initialize state
        {
          client;
          key_name = Mavryk_protocol.dictator_name protocol;
          secret_key = Mavryk_protocol.dictator_secret_key protocol;
        }
      >>= fun _ ->
      (* Fund the rollup-admi account. *)
      Mavryk_client.successful_client_cmd state ~wait:"1" ~client
        [
          "transfer";
          Int.to_string 20_000;
          "from";
          "dictator-default";
          "to";
          admin_name;
          "--burn-cap";
          "1";
        ]
      >>= fun _ ->
      (* The next three functions are in step order for basic rollup with an
         operating node: 1) Configure node 2) Originate rollup 3) Start node. The
         various kernels below will require additional steps. *)
      (* Configure smart-rollup node. *)
      let soru_node_config soru admin_hash base_port protocol =
        let rollup_node_port = Test_scenario.Unix_port.(next_port nodes) in
        Node.make_config ~smart_rollup:soru ~mode:soru.node_mode
          ~operator_addr:admin_hash ~rpc_addr:"0.0.0.0"
          ~rpc_port:rollup_node_port ~endpoint:base_port
          ~protocol:protocol.Mavryk_protocol.kind ~exec:soru.node ~client ()
        |> return
      in
      (* Originate smart-rollup. *)
      let originate_rollup state soru soru_node client admin_name =
        Kernel.build state ~smart_rollup:soru ~node:soru_node >>= fun kernel ->
        (* Originate smart-rollup.*)
        originate_and_confirm state ~client ~kernel ~account:admin_name
          ~confirmations:1 ()
      in
      (* Start smart-rollup node. *)
      let start_rollup_node state soru_node rollup_origination_res =
        Running_processes.start state
          Node.(start state soru_node rollup_origination_res.address)
        >>= fun { process = _; lwt = _ } -> return () (* >>= fun _ -> *)
      in
      (* Print smart-rollup info. *)
      let print_info rollup_origination_res soru_node also =
        Console.say state
          EF.(
            desc_list
              (haf "%S smart optimistic rollup is ready:" soru.id)
              ([
                 desc (af "Address:") (af "`%s`" rollup_origination_res.address);
                 desc
                   (af "A rollup node in %S mode is listening on"
                      (Node.mode_string soru_node.Node.mode))
                   (af "rpc_port: `%d`" soru_node.Node.rpc_port);
               ]
              @ also))
      in
      match soru.kernel with
      | `Evm ->
          (* Originate exchanger contract. *)
          Smart_contract.originate_smart_contract state ~client ~wait:"1"
            ~account:admin_name
            {
              name = "exchanger";
              michelson = Sandbox_smart_contracts.exchanger;
              init_storage = "Unit";
            }
          >>= fun exchanger_contract_addr ->
          (* Originate the bridge contract. *)
          let bridge_init = Fmt.str "(Pair %S  None)" exchanger_contract_addr in
          Smart_contract.(
            originate_smart_contract state ~client ~account:admin_name ~wait:"1"
              {
                name = "evm-bridge";
                michelson = Sandbox_smart_contracts.evm_bridge;
                init_storage = bridge_init;
              })
          >>= fun evm_bridge_address ->
          (* configure rollup node *)
          soru_node_config soru admin_hash base_port protocol
          >>= fun soru_node ->
          (* Originate rollup with setup-file *)
          Kernel.evm_setup_file state ~smart_rollup:soru
            ~bridge_addr:exchanger_contract_addr
          >>= fun evm_setup_file ->
          originate_rollup state
            { soru with setup_file = Some evm_setup_file }
            soru_node client admin_hash
          >>= fun (origination_result, _) ->
          (* Start rollup node*)
          start_rollup_node state soru_node origination_result >>= fun () ->
          (* Wait for the rollup node to bootstrap. *)
          Node.wait_for_responce state ~config:soru_node >>= fun () ->
          (* Start the mavkit-evm-node. *)
          let evm_node_port = Test_scenario.Unix_port.(next_port nodes) in
          Evm_node.make_config ~smart_rollup:soru ~rpc_port:evm_node_port
            ~rollup_node_endpoint:
              (Fmt.str "http://127.0.0.1:%d" soru_node.rpc_port)
            ~exec:soru.evm_node ~protocol:protocol.kind ()
          |> return
          >>= fun evm_node ->
          Evm_node.run state evm_node >>= fun process ->
          Running_processes.start state process
          >>= fun { process = _; lwt = _ } ->
          return () >>= fun _ ->
          (* Print rollup info *)
          EF.
            [
              desc
                (af "mavkit-evm-node is listening on")
                (af "rpc_port: `%d`" evm_node.rpc_port);
              desc
                (af "Exchanger contract address:")
                (af "`%s`" exchanger_contract_addr);
              desc
                (af "EVM bridge contract address:")
                (af "`%s`" evm_bridge_address);
            ]
          |> return
          >>= fun info -> print_info origination_result soru_node info
      | `Tx ->
          (* Originate mint_and_deposit_to_rollup contract. *)
          Smart_contract.(
            originate_smart_contract state ~client ~account:admin_name
              {
                name = "mint_and_deposit_to_rollup";
                michelson = Sandbox_smart_contracts.mint_and_deposit_to_rollup;
                init_storage = "Unit";
              })
          >>= fun mint_addr ->
          (* configure rollup node *)
          soru_node_config soru admin_hash base_port protocol
          >>= fun soru_node ->
          (*  Originate rollup with setup-file*)
          originate_rollup state soru soru_node client admin_hash
          >>= fun (origination_result, _) ->
          (*  Start rollup node*)
          start_rollup_node state soru_node origination_result >>= fun () ->
          (* Pring contract address. *)
          EF.
            [
              desc
                (af "mint_and_deposit_to_rollup contract address:")
                (af "`%s`" mint_addr);
            ]
          |> return
          >>= fun info -> print_info origination_result soru_node info
      | _ ->
          soru_node_config soru admin_hash base_port protocol
          >>= fun soru_node ->
          (*  Originate rollup *)
          originate_rollup state soru soru_node client admin_hash
          >>= fun (origination_result, _) ->
          (*  Start rollup node*)
          start_rollup_node state soru_node origination_result >>= fun () ->
          (* Pring contract address. *)
          print_info origination_result soru_node [])

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
      setup_file
      soru
      level
      custom_kernel
      node_mode
      node_init_options
      node_run_options
      node
      installer
      evm_node
    ->
      let check_options l =
        (* Make sure there are no reduntant options are passed. *)
        List.iter l ~f:(fun opt ->
            if
              List.exists [ "data-dir"; "rpc-addr"; "rpc-port" ] ~f:(fun e ->
                  String.is_prefix ~prefix:e opt)
            then
              Fmt.failwith
                "This option is set by Flexmasa. It cannot be changed. %S" opt)
      in
      let make id kernel =
        check_options node_init_options;
        check_options node_run_options;
        {
          id;
          setup_file;
          level;
          kernel;
          node_mode;
          node_init_options;
          node_run_options;
          node;
          installer;
          evm_node;
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
        (opt string "none"
           (info [ "start-smart-rollup" ]
              ~doc:
                "Start an optimistic smart rollup with one of the following \
                 options: `tx` starts a transaction smart rollup (tx_kernel). \
                 `evm` starts an EVM smart rollup (Mavkit evem_kernel). \
                 `custom:KIND:TYPE:PATH` starts an smart rollup with a user \
                 provided kernel. "
              ~docs ~docv:"OPTION")))
  $ Arg.(
      value
        (opt (some string) None
           (info [ "kernel-setup-file" ]
              ~doc:
                (sprintf
                   "`Path` to the setup_file passed to \
                    `smart-rollup-installer` %s"
                   extra_doc)
              ~docs ~docv:"PATH")))
  $ Arg.(
      value
        (flag
           (info [ "smart-rollup" ]
              ~deprecated:"use --start-smart-rollup OPTION"
              ~doc:"Use --start-smart-rollup" ~docs)))
  $ Arg.(
      value
        (opt int 5
           (info
              [ "smart-rollup-start-level" ]
              ~doc:(sprintf "Origination `level` %s" extra_doc)
              ~docs ~docv:"LEVEL")))
  $ Arg.(
      value
        (opt
           (some (t3 ~sep:':' string string string))
           None
           (info [ "custom-kernel" ] ~docs
              ~deprecated:"use --start-smart-rollup custom:KIND:TYPE:PATH"
              ~doc:"Use --start-smart-rollup custom:KIND:TYPE:PATH"
              ~docv:"KIND:TYPE:PATH")))
  $ Arg.(
      value
        (opt
           (enum
              [
                ("operator", `Operator);
                ("batcher", `Batcher);
                ("observer", `Observer);
                ("maintenance", `Maintenance);
                ("accuser", `Accuser);
              ])
           `Operator
           (info ~docs
              [ "smart-rollup-node-mode" ]
              ~doc:(sprintf "Set the rollup node's `mode`%s" extra_doc))))
  $ Arg.(
      value
        (opt (list ~sep:' ' string) []
           (info ~docs
              [ "smart-rollup-node-init-with" ]
              ~doc:
                "Initiate the smart-rollup-node config with the provided \
                 `flag` or `option=value`. Use quotes to provide multiple \
                 flags and options separated by spaces. (e.g. \"OPT1=VAL1 FLAG \
                 OPT2=VAL2\"). The following options aren't available: \
                 data-dir, rpc-addr, rpc-port."
              ~docv:"FLAG|OPTION=VALUE")))
  $ Arg.(
      value
        (opt (list ~sep:' ' string) []
           (info ~docs
              [ "smart-rollup-node-run-with" ]
              ~doc:
                "Run the smart-rollup-node with the provided `flag` or \
                 `option=value`. Use quotes to provide multiple flags and \
                 options separated by spaces. (e.g. \"OPT1=VAL1 FLAG \
                 OPT2=VAL2\") The following options aren't available: \
                 data-dir, rpc-addr, rpc-port."
              ~docv:"FLAG|OPTION=VALUE")))
  $ Mavryk_executable.cli_term ~extra_doc state `Smart_rollup_node
      ~prefix:"mavkit"
  $ Mavryk_executable.cli_term ~extra_doc state `Smart_rollup_installer
      ~prefix:"mavkit"
  $ Mavryk_executable.cli_term ~extra_doc state `Evm_node ~prefix:"mavkit"
