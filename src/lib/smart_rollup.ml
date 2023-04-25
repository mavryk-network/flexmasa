open Internal_pervasives

(* A type for SORU cmdliner options. *)
type t = {
  id : string;
  level : int;
  custom_kernel : (string * string * string) option;
  node_mode : [ `Operator | `Batcher | `Observer | `Maintenance | `Accuser ];
  node : Tezos_executable.t;
  client : Tezos_executable.t;
  installer : Tezos_executable.t;
}

let make_path ~state p = Paths.root state // sprintf "smart-rollup" // p

let make_dir state p =
  Running_processes.run_successful_cmdf state "mkdir -p %s" p

module Node = struct
  (* The mode of the SORU node. *)
  type mode = [ `Operator | `Batcher | `Observer | `Maintenance | `Accuser ]

  let mode_string = function
    | `Operator -> "operator"
    | `Batcher -> "batcher"
    | `Observer -> "observer"
    | `Maintenance -> "maintenance"
    | `Accuser -> "accuser"

  (* A type for the SORU node config. *)
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
      node_id = name;
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

  (* SORU node directory. *)
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
      @ command
      (* The directory where the node config is stored. *)
      @ opt "data-dir" (data_dir state config)
      @ Option.value_map config.rpc_addr
          ~f:(fun a -> opt "rpc-addr" (sprintf "%s" a))
          ~default:[]
      @ Option.value_map config.rpc_port
          ~f:(fun p -> opt "rpc-port" (sprintf "%d" p))
          ~default:[])

  (* Command to initiate a SORU node [config] *)
  let init state config soru_addr =
    call state ~config
      [
        "init";
        mode_string config.mode;
        "config";
        "for";
        soru_addr;
        "with";
        "operators";
        config.operator_addr;
      ]

  (* Start a running SORU node. *)
  let start state config soru_addr =
    Running_processes.Process.genspio config.node_id
      (Genspio.EDSL.check_sequence ~verbosity:`Output_all
         [
           ("init SORU node", init state config soru_addr);
           ("run SORU node", call state ~config [ "run" ]);
         ])
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

  (* SORU kernel dirctory *)
  let kernel_dir ~state smart_rollup p =
    make_path ~state (sprintf "%s-kernel" smart_rollup.id // p)

  let make_config ~state smart_rollup node : config =
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

  let default_args =
    make_args ~kind:Tx_installer.kind
      ~michelson_type:Tx_installer.michelson_type ~hex:Tx_installer.hex

  let load_default_preimages reveal_data_dir preimages =
    let write_file path content =
      let open Stdlib in
      let oc = open_out_bin path in
      output_bytes oc content;
      close_out oc
    in
    List.iter preimages ~f:(fun (p, contents) ->
        let filename = Caml.Filename.basename p in
        write_file (reveal_data_dir // filename) contents)

  (* Check the extension of user provided kernel. *)
  let check_extension path =
    let open Caml.Filename in
    let ext = extension path in
    match ext with
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
    let config = make_config ~state smart_rollup node in
    make_dir state (kernel_dir ~state smart_rollup "") >>= fun _ ->
    make_dir state config.reveal_data_dir >>= fun _ ->
    match smart_rollup.custom_kernel with
    | None ->
        return
          (load_default_preimages config.reveal_data_dir Preimages.tx_kernel)
        >>= fun _ -> return default_args
    | Some (kind, michelson_type, kernel_path) -> (
        let cli_args hex = make_args ~kind ~michelson_type ~hex in
        let size p =
          let stats = Unix.stat p in
          stats.st_size
        in
        let content path size =
          let open Stdlib in
          let ic = open_in path in
          let cont_str = really_input_string ic size in
          close_in ic;
          cont_str
        in
        if size kernel_path > 24 * 1048 then
          (* wasm files larger that 24kB are passed to isntaller_crate. We can't do anything with large .hex files *)
          match check_extension kernel_path with
          | `Hex p ->
              raise
                (Invalid_argument
                   (sprintf
                      "Installer cli_args is .hex. Was expecting .wasm at %s.\n"
                      p))
          | `Wasm _ ->
              installer_create state ~exec:config.exec.kind ~path:kernel_path
                ~output:config.installer_kernel
                ~preimages_dir:config.reveal_data_dir
              >>= fun _ ->
              return
                (cli_args
                   (content config.installer_kernel
                      (size config.installer_kernel)))
        else
          match check_extension kernel_path with
          | `Hex p -> return (cli_args (content p (size p)))
          | `Wasm p ->
              return (cli_args Hex.(content p (size p) |> of_string |> show)))
end

(* octez-client call to originate a SORU. *)
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

(* octez-client call confirming and operation. *)
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

(* A type for octez client output from a SORU origination. *)
type origination_result = {
  operation_hash : string;
  address : string;
  origination_account : string;
  out : string list;
}

(* Parse octez-client output of SORU origination. *)
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
          (* Configure SORU node. *)
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
          (* Originate SORU.*)
          originate_and_confirm state ~client ~kernel ~account:op_keys.key_name
            ~confirmations:1 ()
          >>= fun (origination_res, _confirmation_res) ->
          (* Start SORU node. *)
          Running_processes.start state
            Node.(start state soru_node origination_res.address)
          >>= fun _ ->
          (* Print SORU info. *)
          Console.say state
            EF.(
              desc_list
                (haf "%S Smart Optimistic Rollup is ready:" soru.id)
                [
                  desc (af "Rollup ddress:") (af "`%s`" origination_res.address);
                  desc
                    (af "The  %s node is listening on port:"
                       (Node.mode_string soru_node.mode))
                    (af "`%d`"
                       (Option.value_exn
                          ?message:
                            (Some
                               "Failed to get rpc port for Smart rollup node.")
                          soru_node.rpc_port));
                  desc
                    (af "Node Operator address:")
                    (af "`%s`" (Tezos_protocol.Account.pubkey_hash op_acc));
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
  const (fun soru level custom_kernel node_mode node client installer ->
      match soru with
      | true ->
          let id =
            match custom_kernel with
            | None -> Tx_installer.name
            | Some (_, _, p) -> (
                match Kernel.check_extension p with
                | `Hex p | `Wasm p ->
                    Caml.Filename.(basename p |> chop_extension))
          in
          Some { id; level; custom_kernel; node_mode; node; client; installer }
      | false -> None)
  $ Arg.(
      value
      & flag
          (info [ "smart-rollup" ]
             ~doc:
               "Start the Flextexa mini-network with a smart optimistic rollup \
                (SORU)."
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
      ~prefix:"octez" ()
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_client
      ~prefix:"octez" ()
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_installer
      ~prefix:"octez" ()
