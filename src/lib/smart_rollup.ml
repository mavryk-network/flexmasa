open Internal_pervasives

(* A type for SORU cmdliner options. *)
type t = {
  id : string;
  level : int;
  kernel : (string * string * string) option;
  node_mode : [ `Operator | `Batcher | `Observer | `Maintenance | `Accuser ];
  node : Tezos_executable.t;
  client : Tezos_executable.t;
  installer : Tezos_executable.t;
}

(* Make a SORU directory *)
let make_path ~state t p =
  Paths.root state // sprintf "%s-smart-rollup" t.id // p

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
    soru_addr : string;
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

  let make_config ~smart_rollup ?node_id ~mode ~soru_addr ~operator_addr
      ?rpc_addr ?rpc_port ?endpoint ~protocol ~exec ~client () : config =
    let name =
      sprintf "%s-smart-rollup-%s-node-%s" smart_rollup.id (mode_string mode)
        (Option.value node_id ~default:"000")
    in
    {
      node_id = name;
      mode;
      soru_addr;
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
  let node_dir state node p =
    make_path ~state node.smart_rollup (sprintf "%s" node.node_id // p)

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
  let init state config =
    call state ~config
      [
        "init";
        mode_string config.mode;
        "config";
        "for";
        config.soru_addr;
        "with";
        "operators";
        config.operator_addr;
      ]

  (* Start a running SORU node. *)
  let start state config =
    Running_processes.Process.genspio
      (sprintf "%s-node-for-%s-smart-rollup" (mode_string config.mode)
         config.node_id)
      (Genspio.EDSL.check_sequence ~verbosity:`Output_all
         [
           ("init SORU node", init state config);
           ("run SORU node", call state ~config [ "run" ]);
         ])

  (*  TODO Maybe add a node with --loser-mode for testing. *)
end

module Kernel = struct
  (* The path to the SORU kernel. *)
  type config = {
    kernel_path : string;
    installer_dir : string;
    reveal_data_dir : string;
    exec : Tezos_executable.t;
    smart_rollup : t;
  }

  (* A type for the kernel hex passed othe octez client origination command. *)
  type hex = { name : string; hex : string }

  (* The default kernel. *)
  let default : hex =
    {
      name = "echo";
      hex =
        "0061736d0100000001280760037f7f7f017f60027f7f017f60057f7f7f7f7f017f60017f0060017f017f60027f7f0060000002610311736d6172745f726f6c6c75705f636f72650a726561645f696e707574000011736d6172745f726f6c6c75705f636f72650c77726974655f6f7574707574000111736d6172745f726f6c6c75705f636f72650b73746f72655f77726974650002030504030405060503010001071402036d656d02000a6b65726e656c5f72756e00060aa401042a01027f41fa002f0100210120002f010021022001200247044041e4004112410041e400410010021a0b0b0800200041c4006b0b5001057f41fe002d0000210341fc002f0100210220002d0000210420002f0100210520011004210620042003460440200041016a200141016b10011a0520052002460440200041076a200610011a0b0b0b1d01017f41dc0141840241901c100021004184022000100541840210030b0b38050041e4000b122f6b65726e656c2f656e762f7265626f6f740041f8000b0200010041fa000b0200020041fc000b0200000041fe000b0101";
    }

  (* SORU kernel dirctory *)
  let kernel_dir ~state smart_rollup p =
    make_path ~state smart_rollup (sprintf "%s-kernel" smart_rollup.id // p)

  let make_config state smart_rollup node =
    (*  TODO these paths need to lead to the actual files not just the directory. *)
    let kernel_path =
      match smart_rollup.kernel with
      | None -> "" (*  TODO default? *)
      | Some (_, _, p) -> p
    in
    let installer_dir = kernel_dir ~state smart_rollup "installer" in
    let reveal_data_dir = Node.reveal_data_dir state node in
    let exec = smart_rollup.installer in
    { kernel_path; installer_dir; reveal_data_dir; exec; smart_rollup }

  (* Name of the kernel installer from path. *)
  let name path = Caml.Filename.basename path |> Caml.Filename.chop_extension

  (* The hexadecimal encoded content of the file at path. *)
  let of_path path : hex =
    let ic = Stdlib.open_in path in
    let bytes = Bytes.create 16 in
    (* Get bytes form file. *)
    let content =
      let rec get b =
        let next = Stdlib.input ic b 0 1 in
        if next = 0 then b else get b
      in
      get bytes
    in
    { name = name path; hex = Hex.(of_bytes content |> show) }
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
  let kind, michelson_type, kernel =
    match kernel with
    | None -> ("wasm_2_0_0", "bytes", Kernel.default)
    | Some (k, t, p) -> (k, t, Kernel.of_path p)
    (*  TODO this will need to become the installer kernel *)
  in
  Tezos_client.successful_client_cmd state ~client
    [
      "originate";
      "smart";
      "rollup";
      "from";
      account;
      "of";
      "kind";
      kind;
      "of";
      "type";
      michelson_type;
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
  const (fun soru level kernel node_mode node client installer ->
      match soru with
      | true ->
          let id =
            match kernel with
            | None -> Kernel.default.name
            | Some (_, _, p) -> Kernel.name p
          in

          Some { id; level; kernel; node_mode; node; client; installer }
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
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_node "octez"
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_client "octez"
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_installer "octez"
