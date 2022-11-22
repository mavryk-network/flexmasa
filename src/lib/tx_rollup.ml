open Internal_pervasives

type t = {
  level : int;
  name : string;
  node : Tezos_executable.t;
  client : Tezos_executable.t;
}

let make_path p ~config t =
  Paths.root config // sprintf "tx-rollup-%s" t.name // p

module Account = struct
  type t = {
    name : string;
    operation_hash : string;
    address : string;
    origination_account : string;
    out : string list;
  }

  let make ~name ~operation_hash ~address ~origination_account ~out : t =
    { name; operation_hash; address; origination_account; out }

  let gas_account ~client name =
    let acc = Tezos_protocol.Account.of_namef "%s" name in
    let key =
      let key, priv = Tezos_protocol.Account.(name acc, private_key acc) in
      Tezos_client.Keyed.make client ~key_name:key ~secret_key:priv
    in
    (acc, key)

  let fund state ~client ~amount ~from ~destination =
    Tezos_client.successful_client_cmd state ~client
      [
        "transfer"; amount; "from"; from; "to"; destination; "--burn-cap"; "15";
      ]

  let fund_multiple state ~client ~from ~(recipients : (string * string) list) =
    let json =
      let open Ezjsonm in
      list dict
        (List.fold recipients ~init:[] ~f:(fun acc (dst, amt) ->
             [ ("destination", string dst); ("amount", string amt) ] :: acc))
      |> to_string
    in
    Tezos_client.successful_client_cmd state ~client
      [
        "multiple"; "transfers"; "from"; from; "using"; json; "--burn-cap"; "15";
      ]

  let originate state ~name ~client ~account =
    Tezos_client.successful_client_cmd state ~client
      [ "originate"; "tx"; "rollup"; name; "from"; account; "--burn-cap"; "15" ]

  let confirm state ~client ?(confirmations = 0) ~operation_hash () =
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
    (* This is parsing the unicode cli output from the octez-client *)
    Option.(
      prefix_from_list ~prefix:"Operation hash is" l >>= fun op ->
      String.chop_prefix ~prefix:"'" op >>= fun suf ->
      String.chop_suffix ~suffix:"'" suf >>= fun operation_hash ->
      prefix_from_list ~prefix:"From:" l >>= fun origination_account ->
      prefix_from_list ~prefix:"Originated tx rollup:" l >>= fun address ->
      prefix_from_list ~prefix:"Transaction rollup memorized as" l
      >>= fun name ->
      return
        (make ~name ~operation_hash ~address ~origination_account ~out:lines))
end

