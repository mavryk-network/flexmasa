open Internal_pervasives

module Account = struct
  type t =
    { name: string
    ; operation_hash: string
    ; address: string
    ; origination_account: string
    ; out: string list }

  let make ~name ~operation_hash ~address ~origination_account ~out : t =
    {name; operation_hash; address; origination_account; out}

  let gas_account ~client name =
    let acc = Tezos_protocol.Account.of_namef "%s" name in
    let key =
      let key, priv = Tezos_protocol.Account.(name acc, private_key acc) in
      Tezos_client.Keyed.make client ~key_name:key ~secret_key:priv in
    (acc, key)

  let fund state ~client ~amount ~from ~dst =
    Tezos_client.successful_client_cmd state ~client
      ["transfer"; amount; "from"; from; "to"; dst; "--burn-cap"; "15"]

  let fund_multiple state ~client ~from ~(recipiants : (string * string) list) =
    let json =
      let open Ezjsonm in
      list dict
        (List.fold recipiants ~init:[] ~f:(fun acc (dst, amt) ->
             [("destination", string dst); ("amount", string amt)] :: acc ) )
      |> to_string in
    Tezos_client.successful_client_cmd state ~client
      ["multiple"; "transfers"; "from"; from; "using"; json; "--burn-cap"; "15"]

  let originate state ~name ~client ~acc =
    Tezos_client.successful_client_cmd state ~client
      ["originate"; "tx"; "rollup"; name; "from"; acc; "--burn-cap"; "15"]

  let confirm state ~client ?(confirmations = 0) ~operation_hash () =
    Tezos_client.successful_client_cmd state ~client
      [ "wait"; "for"; operation_hash; "to"; "be"; "included"; "--confirmations"
      ; Int.to_string confirmations ]

  let parse_origination ~lines =
    let rec prefix_from_list ~prefix = function
      | [] -> None
      | x :: xs ->
          if not (String.is_prefix x ~prefix) then prefix_from_list ~prefix xs
          else
            Some
              (String.lstrip
                 (String.chop_prefix x ~prefix |> Option.value ~default:x) )
    in
    let l = List.map lines ~f:String.lstrip in
    Option.(
      prefix_from_list ~prefix:"Operation hash is" l
      >>= fun op ->
      String.chop_prefix ~prefix:"'" op
      >>= fun suf ->
      String.chop_suffix ~suffix:"'" suf
      >>= fun operation_hash ->
      prefix_from_list ~prefix:"From:" l
      >>= fun origination_account ->
      prefix_from_list ~prefix:"Originated tx rollup:" l
      >>= fun address ->
      prefix_from_list ~prefix:"Transaction rollup memorized as" l
      >>= fun name ->
      return
        (make ~name ~operation_hash ~address ~origination_account ~out:lines))
end

