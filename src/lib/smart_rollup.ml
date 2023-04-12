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
    rpc_addr : int option;
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
          ~f:(fun a -> opt "rpc-addr" (sprintf "%d" a))
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
    Running_processes.Process.genspio
      (sprintf "%s-node-for-%s-smart-rollup" (mode_string config.mode)
         config.node_id)
      (Genspio.EDSL.check_sequence ~verbosity:`Output_all
         [
           ("init SORU node", init state config soru_addr);
           ("start SORU node", call state ~config [ "start" ]);
           ("run SORU node", call state ~config [ "run" ]);
         ])
end

module Kernel = struct
  type custom_config = {
    kernel_path : string;
    installer_kernel : string;
    reveal_data_dir : string;
    exec : Tezos_executable.t;
    smart_rollup : t;
    node : Node.t;
  }

  type kernel = {
    name : string;
    kind : string;
    michelson_type : string;
    hex : string;
  }

  type t = kernel

  (* The default kernel. *)
  let default : t =
    {
      name = "echo";
      kind = "wasm_2_0_0";
      michelson_type = "bytes";
      hex =
        "0061736d0100000001280760037f7f7f017f60027f7f017f60057f7f7f7f7f017f60017f0060017f017f60027f7f0060000002610311736d6172745f726f6c6c75705f636f72650a726561645f696e707574000011736d6172745f726f6c6c75705f636f72650c77726974655f6f7574707574000111736d6172745f726f6c6c75705f636f72650b73746f72655f77726974650002030504030405060503010001071402036d656d02000a6b65726e656c5f72756e00060aa401042a01027f41fa002f0100210120002f010021022001200247044041e4004112410041e400410010021a0b0b0800200041c4006b0b5001057f41fe002d0000210341fc002f0100210220002d0000210420002f0100210520011004210620042003460440200041016a200141016b10011a0520052002460440200041076a200610011a0b0b0b1d01017f41dc0141840241901c100021004184022000100541840210030b0b38050041e4000b122f6b65726e656c2f656e762f7265626f6f740041f8000b0200010041fa000b0200020041fc000b0200000041fe000b0101";
    }

  (* SORU kernel dirctory *)
  let kernel_dir ~state smart_rollup p =
    make_path ~state (sprintf "%s-kernel" smart_rollup.id // p)

  let make_config ~state smart_rollup node : custom_config =
    let kernel_path =
      Option.value_exn smart_rollup.custom_kernel
        ~message:"Was expecting `--custom-kerenel [ARG]`."
      |> fun (_, _, p) -> p
    in
    let installer_kernel =
      kernel_dir ~state smart_rollup
        (sprintf "%s-installer.hex" smart_rollup.id)
    in
    let reveal_data_dir = Node.reveal_data_dir state node in
    let exec = smart_rollup.installer in
    { kernel_path; installer_kernel; reveal_data_dir; exec; smart_rollup; node }

  (* Name of the kernel installer from path. *)
  let name path = Caml.Filename.(basename path |> chop_extension)

  let make ~name ~kind ~michelson_type ~hex =
    { name; kind; michelson_type; hex }

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
  let build state ~smart_rollup ~node =
    match smart_rollup.custom_kernel with
    | None -> return default
    | Some (kind, michelson_type, kernel_path) -> (
        let conf = make_config ~state smart_rollup node in
        let name = name kernel_path in
        let kernel hex = make ~name ~kind ~michelson_type ~hex in
        let size p =
          let open Unix in
          let stats = stat p in
          stats.st_size
        in
        let content path size =
          let open Stdlib in
          let ic = open_in path in
          let cont_str = really_input_string ic size in
          close_in ic;
          cont_str
        in
        make_dir state (kernel_dir ~state smart_rollup "") >>= fun _ ->
        make_dir state conf.reveal_data_dir >>= fun _ ->
        if size conf.kernel_path > 24 * 1048 then
          (* wasm files larger that 24kB are passed to isntaller_crate. We can't do anything with large .hex files *)
          match check_extension conf.kernel_path with
          | `Hex p ->
              raise
                (Invalid_argument
                   (sprintf
                      "Installer kernel is .hex. Was expecting .wasm at %s.\n" p))
          | `Wasm _ ->
              installer_create state ~exec:conf.exec.kind ~path:conf.kernel_path
                ~output:conf.installer_kernel
                ~preimages_dir:conf.reveal_data_dir
              >>= fun _ ->
              return
                (kernel
                   (content conf.installer_kernel (size conf.installer_kernel)))
        else
          (* For smaller kernels *)
          match check_extension conf.kernel_path with
          | `Hex p -> return (kernel (content p (size p)))
          | `Wasm p ->
              return (kernel Hex.(content p (size p) |> of_string |> show)))
end

module Echo_contract = struct
  type t = string

  let make : string -> t = fun s -> s

  let originate state ~client ~account () =
    let michelson =
      "parameter string; storage string; code {CAR; NIL operation; PAIR};"
    in
    Tezos_client.successful_client_cmd state ~client
      [
        "originate";
        "contract";
        "smart-rollup-echo-contract";
        "transferring";
        "0";
        "from";
        account;
        "running";
        michelson;
        "--init";
        "\"\"";
        "--burn-cap";
        "1";
      ]

  let parse_origination ~lines =
    let rec prefix_from_list ~prefix = function
      | [] -> None
      | x :: xs ->
          if not (String.is_prefix x ~prefix) then prefix_from_list ~prefix xs
          else Some x
    in
    let l = List.map lines ~f:String.lstrip in
    Option.(
      prefix_from_list ~prefix:"KT1" l >>= fun address -> return (make address))

  let publish state ~client ~account =
    originate state ~client ~account () >>= fun res ->
    match parse_origination ~lines:res#out with
    | None ->
        System_error.fail_fatalf
          "Smart_rollup.Echo_contract.publish - failed to parse smart contract \
           origination."
    | Some address -> return address
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
            | None -> Kernel.default.name
            | Some (_, _, p) -> (
                Kernel.(
                  match check_extension p with `Hex p | `Wasm p -> name p))
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
          (info [ "soru-start-level" ]
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
      & info ~docs [ "soru-node-mode" ]
          ~doc:(sprintf "Set the rollup node's `mode`%s" extra_doc))
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_node
      ~prefix:"octez" ()
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_client
      ~prefix:"octez" ()
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_installer
      ~prefix:"Octez" ()