module Deposit_contract = struct
  type t = string

  let make : string -> t = fun s -> s

  let originate state ?(rollup_name = "toru")
      ~(protocol : Tezos_protocol.Protocol_kind.t) ~client ~account () =
    let michelson =
      match protocol with
      | `Kathmandu ->
          "parameter (pair string nat tx_rollup_l2_address address);\n\
           storage unit;\n\
           code {\n\
          \       CAR;\n\
          \       UNPAIR 4;\n\
          \       TICKET;\n\
          \       PAIR;\n\
          \       SWAP;\n\
          \       CONTRACT %deposit (pair (ticket string) tx_rollup_l2_address);\n\
          \       ASSERT_SOME;\n\
          \       SWAP;\n\
          \       PUSH mutez 0;\n\
          \       SWAP;\n\
          \       TRANSFER_TOKENS;\n\
          \       UNIT;\n\
          \       NIL operation;\n\
          \       DIG 2;\n\
          \       CONS;\n\
          \       PAIR;\n\
          \     }\n"
      | `Lima | `Alpha ->
          "parameter (pair string nat tx_rollup_l2_address address);\n\
           storage unit;\n\
           code {\n\
          \       CAR;\n\
          \       UNPAIR 4;\n\
          \       TICKET;\n\
          \       ASSERT_SOME;\n\
          \       PAIR;\n\
          \       SWAP;\n\
          \       CONTRACT %deposit (pair (ticket string) tx_rollup_l2_address);\n\
          \       ASSERT_SOME;\n\
          \       SWAP;\n\
          \       PUSH mutez 0;\n\
          \       SWAP;\n\
          \       TRANSFER_TOKENS;\n\
          \       UNIT;\n\
          \       NIL operation;\n\
          \       DIG 2;\n\
          \       CONS;\n\
          \       PAIR;\n\
          \     }\n"
      | _ ->
          failwith
            (sprintf
               "Wrong protocol type for %s ticket deposit contract origination."
               rollup_name)
    in
    Tezos_client.successful_client_cmd state ~client
      [
        "originate";
        "contract";
        rollup_name ^ "-deposit-contract";
        "transferring";
        "0";
        "from";
        account;
        "running";
        michelson;
        "--burn-cap";
        "15";
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
end

module Tx_node = struct
  type mode = Observer | Accuser | Batcher | Maintenance | Operator | Custom

  type operation_signer =
    | Operator_signer of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Batch of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Finalize_commitment of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Remove_commitment of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Rejection of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Dispatch_withdrawal of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)

  type node = {
    id : string;
    port : int option;
    endpoint : int option;
    protocol : Tezos_protocol.Protocol_kind.t;
    exec : Tezos_executable.t;
    client : Tezos_client.t;
    mode : mode;
    cors_origin : string option;
    account : Account.t;
    operation_signers : operation_signer list;
    tx_rollup : t;
  }

  let operation_signers ~client ~id ~operator ~batch ?finalize ?remove
      ?rejection ?dispatch () : operation_signer list =
    let acc_and_key str =
      Account.gas_account ~client (sprintf "%s-%s" id str)
    in
    let of_option opt opr_signer =
      Option.value_map opt ~default:[] ~f:(fun s ->
          [ opr_signer (acc_and_key s) ])
    in
    [ Operator_signer (acc_and_key operator); Batch (acc_and_key batch) ]
    @ of_option finalize (fun s -> Finalize_commitment s)
    @ of_option remove (fun s -> Remove_commitment s)
    @ of_option rejection (fun s -> Rejection s)
    @ of_option dispatch (fun s -> Dispatch_withdrawal s)

  let defult_signers client id : operation_signer list =
    operation_signers ~client ~id ~operator:"operator-signer"
      ~batch:"batch-signer" ~finalize:"finalize-commitment-signer"
      ~remove:"remove-commitment-signer" ~rejection:"rejection-signer"
      ~dispatch:"dispatch-withdrawals-signer" ()

  let operation_signer_map os ~f =
    match os with
    | Operator_signer s
    | Batch s
    | Finalize_commitment s
    | Remove_commitment s
    | Rejection s
    | Dispatch_withdrawal s ->
        f s

  let node_dir p config node =
    make_path (sprintf "%s" node.id // p) ~config node.tx_rollup

  let data_dir config node = node_dir "data-dir" config node
  let exec_path config node = node_dir "exec" config node

  let mode_string = function
    | Observer -> "observer"
    | Accuser -> "accuser"
    | Batcher -> "batcher"
    | Maintenance -> "maintenance"
    | Operator -> "operator"
    | Custom -> "custom "

  let make ?id ?port ?endpoint ~protocol ~exec ~client ~mode ?cors_origin
      ~account ?operation_signers ~tx_rollup () : node =
    let name =
      sprintf "%s-%s-node-%s" account.Account.name (mode_string mode)
        (Option.value id ~default:"000")
    in
    {
      id = name;
      port;
      endpoint;
      protocol;
      exec;
      client;
      mode;
      cors_origin;
      account;
      operation_signers =
        Option.value operation_signers ~default:(defult_signers client name);
      tx_rollup;
    }

  open Tezos_executable.Make_cli

  let call state t command =
    (* The tx_rollup_node base directory is set to share with the octez_client and the endpoint will match the base_port passed to flextesa. *)
    let client_dir = Tezos_client.base_dir ~state t.client in
    Tezos_executable.call state t.exec ~protocol_kind:t.protocol
      ~path:(exec_path state t // sprintf "exec-toru-%s" t.id)
      (Option.value_map t.endpoint ~default:[] ~f:(fun e ->
           opt "endpoint" (sprintf "http://localhost:%d" e))
      @ opt "base-dir" client_dir @ command)

  let common_options state t =
    let singer_options =
      Tezos_protocol.Account.(
        function
        | Operator_signer (acc, _) -> opt "operator" (name acc)
        | Batch (acc, _) -> opt "batch-signer" (name acc)
        | Finalize_commitment (acc, _) ->
            opt "finalize-commitment-signer" (name acc)
        | Remove_commitment (acc, _) ->
            opt "remove-commitment-signer" (name acc)
        | Rejection (acc, _) -> opt "rejection-signer" (name acc)
        | Dispatch_withdrawal (acc, _) ->
            opt "dispatch-withdrawals-signer" (name acc))
    in
    let cors_origin =
      match t.cors_origin with
      | Some _ as s -> s
      | None -> Environment_configuration.default_cors_origin state
    in
    (* Allow deposit is required for obvious reasons. *)
    flag "allow-deposit"
    (* The directory where the node configuration is store. *)
    @ opt "data-dir" (data_dir state t)
    @ List.concat_map t.operation_signers ~f:singer_options
    @ Option.value_map cors_origin
        ~f:(fun s ->
          flag "cors-header=content-type" @ Fmt.kstr flag "cors-origin=%s" s)
        ~default:[]
    (* Set the nodes rpc_adderess. *)
    @ Option.value_map t.port
        ~f:(fun p -> opt "rpc-addr" (sprintf "0.0.0.0:%d" p))
        ~default:[]

  let init state t =
    call state t
      ([ "init"; mode_string t.mode; "config"; "for"; t.account.address ]
      @ flag "force" @ common_options state t)

  let run state t =
    call state t
      ([ "run"; mode_string t.mode; "for"; t.account.address ]
      @ common_options state t)

  let start_script state t =
    let open Genspio.EDSL in
    check_sequence ~verbosity:`Output_all
      [ ("init node", init state t); ("run node", run state t) ]

  let process state t script =
    Running_processes.Process.genspio
      (sprintf "%s-node-for-tx-rollup-%s" (mode_string t.mode) t.account.name)
      (script state t)

  let cmdliner_term state () =
    (* This was added in anticipation of possibly creating multiple nodes of different mode types. *)
    (* Maybe users what to run their own TORU node and would like Flextesa to run a passive observer node.*)
    let open Cmdliner in
    let extra_doc = " for transaction rollups (requires --tx-rollup)" in
    let docs =
      Manpage_builder.section state ~rank:2
        ~name:"TRANSACTION OPTIMISTIC ROLLUP NODE"
    in
    Arg.(
      value
      & opt
          (enum
             [
               ("observer", Observer);
               ("accuser", Accuser);
               ("batcher", Batcher);
               ("maintenance", Maintenance);
               ("custom ", Custom);
               ("operator", Operator);
             ])
          Operator
      & info ~docs [ "tx-rollup-node-mode" ]
          ~doc:
            (sprintf
               "Set the transaction rollup node's `mode`%s. The default mode \
                is `Operator`."
               extra_doc))