module Tx_node = struct
  type mode = Observer | Accuser | Batcher | Maintenance | Operator | Custom

  type operation_signer =
    | Operator of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Batch of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Finalize_commitment of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Remove_commitment of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Rejection of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)
    | Dispatch_withdrawal of (Tezos_protocol.Account.t * Tezos_client.Keyed.t)

  type t =
    { id: string
    ; port: int option
    ; endpoint: int
    ; protocol: Tezos_protocol.Protocol_kind.t
    ; exec: Tezos_executable.t
    ; client: Tezos_client.t
    ; mode: mode
    ; cors_origin: string option
    ; account: Account.t
    ; operation_signers: operation_signer list }

  let operation_signers ~client ~id ~operator ~batch ?finalize ?remove
      ?rejection ?dispatch () : operation_signer list =
    let acc str = Account.gas_account ~client (sprintf "%s-%s" id str) in
    let op_key = acc operator in
    let batch_key = acc batch in
    let or_op_key = function None -> op_key | Some s -> acc s in
    [ Operator op_key; Batch batch_key; Finalize_commitment (or_op_key finalize)
    ; Remove_commitment (or_op_key remove); Rejection (or_op_key rejection)
    ; Dispatch_withdrawal (or_op_key dispatch) ]

  let defult_signers client id : operation_signer list =
    operation_signers ~client ~id ~operator:"operator-signer"
      ~batch:"batch-signer" ~finalize:"finalize-commitment-signer"
      ~remove:"remove-commitment-signer" ~rejection:"rejection-signer"
      ~dispatch:"dispatch-withdrawals-signer" ()

  let operation_signer_map os ~f =
    match os with
    | Operator s
     |Batch s
     |Finalize_commitment s
     |Remove_commitment s
     |Rejection s
     |Dispatch_withdrawal s ->
        f s

  let make_path p ~config t =
    Paths.root config // sprintf "tx-rollup-%s" t.id // p

  let data_dir config t = make_path "data-dir" ~config t
  let exec_path config t = make_path "exec" ~config t

  let mode_string = function
    | Observer -> "observer"
    | Accuser -> "accuser"
    | Batcher -> "batcher"
    | Maintenance -> "maintenance"
    | Operator -> "operator"
    | Custom -> "custom "

  let make ?id ?port ~endpoint ~protocol ~exec ~client ~mode ?cors_origin
      ~account ?operation_signers () : t =
    let name =
      sprintf "%s-%s-node-%s" account.Account.name (mode_string mode)
        (Option.value id ~default:"000") in
    { id= name
    ; port
    ; endpoint
    ; protocol
    ; exec
    ; client
    ; mode
    ; cors_origin
    ; account
    ; operation_signers=
        Option.value operation_signers ~default:(defult_signers client name) }

  open Tezos_executable.Make_cli

  let call state t command =
    let client_dir = Tezos_client.base_dir ~state t.client in
    Tezos_executable.call state t.exec ~protocol_kind:t.protocol
      ~path:(exec_path state t // sprintf "exec-toru-%s" t.id)
      ( opt "endpoint" (sprintf "http://localhost:%d" t.endpoint)
      @ opt "base-dir" client_dir @ command )

  let common_options state t =
    let singer_options =
      Tezos_protocol.Account.(
        function
        | Operator (acc, _) -> opt "operator" (name acc)
        | Batch (acc, _) -> opt "batch-signer" (name acc)
        | Finalize_commitment (acc, _) ->
            opt "finalize-commitment-signer" (name acc)
        | Remove_commitment (acc, _) ->
            opt "remove-commitment-signer" (name acc)
        | Rejection (acc, _) -> opt "rejection-signer" (name acc)
        | Dispatch_withdrawal (acc, _) ->
            opt "dispatch-withdrawals-signer" (name acc)) in
    let cors_origin =
      match t.cors_origin with
      | Some _ as s -> s
      | None -> Environment_configuration.default_cors_origin state in
    flag "allow-deposit"
    @ opt "data-dir" (data_dir state t)
    @ List.concat_map t.operation_signers ~f:singer_options
    @ Option.value_map cors_origin
        ~f:(fun s ->
          flag "cors-header=content-type" @ Fmt.kstr flag "cors-origin=%s" s )
        ~default:[]

  let init state t =
    call state t
      ( ["init"; mode_string t.mode; "config"; "for"; t.account.address]
      @ flag "force" @ common_options state t )

  let run state t =
    call state t
      ( ["run"; mode_string t.mode; "for"; t.account.address]
      @ common_options state t )

  let start_script state t =
    let open Genspio.EDSL in
    check_sequence ~verbosity:`Output_all
      [("init node", init state t); ("run node", run state t)]

  let process state t script =
    Running_processes.Process.genspio
      (sprintf "%s-node-for-tx-rollup-%s" (mode_string t.mode) t.account.name)
      (script state t)

  let cmdliner_term state ~extra_doc =
    let open Cmdliner in
    let open Term in
    let docs =
      Manpage_builder.section state ~rank:2 ~name:"TRANSACTIONAL ROLLUP NODE"
    in
    const (fun mode ->
        match mode with
        | "observer" -> Observer
        | "accuser" -> Accuser
        | "batcher" -> Batcher
        | "maintenance" -> Maintenance
        | "custom " -> Custom
        | "operator" | _ -> Operator )
    $ Arg.(
        value
          (opt string "operator"
             (info ~docs ["tx-rollup-node-mode"]
                ~doc:
                  (sprintf
                     "Set the rollup node's `mode` %s. Possible modes include: \
                      operator, observer, accuser, batcher, maintenance and \
                      custom."
                     extra_doc ) ) ))
end

type t =
  { level: int
  ; name: string
  ; node: Tezos_executable.t
  ; client: Tezos_executable.t
  ; mode: Tx_node.mode }

let origination_account ~client name =
  Account.gas_account ~client (sprintf "%s-origination-account" name)

let originate_and_confirm state ~name ~client ~acc ?confirmations () =
  Account.originate state ~name ~client ~acc
  >>= fun res ->
  return (Account.parse_origination ~lines:res#out)
  >>= fun rollup ->
  match rollup with
  | None ->
      System_error.fail_fatalf
        "Tx_rollup.originate_and_confirm - failed to parse rollup."
  | Some acc ->
      Account.confirm state ~client ?confirmations
        ~operation_hash:acc.operation_hash ()
      >>= fun conf -> return (acc, conf#out)

let executables ({client; node; _} : t) = [client; node]

let cmdliner_term base_state ~docs () =
  let open Cmdliner in
  let open Term in
  let extra_doc = Fmt.str " for transactional rollups (requires --tx-rollup)" in
  const (fun tx_rollup node client mode ->
      Option.map tx_rollup ~f:(fun (level, name) ->
          let txr_name =
            match name with None -> "flextesa-tx-rollup" | Some n -> n in
          {level; name= txr_name; node; client; mode} ) )
  $ Arg.(
      value
        (opt
           (some (t2 ~sep:':' int (some string)))
           None
           (info ["tx-rollup"]
              ~doc:"Orginate a transactional rollup `name` at `level`." ~docs
              ~docv:"LEVEL:TX-ROLLUP-NAME" ) ))
  $ Tezos_executable.cli_term ~extra_doc base_state `Tx_rollup_node "tezos"
  $ Tezos_executable.cli_term ~extra_doc base_state `Tx_rollup_client "tezos"
  $ Tx_node.cmdliner_term ~extra_doc base_state
