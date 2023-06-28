open Internal_pervasives

type mode = [ `Operator | `Batcher | `Observer | `Maintenance | `Accuser ]

type t = {
  id : string;
  level : int;
  kernel : [ `Tx | `Evm | `Custom of string * string * string ];
  node_mode : mode;
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
    let name =
      sprintf "%s-smart-rollup-%s-node-%s" smart_rollup.id (mode_string mode)
        (Option.value node_id ~default:"000")
    in
    {
      node_id = Option.value node_id ~default:name;
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

  (* Command to initiate a smart-rollup node [config] *)
  let init state config soru_addr =
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
      @ int_run_options state ~config)

  (* Start a running smart-rollup node. *)
  let start state config soru_addr =
    Running_processes.Process.genspio config.node_id
      (Genspio.EDSL.check_sequence ~verbosity:`Output_all
         [
           ("init smart-rollup-node", init state config soru_addr);
           ( "run smart-rollup-node",
             call state ~config ([ "run" ] @ int_run_options state ~config) );
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
        | true ->
            Console.say state EF.(haf " %d nth waiting for bootstrap" nth)
            >>= fun () -> return ()
        | false ->
            System.sleep Float.(of_int nth * 1.0) >>= fun () ->
            loop (nth + 1) >>= fun () ->
            Console.say state EF.(haf " %d nth waiting for bootstrap" nth)
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
    let open Caml.Filename in
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
          >>= fun path -> return ("wasm_2_0_0", "unit", path)
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
  | Some soru -> (
      List.hd keys_and_daemons |> function
      | None -> return ()
      | Some (_, _, client, _, _) ->
          (* Initialize operator keys. *)
          let op_acc = Tezos_protocol.soru_node_operator protocol in
          let op_keys =
            let name, priv =
              Tezos_protocol.Account.(name op_acc, private_key op_acc)
            in
            Tezos_client.Keyed.make client ~key_name:name ~secret_key:priv
          in
          Tezos_client.Keyed.initialize state op_keys >>= fun _ ->
          (* Configure smart-rollup node. *)
          let port = Test_scenario.Unix_port.(next_port nodes) in
          Node.make_config ~smart_rollup:soru ~mode:soru.node_mode
            ~operator_addr:op_keys.key_name ~rpc_addr:"0.0.0.0" ~rpc_port:port
            ~endpoint:base_port ~protocol:protocol.kind ~exec:soru.node ~client
            ()
          |> return
          >>= fun soru_node ->
          (* Configure custom Kernel or use default if none. *)
          Kernel.build state ~smart_rollup:soru ~node:soru_node
          >>= fun kernel ->
          (* Originate smart-rollup.*)
          originate_and_confirm state ~client ~kernel ~account:op_keys.key_name
            ~confirmations:1 ()
          >>= fun (origination_res, _confirmation_res) ->
          (* Start smart-rollup node. *)
          Running_processes.start state
            Node.(start state soru_node origination_res.address)
          >>= fun _ ->
          (* Print smart-rollup info. *)
          Console.say state
            EF.(
              desc_list
                (haf "%S smart optimistic rollup is ready:" soru.id)
                [
                  desc (af "Address:") (af "`%s`" origination_res.address);
                  desc
                    (af "A rollup node in %S mode is listening on"
                       (Node.mode_string soru_node.mode))
                    (af "rpc_port: `%d`"
                       (Option.value_exn
                          ?message:
                            (Some
                               "Failed to get rpc port for Smart rollup node.")
                          soru_node.rpc_port));
                ]))

let cmdliner_term state () =
  let open Cmdliner in
  let open Term in
  let docs =
    Manpage_builder.section state ~rank:2 ~name:"SMART OPTIMISTIC ROLLUPS"
  in
  let extra_doc =
    Fmt.str " for the smart optimistic rollup (requires --smart-rollup)."
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
    | `Hex p | `Wasm p -> Caml.Filename.(basename p |> chop_extension)
  in
  const
    (fun
      start
      soru
      level
      custom_kernel
      node_mode
      node
      client
      installer
      evm_proxy_server
    ->
      let make id kernel =
        {
          id;
          level;
          kernel;
          node_mode;
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
          (info [ "smart-rollup" ]
             ~doc:
               "Start the Flextexa mini-network with a smart optimistic \
                rollup. By default this will be the transction smart rollup \
                (TX-kernel). See `--custom-kernel` for other options."
             ~docs))
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
          ~doc:
            (sprintf
               "Originate a smart rollup of KIND and of TYPE with PATH to a \
                custom kernel %s"
               extra_doc)
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
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_node
      ~prefix:"octez"
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_client
      ~prefix:"octez"
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_installer
      ~prefix:"octez"
  $ Tezos_executable.cli_term ~extra_doc state `Evm_proxy_server ~prefix:"octez"