end

let origination_account ~client name =
  Account.gas_account ~client (sprintf "%s-origination-account" name)

let originate_and_confirm state ~name ~client ~account ?confirmations () =
  Account.originate state ~name ~client ~account >>= fun res ->
  return (Account.parse_origination ~lines:res#out) >>= fun rollup ->
  match rollup with
  | None ->
      System_error.fail_fatalf
        "Tx_rollup.originate_and_confirm - failed to parse tx_rollup \
         origination."
  | Some acc ->
      Account.confirm state ~client ?confirmations
        ~operation_hash:acc.operation_hash ()
      >>= fun conf -> return (acc, conf#out)

let publish_deposit_contract state protocol rollup_name client account =
  let open Deposit_contract in
  originate state ~rollup_name ~protocol ~client ~account () >>= fun res ->
  match parse_origination ~lines:res#out with
  | None ->
      System_error.fail_fatalf
        "Tx_rollup.publish - failed to parse smart contract origination."
  | Some address -> return address

let executables ({ client; node; _ } : t) = [ client; node ]

let cmdliner_term base_state ~docs () =
  let open Cmdliner in
  let open Term in
  let extra_doc = Fmt.str " for transaction rollups (requires --tx-rollup)" in
  const (fun tx_rollup node client ->
      Option.map tx_rollup ~f:(fun (level, name) ->
          let txr_name =
            match name with None -> "flextesa-tx-rollup" | Some n -> n
          in
          { level; name = txr_name; node; client }))
  $ Arg.(
      value
        (opt
           (some (t2 ~sep:':' int (some string)))
           None
           (info [ "tx-rollup" ]
              ~doc:"Originate a transaction rollup `name` at `level`." ~docs
              ~docv:"LEVEL:TX-ROLLUP-NAME")))
  $ Tezos_executable.cli_term ~extra_doc base_state `Tx_rollup_node "tezos"
  $ Tezos_executable.cli_term ~extra_doc base_state `Tx_rollup_client "tezos"
