open Internal_pervasives

module Node = struct
  (* The mode of the SORU node. *)
  type mode = Operator | Batcher | Observer | Maintenance | Accuser

  let mode_string = function
    | Operator -> "operator"
    | Batcher -> "batcher"
    | Observer -> "observer"
    | Maintenance -> "maintenance"
    | Accuser -> "accuser"

  (* A type for the SORU node config. *)
  type config = {
    id : string;
    mode : mode;
    soru_addr : string;
    operator_addr : string;
    rpc_addr : int option;
    rpc_port : int option;
    endpoint : int option;
    protocol : Tezos_protocol.Protocol_kind.t;
    exec : Tezos_executable.t;
    client : Tezos_client.t;
  }

  type t = config

  let make_config ?id ~mode ~soru_addr ~operator_addr ?rpc_addr ?rpc_port
      ?endpoint ~protocol ~exec ~client () : config =
    let name =
      sprintf "smart-rollup-%s-node-%s" (mode_string mode)
        (Option.value id ~default:"000")
    in
    {
      id = name;
      mode;
      soru_addr;
      operator_addr;
      rpc_addr;
      rpc_port;
      endpoint;
      protocol;
      exec;
      client;
    }

  (* SORU node directory. *)
  let node_dir p state node =
    Paths.root state // sprintf "smart-rollup" // (sprintf "%s" node.id // p)

  (* octez-smart-rollup node command.*)
  let call state ~config command =
    let open Tezos_executable.Make_cli in
    let client_dir = Tezos_client.base_dir ~state config.client in
    Tezos_executable.call state config.exec ~protocol_kind:config.protocol
      ~path:(node_dir "exec" state config)
      (Option.value_map config.endpoint ~default:[] ~f:(fun e ->
           opt "endpoint" (sprintf "http://localhost:%d" e))
      (* The base-dir is the octez_client directory. *)
      @ opt "base-dir" client_dir
      @ command
      (* The directory where the node config is stored. *)
      @ opt "data-dir" (node_dir "data-dir" state config)
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
      (sprintf "%s-node-for-smart-rollup" (mode_string config.mode))
      (Genspio.EDSL.check_sequence ~verbosity:`Output_all
         [
           ("init SORU node", init state config);
           ("run SORU node", call state ~config [ "run" ]);
         ])
end

(* The hexadecimal encoded content of the file at path. *)
let kernel_of_path path =
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
  (* Convert to a hexidecimal encoded string. *)
  Hex.(of_bytes content |> show)

(* Flextesa's default SORU kernel. *)
let default_kernel =
  "0061736d0100000001280760037f7f7f017f60027f7f017f60057f7f7f7f7f017f60017f0060017f017f60027f7f0060000002610311736d6172745f726f6c6c75705f636f72650a726561645f696e707574000011736d6172745f726f6c6c75705f636f72650c77726974655f6f7574707574000111736d6172745f726f6c6c75705f636f72650b73746f72655f77726974650002030504030405060503010001071402036d656d02000a6b65726e656c5f72756e00060aa401042a01027f41fa002f0100210120002f010021022001200247044041e4004112410041e400410010021a0b0b0800200041c4006b0b5001057f41fe002d0000210341fc002f0100210220002d0000210420002f0100210520011004210620042003460440200041016a200141016b10011a0520052002460440200041076a200610011a0b0b0b1d01017f41dc0141840241901c100021004184022000100541840210030b0b38050041e4000b122f6b65726e656c2f656e762f7265626f6f740041f8000b0200010041fa000b0200020041fc000b0200000041fe000b0101"

(* octez-client call to originate a SORU. *)
let originate state ~client ~account ~kernel () =
  let kind, michelson_type, kernel =
    match kernel with
    | None -> ("wasm_2_0_0", "bytes", default_kernel)
    | Some (k, t, p) -> (k, t, kernel_of_path p)
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
      kernel;
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

(* A type for SORU cmdliner options. *)
type t = {
  level : int;
  kernel : (string * string * string) option;
  node_mode : Node.mode;
  node : Tezos_executable.t;
  client : Tezos_executable.t;
}

(* A list of smart rollup executables. *)
let executables ({ client; node; _ } : t) = [ client; node ]

let cmdliner_term state () =
  let open Cmdliner in
  let open Term in
  let docs =
    Manpage_builder.section state ~rank:2 ~name:"SMART OPTIMISTIC ROLLUPS"
  in
  let extra_doc =
    Fmt.str " for the smart optimistic rollup (requires --smart-rollup)."
  in
  const (fun soru level kernel node_mode node client ->
      match soru with
      | true -> Some { level; kernel; node_mode; node; client }
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
          Node.(
            enum
              [
                ("operator", Operator);
                ("batcher", Batcher);
                ("observer", Observer);
                ("maintenance", Maintenance);
                ("accuser", Accuser);
              ])
          Operator
      & info ~docs [ "soru-node-mode" ]
          ~doc:(sprintf "Set the rollup node's `mode`%s" extra_doc))
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_node "octez"
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_client "octez"
